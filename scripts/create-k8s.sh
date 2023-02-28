#!/usr/bin/env bash

# This script may be used to initialize and deploy our EKS Kubernetes cluster. At some point, however, we
# should replace this thing with an Ansible playbook.

# It would be nice to provide reasonable defaults for the half-dozen environment variables expected to be
# bound before this script is run; however, that might not be possible. Needs investigation.

set -o pipefail -o errexit -o nounset

readonly progname=$(basename $0)

readonly k8s_root=$(pwd)/..  # we're assuming that this script is run from its home directory (scripts)
readonly k8s_provider=${k8s_provider:-eks}

readonly ingress_dir=$k8s_root/ingress
readonly helm_url='https://charts.jetstack.io'
readonly certman_version='v1.7.1'

readonly nginx_url='https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/aws/deploy.yaml'
readonly prometheus_helm_url='https://prometheus-community.github.io/helm-charts'

readonly cloudwatch_k8s_url='https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest'
readonly cloudwatch_url="$cloudwatch_k8s_url/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluent-bit-quickstart.yaml"

readonly elastic_crds_url='https://download.elastic.co/downloads/eck/2.2.0/crds.yaml'
readonly elastic_op_url='https://download.elastic.co/downloads/eck/2.2.0/operator.yaml'

readonly jaeger_url='https://github.com/jaegertracing/jaeger-operator/releases/download/v1.34.0/jaeger-operator.yaml'

usage() {
    cat <<EOF
Usage: $progname [OPTIONS]

This script may be used to initialize and deploy our EKS Kubernetes cluster. By default, all setup tasks
are run. This may be controlled via the use of command-line arguments.

The following environment variables are expected to be defined for this script to function properly:
  - TF_VAR_eks_cluster
  - TF_VAR_aws_region
  - FluentBitReadFromHead
  - FluentBitHttpPort
  - k8s_provider (optional; defaults to 'eks')

Options:
  -c   Set up the kube context only.
  -e   Set up EKS only.
  -j   Set up Jaeger only.
  -k   Set up Kibana only.
  -l   Set up Elastic only.
  -m   Set up monitoring only.
  -n   Set up nginx only.
  -p   Set up Prometheus only.
  -t   Set up Terraform only.
  -h   Show this message and exit.

Notes:
  - At present, only 'eks' is supported for k8s_provider.
EOF

    exit 1
}

fail() {
    local funcname=''
    
    [[ $1 == -v ]] && { funcname="${FUNCNAME[1]}: "; shift; }
    
    local msg="$@"

    >&2 echo "$progname: $funcname $msg"

    exit 1
}

pushd() {
    local args="$@"

    command pushd $args > /dev/null
}

popd() {
    command popd > /dev/null
}

setup_terraform() {
    [[ $k8s_provider == eks ]] || fail -v "currently, only 'eks' is supported as the Kubernetes provider"

    local tstate=state.tf
    local tform_env=$k8s_root/terraform/environments/$k8s_provider
    
    pushd $tform_env

    mv $tstate state.template
    envsubst < state.template > $tstate
    rm -f state.template 

    terraform init

    echo "Creating or updating K8s cluster now. Please don't interrupt your terminal!"

    terraform apply -auto-approve

    echo "Please wait while your K8s cluster is configured."

    popd
}

setup_kube_context() {
    local issuer='prod-issuer.yaml'
    
    pushd $ingress_dir

    echo "Updating local kube context..."
    
    aws eks update-kubeconfig --name ${TF_VAR_eks_cluster_name}
    
    echo "Deploying cert-manager helm chart to ${TF_VAR_eks_cluster_name}..."

    helm repo add jetstack $helm_url
    helm repo update

    helm upgrade cert-manager jetstack/cert-manager --set installCRDs=true --namespace cert-manager --version $certman_version --install --create-namespace --wait --timeout 8000s --debug 

    echo "Deploying production cluster issuer to ${TF_VAR_eks_cluster_name}..."

    mv $issuer prod-issuer.template
    
    envsubst < prod-issuer.template > $issuer
    rm -f prod-issuer.template

    kubectl apply -f $issuer

    popd
}

setup_nginx() {
    echo "Deploying nginx ingress controller to ${TF_VAR_eks_cluster_name}..."
    
    kubectl apply -f $nginx_url
    sleep 180  # We need a better way to determine readiness
}

setup_prometheus() {
    local values_env='values.yaml'
    
    echo "Deploying kube-prometheus helm chart to ${TF_VAR_eks_cluster_name}..."

    pushd monitoring

    mv $values_env values.template
    envsubst < values.template > $values_env

    rm -f values.template

    helm repo add prometheus-community $prometheus_helm_url
    helm repo update
    helm upgrade kube-prometheus prometheus-community/kube-prometheus-stack --values $values_env --install --create-namespace --namespace=monitoring --wait --timeout 8000s --debug --version '^34'

    popd
}

