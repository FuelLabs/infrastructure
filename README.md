# Fuel Infrastructure

## Prerequisites

Before proceeding make sure to have these software packages installed on your machine:

1) [Helm][helm]: Install latest version of Helm3 for your OS

2) [Terraform][terraform]: Install latest version of Terraform for your OS

3) [kubectl][kubectl-cli]: Install latest version of kubectl

4) [gettext][gettext-cli]: Install gettext for your OS

5) AWS (for EKS deployment only):
- [aws cli v2][aws-cli]: Install latest version of aws cli v2

- [aws-iam-authenticator][iam-auth]: Install to authenticate to EKS cluster via AWS IAM

- IAM user(s) with AWS access keys with following IAM access:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "iam:CreateInstanceProfile",
                "iam:GetPolicyVersion",
                "iam:PutRolePermissionsBoundary",
                "iam:DeletePolicy",
                "iam:CreateRole",
                "iam:AttachRolePolicy",
                "iam:PutRolePolicy",
                "iam:DeleteRolePermissionsBoundary",
                "iam:CreateLoginProfile",
                "iam:ListInstanceProfilesForRole",
                "iam:PassRole",
                "iam:DetachRolePolicy",
                "iam:DeleteRolePolicy",
                "iam:ListAttachedRolePolicies",
                "iam:ListRolePolicies",
                "iam:CreatePolicyVersion",
                "iam:DeleteInstanceProfile",
                "iam:GetRole",
                "iam:GetInstanceProfile",
                "iam:GetPolicy",
                "iam:ListRoles",
                "iam:DeleteRole",
                "iam:CreatePolicy",
                "iam:ListPolicyVersions",
                "iam:UpdateRole",
                "iam:DeleteServiceLinkedRole",
                "iam:GetRolePolicy",
                "iam:DeletePolicyVersion",
                "logs:*",
                "s3:*",
                "autoscaling:*",
                "cloudwatch:*",
                "elasticloadbalancing:*",
                "ec2:*",
                "eks:*"
            ],
            "Resource": "*"
        }
    ]
}
```

Note: Currently only Linux and Unix operating systems are supported for terraform creation of a k8s cluster.

## Deploying k8s Cluster

Currently Fuel Core support terraform based k8s cluster environment deployments for:

1) AWS Elastic Kubernetes Service ([EKS][aws-eks])

### k8s Cluster Configuration

The current k8s cluster configuration is based on a single [env][env-file] file.

You will need to customize the following environment variables as needed (for variables not needed - keep the defaults):

| ENV Variable                   |  Script Usage             | Description                                                                                       |
|--------------------------------|---------------------------|---------------------------------------------------------------------------------------------------|
| kibana_ingress_dns             |  deploy-k8s-logging       | your kibaa ingress dns                                                                            |
| letsencrypt_email              |  create-k8s (all)         | the email address for requesting & renewing your lets encrypt certificate                         |
| grafana_ingress_dns            |  create-k8s (all)         | the custom dns address for the grafana ingress                                                    |
| k8s_provider                   |  create-k8s (all)         | your kubernetes provider name, possible options: eks                                              |
| TF_VAR_aws_environment         |  create-k8s (all)         | environment name                                                                                  |
| TF_VAR_aws_region              |  create-k8s (aws)         | AWS region where you plan to deploy your EKS cluster e.g. us-east-1                               |
| TF_VAR_aws_account_id          |  create-k8s (aws)         | AWS account id                                                                                    |
| TF_state_s3_bucket             |  create-k8s (aws)         | the s3 bucket to store the deployed terraform state                                               |
| TF_state_s3_bucket_key         |  create-k8s (aws)         | the s3 key to save the deployed terraform state.tf                                                |
| TF_VAR_aws_vpc_cidr_block      |  create-k8s (aws)         | AWS vpc cidr block                                                                                |
| TF_VAR_aws_azs                 |  create-k8s (aws)         | A list of regional availability zones for the AWS vpc subnets                                     |
| TF_VAR_aws_public_subnets      |  create-k8s (aws)         | A list of cidr blocks for AWS public subnets                                                      |
| TF_VAR_aws_private_subnets     |  create-k8s (aws)         | A list of cidr blocks for AWS private subnets                                                     | 
| TF_VAR_eks_cluster_name        |  create-k8s (aws)         | EKS cluster name                                                                                  |
| TF_VAR_eks_cluster_version     |  create-k8s (aws)         | EKS cluster version, possible options: 1.18.16, 1.19.8, 1.20.7, 1.21.2                            |
| TF_VAR_eks_node_groupname      |  create-k8s (aws)         | EKS worker node group name                                                                        |
| TF_VAR_eks_node_ami_type       |  create-k8s (aws)         | EKS worker node group AMI type, possible options: AL2_x86_64, AL2_x86_64_GPU, AL2_ARM_64, CUSTOM  | 
| TF_VAR_eks_node_disk_size      |  create-k8s (aws)         | disk size (GiB) for EKS worker nodes                                                              |
| TF_VAR_eks_node_instance_types |  create-k8s (aws)         | A list of instance types for the EKS worker nodes                                                 |
| TF_VAR_eks_node_min_size       |  create-k8s (aws)         | minimum number of eks worker nodes                                                                |
| TF_VAR_eks_node_desired_size   |  create-k8s (aws)         | desired number of eks worker nodes                                                                |
| TF_VAR_eks_node_max_size       |  create-k8s (aws)         | maximum number of eks worker nodes                                                                |
| TF_VAR_eks_capacity_type       |  create-k8s (aws)         | type of capacity associated with the eks node group, possible options: ON_DEMAND, SPOT            |
| TF_VAR_ec2_ssh_key             |  create-k8s (aws)         | ec2 key Pair name for ssh access (must create this key pair in your AWS account before)           |

Notes:

- create-k8s refers to the [create-k8s.sh][create-k8s-sh] script

### k8s Cluster Deployment

Once your env file is updated with your parameters, then run the [create-k8s.sh][create-k8s-sh] to create, deploy, update, and/or setup the k8s cluster to your cloud provider:

```bash
./create-k8s.sh
```
The script will read the "k8s_provider" from the env file and then terraform will automatically create the k8s cluster.

Note:

- During the create-k8s script run, please do not interrupt your terminal as terraform is deploying your infrastructure. 

If you stop the script somehow, terraform may lock the state of configuration.

- If you have deployed an AWS EKS cluster, post creation of the EKS cluster make sure the proper IAM users have access to the EKS cluster via the [aws-auth][add-users-aws-auth] configmap to run the other deployment scripts.

### k8s Cluster Delete

If you need to tear down your entire k8s cluster, just run the [delete-k8s.sh][delete-k8s-sh] script:

```bash
./delete-k8s.sh
```


## Deploying Prometheus-Grafana on k8s

[Prometheus][prometheus] and [Grafana][grafana] are used for monitoring and visualization of the k8s cluster and fuel-core deployment(s) metrics.

The prometheus-grafana stack is deployed to the monitoring namespace via create-k8s script:

In order to access the grafana dashboard, you can will need to run:

```bash
kubectl port-forward svc/kube-prometheus-grafana 3001:80 -n monitoring
```

You can then access the grafana dashboard via localhost:3001. 

For grafana console access, the default username is 'admin' and password is 'prom-operator',

If you want to access the grafana dashboard from a custom DNS address, you need to select 'grafana_ingress_dns' env that is a custom DNS address available in your owned DNS domain.

Check that the grafana ingress is setup via:

```bash
% kubectl get ingress -n monitoring
NAME                 CLASS    HOSTS                    ADDRESS                              PORTS     AGE
monitoring-ingress   <none>   monitoring.example.com   xxxxxx.elb.us-east-1.amazonaws.com   80, 443   19d

