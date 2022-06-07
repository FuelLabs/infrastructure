#!/bin/bash

set -o errexit # abort on nonzero exitstatus
set -o nounset # abort on unbound variable

set -o allexport && source .env && set +o allexport 

if [ "${k8s_provider}" == "eks" ]; then
    echo " ...."
    echo "Updating your kube context locally ...."
    aws eks update-kubeconfig --name ${TF_VAR_eks_cluster_name}
    cd ../logging/elasticsearch/
    echo "Deploying kibana ingress to ${TF_VAR_eks_cluster_name} ...."
    mv kibana-ingress.yaml kibana-ingress.template
    envsubst < kibana-ingress.template > kibana-ingress.yaml
    rm kibana-ingress.template
    kubectl apply -f kibana-ingress.yaml
else
   echo "You have inputted a non-supported kubernetes provider in your .env"
fi
