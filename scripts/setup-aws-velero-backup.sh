#!/bin/bash

echo "Please enter your EKS Cluster Name ...."
read CLUSTER_NAME

echo "Please enter your S3 Backup Bucket Name ...."
read BUCKET

echo "Please enter your S3 Backup Bucket Region ...."
read REGION

echo "Create the S3 Backup Bucket ...."
aws s3api create-bucket \
    --bucket $BUCKET \
    --region $REGION 

echo "Create the S3 Backup Bucket Policy ...."
cat > velero-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeVolumes",
                "ec2:DescribeSnapshots",
                "ec2:CreateTags",
                "ec2:CreateVolume",
                "ec2:CreateSnapshot",
                "ec2:DeleteSnapshot"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:PutObject",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET}"
            ]
        }
    ]
}
EOF

echo "Applying the S3 Backup Bucket Policy  ...."
aws iam put-user-policy \
  --user-name velero \
  --policy-name velero \
  --policy-document file://velero-policy.json

echo "Authenticating to EKS Cluster ...."
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION

echo "Installing Velero on EKS Cluster ...."
  velero install \
    --provider aws \
    --bucket $BUCKET \
    --secret-file ./credentials-velero \
    --backup-location-config region=$REGION \
    --snapshot-location-config region=$REGION \
    --plugins velero/velero-plugin-for-aws:v1.6.0

echo "Please give the list of namespaces to be backed up separated by spaces e.g. test1 test2 ...."
read list $*

echo "Creating Velero Backup Schedules ...."
for i in ${list[@]}; do
    velero schedule create $i-backups --include-namespaces $i --schedule="0 */4 * * *"
done

echo "Viewing Velero Backup Schedules ...."
velero schedule get