```

## Setup Elasticsearch & FluentD Logging on k8s

Once your k8s cluster is deployed, you can setup elasticsearch and fluentd setup on your k8s cluster.

Make sure you have setup the [certificate manager][cert-manager] and [ingress controller][ingress-controller] before you setup logging on your k8s cluster.

Then run the [deploy-k8s-logging][deploy-k8s-logging] script: 

```bash
  ./deploy-k8s-logging.sh
```

This will setup elasticsearch and fluentd on your cluster.

In order to deploy your Kibana ingress, run the [deploy-k8s-kibana-ingress][deploy-k8s-kibana-ingress]

```bash
  ./deploy-k8s-kibana-ingress.sh
```
 
Then to view the kibana ingress:

```bash
  kubectl get ingress kibana-ingress -n logging
```

The default username for kibana dashboard UI will be "elastic" and the password can be gotted from

```bash
  PASSWORD=$(kubectl get secret eck-es-elastic-user -o go-template='{{.data.elastic | base64decode}}')
  echo $PASSWORD
```

## Deploying Jaeger on k8s

Jaeger is an opensource end to end distributed system. There is native support for OpenTelemetry in [Jaeger][jaeger].

Before you deploy Jaeger, make sure to follow the section above to "Setup Elasticsearch & FluentD Logging on k8s". 

The elasticsearch instance is required to deploy Jaeger with an ElasticSearch storage backend. 

To deploy the jaeger operator and instance, simply run the [deploy-jaeger-tracing][deploy-jaeger-tracing]

```bash
  ./deploy-jaeger-tracing.sh
