#!/bin/bash

set -o errexit # abort on nonzero exitstatus
set -o nounset # abort on unbound variable

set -o allexport && source .env && set +o allexport 

if [ "${k8s_provider}" == "eks" ]; then
    echo " ...."
    echo "Updating your kube context locally ...."
    aws eks update-kubeconfig --name ${TF_VAR_eks_cluster_name}
    cd cd ../security/falco/
    echo "Deploying falco monitoring to ${TF_VAR_eks_cluster_name} ...."
    helm repo add falcosecurity https://falcosecurity.github.io/charts
    helm repo update
    helm upgrade falco falcosecurity/falco \
      --set falcosidekick.enabled=true \
      --set falcosidekick.webui.enabled=true \
      --set auditLog.enabled=true \
      --set falco.jsonOutput=true \
      --set falco.fileOutput.enabled=true \
      --set falcosidekick.config.slack.webhookurl=${slack_api_url} \
      --install \
      --values values.yaml \
      --create-namespace \
      --namespace="falco" \
      --wait \
      --timeout 8000s \
      --debug 
else
   echo "You have inputted a non-supported kubernetes provider in your .env"
fi
