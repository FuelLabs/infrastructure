#!/bin/bash

echo "Please authenticate to your cluster first with your AWS credentials ...."

echo "Please enter your k8s namespace ...."
read NAMESPACE

echo "Please enter your fuel-core service name e.g. authority, sentry-1, sentry-2 ...."
read SERVICE

export PVC_NAME=$(kubectl get pv | grep $NAMESPACE/$SERVICE-db-pv-claim | awk '{print $1}')

echo "The PVC name you have selected is $PVC_NAME ...."

export ORG_SNAPSHOT_ID=$(kubectl get pv $PVC_NAME --output=jsonpath='{.spec.awsElasticBlockStore.volumeID}')

echo "The Source Snapshot ID you have elected is $ORG_SNAPSHOT_ID ...." 

echo "Creating EBS snapshot of $NAMESPACE/$SERVICE-db-pv-claim ...."
aws ec2 create-snapshot --volume-id $ORG_SNAPSHOT_ID

echo "Enter your SnapshotId from above command output ...."
read FINAL_SNAPSHOT_ID

echo "Wait until progress is 100% before deploying fuel-core ...."
aws ec2 describe-snapshots --snapshot-ids $FINAL_SNAPSHOT_ID
echo ""Make sure to utilize $FINAL_SNAPSHOT_ID for fuel_core_pvc_snapshot_ref in fuel-deployment env file"

