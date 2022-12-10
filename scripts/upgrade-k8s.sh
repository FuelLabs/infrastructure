#!/bin/bash

set -o errexit # abort on nonzero exitstatus
set -o nounset # abort on unbound variable

echo "This script is to create a upgrade existing k8s cluster ...."

set -o allexport && source .env && set +o allexport 

cd ../terraform/environments/${k8s_provider}

mv state.tf state.template

envsubst < state.template > state.tf

rm state.template 

terraform init

echo "Upgrading k8s cluster now .... please don't interrupt your terminal ...."

terraform apply -auto-approve

echo "k8s cluster is now upgraded ...."
