#!/bin/bash

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
else
   echo "You have inputted a non-supported kubernetes provider in your .env"
fi