setup_monitoring() {
    local mon_ingress='monitoring-ingress.yaml'
    
    pushd ingress

    echo "Deploying monitoring ingress to ${TF_VAR_eks_cluster_name}..."

    mv $mon_ingress monitoring-ingress.template
    envsubst < monitoring-ingress.template > $mon_ingress
    
    rm -f monitoring-ingress.template

    kubectl apply -f $mon_ingress

    popd
}

setup_eks_container() {
    echo "Deploying AWS EKS Container Insights to ${TF_VAR_eks_cluster_name}..."
    
    export ClusterName=${TF_VAR_eks_cluster_name}
    export RegionName=<${TF_VAR_aws_region}
    export FluentBitHttpPort='2020'
    export FluentBitReadFromHead='Off'

    [[ $FluentBitReadFromHead = 'On' ]] && FluentBitReadFromTail='Off'|| FluentBitReadFromTail='On'
    [[ -z $FluentBitHttpPort ]] && FluentBitHttpServer='Off' || FluentBitHttpServer='On'

    local cw_data=$(curl --silent $cloudwatch_url)

    [[ -n $cw_data ]] || fail "nothing retrieved from $cloudwatch_url"

    local kubedata=$(sed -e 's/{{cluster_name}}/'${ClusterName}'/' \
                         -e 's/{{region_name}}/'${RegionName}'/' \
                         -e 's/{{http_server_toggle}}/"'${FluentBitHttpServer}'"/' \
                         -e 's/{{http_server_port}}/"'${FluentBitHttpPort}'"/' \
                         -e 's/{{read_from_head}}/"'${FluentBitReadFromHead}'"/' \
                         -e 's/{{read_from_tail}}/"'${FluentBitReadFromTail}'"/' <<< $cw_data)

    echo $kubedata | kubectl apply -f -
}

setup_elastic() {
    local log_cluster='logging-cluster.yaml'
    local log_kibana='logging-kibana.yaml'
    local fluentd_cm='fluentd-cm.yaml'
    local fluentd_ds='fluentd_ds.yaml'

    echo "Deploying elasticsearch to ${TF_VAR_eks_cluster_name}..."

    pushd logging/elasticsearch

    kubectl apply -f $elastic_crds_url
    kubectl apply -f $elastic_op_url

    kubectl create ns logging || true
    kubectl apply -f $log_cluster

    sleep 120  # Need a better way to determine readiness

    kubectl apply -f $log_kibana

    popd
    pushd logging/fluentd

    kubectl apply -f $fluentd_cm
    
    export elasticsearch_password=$(kubectl get secret eck-es-elastic-user -n logging -o go-template='{{.data.elastic | base64decode}}')

    mv $fluentd_ds fluentd-ds.template
    envsubst < fluentd-ds.template > $fluentd_ds

    rm -f fluentd-ds.template

    kubectl apply -f $fluentd_ds

    popd
}

setup_kibana() {
    local ki_ingress='kibana-ingress.yaml'
    
    echo "Deploying kibana ingress to ${TF_VAR_eks_cluster_name}..."

    pushd elasticsearch

    mv $ki_ingress kibana-ingress.template
    envsubst < kibana-ingress.template > $ki_ingress
    rm -f kibana-ingress.template
    
    kubectl apply -f $ki_ingress

    popd
}

setup_jaeger() {
    echo "Deploying jaeger operator to ${TF_VAR_eks_cluster_name}..."

    pushd elasticsearch
    
    kubectl create ns observability || true
    kubectl apply -f $jaeger_url -n observability

    sleep 120  # we need a better way to determine readiness

    popd
}

show_pods() {
    kubectl get pods -n observability
}

sanity_checks() {
    # assuming these directories exist, we're likely ok.
    
    for dir in ingress logging monitoring scripts terraform ; do
        [[ -d $dir ]] || fail -v "$dir is missing from $k8s_root!"
    done
}

error_handler() {
    local rc="$1"
    local line="$2"
    
    >&2 echo "$progname: non-recoverable error at line $line ($rc)."
}

setup_all() {
    setup_terraform
    setup_kube_context
    setup_nginx
    setup_prometheus
    setup_monitoring
    setup_eks_container
    setup_elastic
    setup_kibana
    setup_jaeger
}

# --- main() ---

task='all'

while getopts "cejklmnpth" opt ; do
    case $opt in
        c) task=context ;;
        e) task=eks ;;
        j) task=jaeger ;;
        k) task=kibana ;;
        l) task=elastic ;;
        m) task=monitor ;;
        n) task=nginx ;;
        p) task=prometheus ;;
        t) task=terraform ;;
        h) usage ;;
        *) usage ;;
    esac
done

shift $((OPTIND - 1))

trap 'error_handler $? $LINENO' ERR

case $task in
    all) setup_all ;;
    terraform) setup_terraform ;;
    context) setup_kube_context ;;
    nginx) setup_nginx ;;
    prometheus) setup_prometheus ;;
    monitor) setup_monitoring ;;
    eks) setup_eks_container ;;
    elastic) setup_elastic ;;
    kibana) setup_kibana ;;
    jaeger) setup_jaeger ;;
    *) usage ;;
esac

show_pods

exit 0
