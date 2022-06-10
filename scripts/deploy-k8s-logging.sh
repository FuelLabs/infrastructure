#!/bin/bash

set -o errexit # abort on nonzero exitstatus
set -o nounset # abort on unbound variable

set -o allexport && source .env && set +o allexport 

if [ "${k8s_provider}" == "eks" ]; then
    echo " ...."
    echo "Updating your kube context locally ...."
    aws eks update-kubeconfig --name ${TF_VAR_eks_cluster_name}
    cd ../logging/elasticsearch
    echo "Deploying logging to ${TF_VAR_eks_cluster_name} ...."
    kubectl create -f https://download.elastic.co/downloads/eck/2.2.0/crds.yaml
    kubectl apply -f https://download.elastic.co/downloads/eck/2.2.0/operator.yam
    kubectl create ns logging
    kubectl apply -f logging-cluster.yaml
    sleep 600
    kubectl apply -f logging-kibana.yaml
    cd ../fluentd/
    kubectl apply -f fluentd-cm.yaml
    export elasticsearch_password=$(kubectl get secret eck-es-elastic-user -n logging -o go-template='{{.data.elastic | base64decode}}')
    mv fluentd-ds.yaml fluentd-ds.template
    envsubst < fluentd-ds.template > fluentd-ds.yaml
    rm fluentd-ds.template
    kubectl apply -f fluentd-ds.yaml
else
   echo "You have inputted a non-supported kubernetes provider in your .env"
fi

