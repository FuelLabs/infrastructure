#!/usr/bin/env bash

# This script may be used to initialize and deploy our EKS Kubernetes cluster.

set -o pipefail
set -o errexit

readonly progname=$(basename $0)

readonly k8s_root=$(pwd)/..  # we're assuming that this script is run from its home directory (scripts)

readonly kube_provider="${k8s_provider:-eks}"

readonly tform_env=$k8s_root/terraform/environments/$kube_provider
readonly ingress_dir=$k8s_root/ingress
readonly helm_url='https://charts.jetstack.io'
readonly certman_version='v1.7.1'

readonly nginx_url='https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/aws/deploy.yaml'
readonly prometheus_helm_url='https://prometheus-community.github.io/helm-charts'

readonly cloudwatch_url='https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluent-bit-quickstart.yaml'

readonly elastic_crds_url='https://download.elastic.co/downloads/eck/2.2.0/crds.yaml'
readonly elastic_op_url='https://download.elastic.co/downloads/eck/2.2.0/operator.yaml'

readonly jaeger_url='https://github.com/jaegertracing/jaeger-operator/releases/download/v1.34.0/jaeger-operator.yaml'

: ${TF_VAR_eks_cluster_name:?unbound}
: ${TF_VAR_aws_region:?unbound}
: ${FluentBitReadFromHead:?unbound}
: ${FluentBitHttpPort:?unbound}

usage() {
    cat <<EOF
Usage: $progname [OPTIONS]

This script may be used to initialize and deploy our EKS Kubernetes
cluster.

Options:
  -h   Show this message and exit.
EOF

    exit 1
}

fail() {
    local msg="$@"

    >&2 echo "$progname: $msg"

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
    pushd $tform_env

    mv state.tf state.template
    envsubst < state.template > state.tf
    rm state.template 

    terraform init

    echo "Creating or updating k8s cluster now. Please don't interrupt your terminal!"

    terraform apply -auto-approve

    echo "Please wait while your k8s cluster gets ready..."

    popd
}

setup_kube_context() {
    local issuer='prod-issuer.yaml'
    
    pushd $ingress_dir

    echo "Updating your kube context locally..."
    
    aws eks update-kubeconfig --name ${TF_VAR_eks_cluster_name}
    
    echo "Deploying cert-manager helm chart to ${TF_VAR_eks_cluster_name}."

    helm repo add jetstack $helm_url
    helm repo update

    helm upgrade cert-manager jetstack/cert-manager --set installCRDs=true --namespace cert-manager --version $certman_version --install --create-namespace --wait --timeout 8000s --debug 

    echo "Deploying production cluster issuer to ${TF_VAR_eks_cluster_name}."

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

    rm values.template

    helm repo add prometheus-community $prometheus_helm_url
    helm repo update
    helm upgrade kube-prometheus prometheus-community/kube-prometheus-stack --values $values_env --install --create-namespace --namespace=monitoring --wait --timeout 8000s --debug --version ^34

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

    [[ ${FluentBitReadFromHead} = 'On' ]] && FluentBitReadFromTail='Off'|| FluentBitReadFromTail='On'
    [[ -z ${FluentBitHttpPort} ]] && FluentBitHttpServer='Off' || FluentBitHttpServer='On'
    
    curl $cloudwatch_url | sed 's/{{cluster_name}}/'${ClusterName}'/;s/{{region_name}}/'${RegionName}'/;s/{{http_server_toggle}}/"'${FluentBitHttpServer}'"/;s/{{http_server_port}}/"'${FluentBitHttpPort}'"/;s/{{read_from_head}}/"'${FluentBitReadFromHead}'"/;s/{{read_from_tail}}/"'${FluentBitReadFromTail}'"/' | kubectl apply -f -

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

    sleep 120  # Need a better method to determine readiness

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

    echo "Deploying jaeger operator to ${TF_VAR_eks_cluster_name}..."
    
    kubectl create ns observability || true
    kubectl apply -f $jaeger_url -n observability

    sleep 120  # we need a better way to determine readiness

    kubectl get pods -n observability

    popd
}

sanity_checks() {
    # assuming these directories exist, we're likely ok.
    
    for dir in ingress logging monitoring scripts terraform ; do
        [[ -d $dir ]] || fail "${FUNCNAME[0]: $dir is missing"
    done
}

# --- main() ---

while getopts "h" opt ; do
    case $opt in
        h) usage ;;
        *) usage ;;
    esac
done

shift $((OPTIND - 1))

sanity_checks

setup_terraform
setup_kube_context
setup_nginx
setup_prometheus
setup_monitoring
setup_eks_container
setup_elastic
setup_kibana

exit 0







# --- original ---

set -o errexit # abort on nonzero exitstatus
set -o nounset # abort on unbound variable

echo "This script is to create a new or update existing k8s cluster ...."

set -o allexport && source .env && set +o allexport 

