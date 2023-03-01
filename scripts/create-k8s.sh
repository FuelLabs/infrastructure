#!/bin/bash -x

# This script may be used to initialize and deploy our EKS Kubernetes cluster. At some point, however, we
# should replace this thing with an Ansible playbook.

# It would be nice to provide reasonable defaults for the half-dozen environment variables expected to be
# bound before this script is run; however, that might not be possible. Needs investigation.

set -o pipefail -o errexit -o nounset

readonly progname=$(basename $0)

set -o allexport
source .env
set +o allexport

readonly k8s_root=$(pwd)/..  # we're assuming that this script is run from its home directory (scripts)

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
  - TF_VAR_eks_cluster_name
  - TF_VAR_aws_region
  - k8s_provider

Options:
  -c   Set up the kube context only.
  -e   Set up EKS only.
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

    echo "Initializing terraform environment..."
    
    terraform init

    echo "Creating or updating K8s cluster now. Please don't interrupt your terminal!"

    terraform apply -auto-approve

    echo "Please wait while your K8s cluster is configured."

    popd
}

setup_kube_context() {
    local issuer='prod-issuer.yaml'
    
    pushd ../ingress

    echo "Updating local kube context..."
    
    aws eks update-kubeconfig --name $TF_VAR_eks_cluster_name --region $TF_VAR_aws_region
    
    echo "Deploying cert-manager helm chart to $TF_VAR_eks_cluster_name..."

    helm repo add jetstack $helm_url
    helm repo update

    helm upgrade cert-manager jetstack/cert-manager --set installCRDs=true --namespace cert-manager --version $certman_version --install --create-namespace --wait --timeout 8000s --debug 

    echo "Deploying production cluster issuer to $TF_VAR_eks_cluster_name..."

    mv $issuer prod-issuer.template
    
    envsubst < prod-issuer.template > $issuer
    rm -f prod-issuer.template

    kubectl apply -f $issuer

    popd
}

setup_nginx() {
    echo "Deploying nginx ingress controller to $TF_VAR_eks_cluster_name..."
    
    kubectl apply -f $nginx_url

    sleep 180  # We need a better way to determine readiness
}

setup_prometheus() {
    local values_env='values.yaml'
    
    echo "Deploying kube-prometheus helm chart to $TF_VAR_eks_cluster_name..."

    pushd ../monitoring

    mv $values_env values.template
    envsubst < values.template > $values_env

    rm -f values.template

    helm repo add prometheus-community $prometheus_helm_url
    helm repo update

    helm delete kube-prometheus --namespace monitoring || echo "$progname: kube-prometheus not loaded: ignoring.."
    helm upgrade kube-prometheus prometheus-community/kube-prometheus-stack --values $values_env --install --create-namespace --namespace=monitoring --wait --timeout 8000s --debug --version ^34

    popd
}

setup_monitoring() {
    local mon_ingress='monitoring-ingress.yaml'
    
    pushd ../ingress

    echo "Deploying monitoring ingress to $TF_VAR_eks_cluster_name..."

    mv $mon_ingress monitoring-ingress.template
    envsubst < monitoring-ingress.template > $mon_ingress
    
    rm -f monitoring-ingress.template

    kubectl apply -f $mon_ingress

    popd
}

setup_eks_container() {
    echo "Deploying AWS EKS Container Insights to $TF_VAR_eks_cluster_name..."
    
    export ClusterName=$TF_VAR_eks_cluster_name
    export RegionName=$TF_VAR_aws_region
    export FluentBitHttpPort='2020'
    export FluentBitReadFromHead='Off'

    [[ $FluentBitReadFromHead = 'On' ]] && FluentBitReadFromTail='Off'|| FluentBitReadFromTail='On'
    [[ -z $FluentBitHttpPort ]] && FluentBitHttpServer='Off' || FluentBitHttpServer='On'

    curl $cloudwatch_url | sed 's/{{cluster_name}}/'${ClusterName}'/;s/{{region_name}}/'${RegionName}'/;s/{{http_server_toggle}}/"'${FluentBitHttpServer}'"/;s/{{http_server_port}}/"'${FluentBitHttpPort}'"/;s/{{read_from_head}}/"'${FluentBitReadFromHead}'"/;s/{{read_from_tail}}/"'${FluentBitReadFromTail}'"/' | kubectl apply -f -
}

show_pods() {
    kubectl get pods -n observability
}

sanity_checks() {
    [[ -n $k8s_provider ]] || fail -v "k8s_provider is unbound!"
    [[ -n $TF_VAR_eks_cluster_name ]] || fail -v "TF_VAR_eks_cluster_name is unbound!"
    [[ -n $TF_VAR_aws_region ]] || fail -v "TF_VAR_aws_region is unbound!"

    [[ $k8s_provider == eks ]] || fail -v "only 'eks' is supported for k8s_provider ($k8s_provider)!"
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
}

# --- main() ---

task='all'

while getopts "cemnpth" opt ; do
    case $opt in
        c) task=context ;;
        e) task=eks ;;
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

sanity_checks

case $task in
    all) setup_all ;;
    terraform) setup_terraform ;;
    context) setup_kube_context ;;
    nginx) setup_nginx ;;
    prometheus) setup_prometheus ;;
    monitor) setup_monitoring ;;
    eks) setup_eks_container ;;
    *) usage ;;
esac

show_pods

exit 0
