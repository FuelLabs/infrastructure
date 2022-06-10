#!/bin/bash

set -o errexit # abort on nonzero exitstatus
set -o nounset # abort on unbound variable

set -o allexport && source .env && set +o allexport 

if [ "${k8s_provider}" == "eks" ]; then
    echo " ...."
    echo "Updating your kube context locally ...."
    aws eks update-kubeconfig --name ${TF_VAR_eks_cluster_name}
    cd ../tracing
    echo "Deploying jaeger operator to ${TF_VAR_eks_cluster_name} ...."
    export elasticsearch_password=$(kubectl get secret eck-es-elastic-user -n logging -o go-template='{{.data.elastic | base64decode}}')
    kubectl create namespace observability
    kubectl create -f https://github.com/jaegertracing/jaeger-operator/releases/download/v1.34.0/jaeger-operator.yaml -n observability
    sleep 180
    echo "Deploying jaeger instance to ${TF_VAR_eks_cluster_name} ...."
    mv jaeger-tracing.yaml jaeger-tracing.template
    envsubst < jaeger-tracing.template > jaeger-tracing.yaml
    rm jaeger-tracing.template
    kubectl apply -f jaeger-tracing.yaml
    sleep 180
    echo "Deploying jaeger ingress to ${TF_VAR_eks_cluster_name} ...."
    mv jaeger-tracing-ingress.yaml jaeger-tracing-ingress.template
    envsubst < jaeger-tracing-ingress.template > jaeger-tracing-ingress.yaml
    rm jaeger-tracing-ingress.template
    kubectl apply -f jaeger-tracing-ingress.yaml
    wait 120
    kubectl get ingress jaeger-tracing-ingress -n observability
else
   echo "You have inputted a non-supported kubernetes provider in your .env"
fi
