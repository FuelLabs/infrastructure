#!/bin/bash

set -o errexit # abort on nonzero exitstatus
set -o nounset # abort on unbound variable

set -o allexport && source .env && set +o allexport 

if [ "${k8s_provider}" == "eks" ]; then
    echo " ...."
    echo "Updating your kube context locally ...."
    aws eks update-kubeconfig --name ${TF_VAR_eks_cluster_name}
    cd ../autoscaling/
    echo "Deploying metrics server to ${TF_VAR_eks_cluster_name} ...."
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    echo "Deploying cluster autoscaler to ${TF_VAR_eks_cluster_name} ...."
    curl https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml | sed "s#<YOUR CLUSTER NAME>#${TF_VAR_eks_cluster_name}\n            - --balance-similar-node-groups\n            - --skip-nodes-with-system-pods=false#g" > cluster-autoscaler-autodiscover.yaml
    kubectl apply -f cluster-autoscaler-autodiscover.yaml
    kubectl apply -f fuel-core-cpu-hpa.yaml
    kubectl apply -f fuel-core-memory-hpa.yaml
else
   echo "You have inputted a non-supported kubernetes provider in your .env"
fi
