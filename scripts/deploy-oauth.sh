#!/bin/bash

set -o errexit # abort on nonzero exitstatus
set -o nounset # abort on unbound variable

set -o allexport && source .env && set +o allexport 

if [ "${k8s_provider}" == "eks" ]; then
    echo "Updating your kube context locally ...."
    aws eks update-kubeconfig --name ${TF_VAR_eks_cluster_name}
    echo "Deploying oauth to ${TF_VAR_eks_cluster_name} ...."
    cd ../oauth/
    mv oauth-proxy-deploy.yaml oauth-proxy-deploy.template
    envsubst < oauth-proxy-deploy.template > oauth-proxy-deploy.yaml
    rm oauth-proxy-deploy.template
    kubectl apply -f oauth-proxy-deploy.yaml
    echo "Deploying oauth ingress to ${TF_VAR_eks_cluster_name} ...."
    cd ../ingress/
    mv oauth-ingress.yaml oauth-ingress.template
    envsubst < oauth-ingress.template > oauth-ingress.yaml
    rm oauth-ingress.template
    kubectl apply -f oauth-ingress.yaml
    echo "Deploying monitoring oauth ingress to ${TF_VAR_eks_cluster_name} ...."
    mv monitoring-ingress-oauth.yaml monitoring-ingress-oauth.template
    envsubst < monitoring-ingress-oauth.template > monitoring-ingress-oauth.yaml
    rm monitoring-ingress-oauth.template
    kubectl apply -f monitoring-ingress-oauth.yaml
else
   echo "You have inputted a non-supported kubernetes provider in your .env"
fi