cd ../terraform/environments/${k8s_provider}

mv state.tf state.template

envsubst < state.template > state.tf

rm state.template 

terraform init

echo "Creating or updating k8s cluster now .... please don't interrupt your terminal ...."

terraform apply -auto-approve

echo "Please wait while your k8s cluster gets ready ...."
#sleep 120

echo "Now setting up your k8s cluster ..."

if [ "${k8s_provider}" == "eks" ]; then
    cd ../../../ingress/
    echo "Updating your kube context locally ....."
    aws eks update-kubeconfig --name ${TF_VAR_eks_cluster_name}
    echo "Deploying cert-manager helm chart to ${TF_VAR_eks_cluster_name} ...."
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    helm upgrade cert-manager jetstack/cert-manager --set installCRDs=true --namespace cert-manager --version v1.7.1 --install --create-namespace --wait --timeout 8000s --debug 
    echo "Deploying production cluster issuer to ${TF_VAR_eks_cluster_name} ...."
    mv prod-issuer.yaml prod-issuer.template
    envsubst < prod-issuer.template > prod-issuer.yaml
    rm prod-issuer.template
    kubectl apply -f prod-issuer.yaml
    
    echo "Deploying nginx ingress controller to ${TF_VAR_eks_cluster_name} ...."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/aws/deploy.yaml
    sleep 180
    
    echo "Deploying kube-prometheus helm chart to ${TF_VAR_eks_cluster_name} ...."
    cd ../monitoring/
    mv values.yaml values.template
    envsubst < values.template > values.yaml
    rm values.template
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    helm upgrade kube-prometheus prometheus-community/kube-prometheus-stack --values values.yaml --install --create-namespace --namespace=monitoring --wait --timeout 8000s --debug --version ^34

    cd ../ingress/
    echo "Deploying monitoring ingress to ${TF_VAR_eks_cluster_name} ...."
    mv monitoring-ingress.yaml monitoring-ingress.template
    envsubst < monitoring-ingress.template > monitoring-ingress.yaml
    rm monitoring-ingress.template
    kubectl apply -f monitoring-ingress.yaml

    echo "Deploying AWS EKS Container Insights to ${TF_VAR_eks_cluster_name} ...."
    export ClusterName=${TF_VAR_eks_cluster_name}
    export RegionName=<${TF_VAR_aws_region}
    export FluentBitHttpPort='2020'
    export FluentBitReadFromHead='Off'
    [[ ${FluentBitReadFromHead} = 'On' ]] && FluentBitReadFromTail='Off'|| FluentBitReadFromTail='On'
    [[ -z ${FluentBitHttpPort} ]] && FluentBitHttpServer='Off' || FluentBitHttpServer='On'
    curl https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluent-bit-quickstart.yaml | sed 's/{{cluster_name}}/'${ClusterName}'/;s/{{region_name}}/'${RegionName}'/;s/{{http_server_toggle}}/"'${FluentBitHttpServer}'"/;s/{{http_server_port}}/"'${FluentBitHttpPort}'"/;s/{{read_from_head}}/"'${FluentBitReadFromHead}'"/;s/{{read_from_tail}}/"'${FluentBitReadFromTail}'"/' | kubectl apply -f -

    echo "Deploying elasticsearch to ${TF_VAR_eks_cluster_name} ...."
    cd ../logging/elasticsearch
    kubectl apply -f https://download.elastic.co/downloads/eck/2.2.0/crds.yaml
    kubectl apply -f https://download.elastic.co/downloads/eck/2.2.0/operator.yaml
    kubectl create ns logging || true
    kubectl apply -f logging-cluster.yaml
    sleep 120
    kubectl apply -f logging-kibana.yaml
    cd ../fluentd/
    kubectl apply -f fluentd-cm.yaml
    export elasticsearch_password=$(kubectl get secret eck-es-elastic-user -n logging -o go-template='{{.data.elastic | base64decode}}')
    mv fluentd-ds.yaml fluentd-ds.template
    envsubst < fluentd-ds.template > fluentd-ds.yaml
    rm fluentd-ds.template
    kubectl apply -f fluentd-ds.yaml
    
    echo "Deploying kibana ingress to ${TF_VAR_eks_cluster_name} ...."
    cd ../elasticsearch
    mv kibana-ingress.yaml kibana-ingress.template
    envsubst < kibana-ingress.template > kibana-ingress.yaml
    rm kibana-ingress.template
    kubectl apply -f kibana-ingress.yaml
    echo "Deploying jaeger operator to ${TF_VAR_eks_cluster_name} ...."
    kubectl create ns observability || true
    kubectl apply -f https://github.com/jaegertracing/jaeger-operator/releases/download/v1.34.0/jaeger-operator.yaml -n observability
    sleep 120 
    kubectl get pods -n observability
else
   echo "You have inputted a non-supported kubernetes provider in your .env"
fi