```

Then to view the jaeger ingress:

```bash
  kubectl get ingress jaeger-tracing-ingress -n observability
```

Once Jaeger is setup, you can start to integrate fuel services to send traces Jaeger via [OpenTelemetry SDK][opentelemetry-sdk]

[add-users-aws-auth]: https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html
[aws-cli]: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
[aws-eks]: https://aws.amazon.com/eks/
[cert-manager]: https://cert-manager.io/docs/configuration/acme/
[create-k8s-sh]: https://github.com/FuelLabs/infrastructure/blob/master/scripts/create-k8s.sh
[delete-k8s-sh]: https://github.com/FuelLabs/infrastructure/blob/master/scripts/delete-k8s.sh
[deploy-k8s-kibana-ingress]: https://github.com/FuelLabs/infrastructure/blob/master/scripts/deploy-k8s-kibana-ingress.sh
[deploy-k8s-logging]: https://github.com/FuelLabs/infrastructure/blob/master/scripts/deploy-k8s-logging.sh
[deploy-jaeger-tracing]: https://github.com/FuelLabs/infrastructure/blob/master/scripts/deploy-jaeger-tracing.sh
[docker-desktop]: https://docs.docker.com/engine/install/
[env-file]: https://github.com/FuelLabs/infrastructure/blob/master/scripts/.env
[gettext-cli]: https://www.gnu.org/software/gettext/
[grafana]: https://grafana.com/
[helm]: https://helm.sh/docs/intro/install/
[iam-auth]: https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html
[ingress-controller]: https://github.com/kubernetes/ingress-nginx
[ingress-def]: https://kubernetes.io/docs/concepts/services-networking/ingress/
[jaeger]: https://www.jaegertracing.io/
[jaeger-operator]: https://www.jaegertracing.io/docs/1.34/operator/
[k8s-terraform]: https://github.com/FuelLabs/infrastructure/tree/master/terraform
[kubectl-cli]: https://kubernetes.io/docs/tasks/tools/
[prometheus]: https://prometheus.io/
[terraform]: https://learn.hashicorp.com/tutorials/terraform/install-cli
[opentelemetry-sdk]: https://www.jaegertracing.io/_client_libs/client-libraries/
