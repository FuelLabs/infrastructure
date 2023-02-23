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

: ${TF_VAR_eks_cluster_name:?unbound}

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

init_terraform() {
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

    [[ -f $issuer ]] || fail "${FUNCNAME[0]}: $issuer is missing"

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

    [[ -e $values_env ]] || fail "${FUNCNAME[0]}: $values_env is missing"
    
    mv $values_env values.template
    envsubst < values.template > $values_env

    rm values.template

    helm repo add prometheus-community $prometheus_helm_url
    helm repo update
    helm upgrade kube-prometheus prometheus-community/kube-prometheus-stack --values $values_env --install --create-namespace --namespace=monitoring --wait --timeout 8000s --debug --version ^34

    popd
}

sanity_checks() {
    [[ -d $tform_env ]] || fail "the terrform environment does not exist: $tform_env"
    [[ -d $ingress_dir ]] || fail "the ingress directory does not exist: $ingress_dir"
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
init_terraform

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
