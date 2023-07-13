#!/usr/bin/env bash

set -o pipefail -o errexit -o nounset

readonly progname=$(basename $0)

set -o allexport
source .env
set +o allexport

readonly k8s_root=$(pwd)/..  # we're assuming that this script is run from its home directory (scripts)

export tstate=state.tf
export tform_env=$k8s_root/terraform/environments/$k8s_provider
    
pushd $tform_env

mv $tstate state.template
envsubst < state.template > $tstate
rm -f state.template 

echo "Initializing terraform environment..."

terraform init

echo "Creating or updating K8s cluster now. Please don't interrupt your terminal!"

terraform plan


