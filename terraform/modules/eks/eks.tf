# EKS Cluster
module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "19.15.3"

  cluster_name                    = "${var.eks_cluster_name}"
  cluster_version                 = "${var.eks_cluster_version}"
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = false

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  create_iam_role = false
  iam_role_arn = aws_iam_role.eks-cluster-iam-role.arn
  create_cluster_security_group= false
  cluster_security_group_id = aws_security_group.eks-cluster-sg.id
}

# EKS Cluster CoreDNS Add On 
resource "aws_eks_addon" "core_dns" {
  cluster_name = "${var.eks_cluster_name}"
  addon_name        = "coredns"
  addon_version     = "v1.10.1-eksbuild.2"
  resolve_conflicts = "OVERWRITE"
  depends_on = [
    aws_eks_node_group.nodes,
  ]
}

# EKS Cluster EBS CSI Driver Add On 
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = "${var.eks_cluster_name}"
  addon_name        = "aws-ebs-csi-driver"
  addon_version     = "v1.20.0-eksbuild.1"
  resolve_conflicts = "OVERWRITE"
  depends_on = [
    aws_eks_node_group.nodes,
  ]
}

# EKS Cluster VPC CNI Cluster Add On
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = "${var.eks_cluster_name}"
  addon_name   = "vpc-cni"
  addon_version     = "v1.13.2-eksbuild.1"
  resolve_conflicts = "OVERWRITE"
  depends_on = [
    aws_eks_node_group.nodes,
  ]
}

# EKS Cluster Kube-Proxy Add On
resource "aws_eks_addon" "kube_proxy" {
  cluster_name = "${var.eks_cluster_name}"
  addon_name   = "kube-proxy"
  addon_version     = "v1.27.3-eksbuild.1"
  resolve_conflicts = "OVERWRITE"
  depends_on = [
    aws_eks_node_group.nodes,
  ]
}

# EKS Node Group
resource "aws_eks_node_group" "nodes" {
  cluster_name    = "${var.eks_cluster_name}"
  node_group_name = var.eks_node_groupname
  node_role_arn   = aws_iam_role.eks-nodegroup-iam-role.arn
  subnet_ids      = module.vpc.private_subnets
  capacity_type   = var.eks_capacity_type 
  ami_type        = var.eks_node_ami_type
  instance_types  = var.eks_node_instance_types
  disk_size       = var.eks_node_disk_size

  scaling_config {
    desired_size = var.eks_node_desired_size
    max_size     = var.eks_node_max_size
    min_size     = var.eks_node_min_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
    module.eks

  ]
}

# EKS Cluster IAM Role
resource "aws_iam_role" "eks-cluster-iam-role" {
  name = "${var.eks_cluster_name}-eks-cluster-iam-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "eks-cluster-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks-cluster-iam-role.name
}

resource "aws_iam_role_policy_attachment" "eks-node-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks-cluster-iam-role.name
}

resource "aws_iam_role_policy_attachment" "eks-node-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks-cluster-iam-role.name
}

resource "aws_iam_role_policy_attachment" "eks-node-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks-cluster-iam-role.name
}

# EKS Node IAM Role
resource "aws_iam_role" "eks-nodegroup-iam-role" {
  name = "${var.eks_cluster_name}-eks-managed-group-node-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "EC2_Access" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
  role       = aws_iam_role.eks-nodegroup-iam-role.name
}
    
resource "aws_iam_role_policy_attachment" "EBS_CSI_Driver_Access" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.eks-nodegroup-iam-role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks-nodegroup-iam-role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks-nodegroup-iam-role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks-nodegroup-iam-role.name
}

resource "aws_iam_role_policy_attachment" "AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.eks-nodegroup-iam-role.name
}

resource "aws_iam_role_policy_attachment" "CloudWatchAgentServerPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.eks-nodegroup-iam-role.name
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  policy_arn = aws_iam_policy.cluster_autoscaler_policy.arn
  role = aws_iam_role.eks-nodegroup-iam-role.name
}
resource "aws_iam_policy" "cluster_autoscaler_policy" {
  name        = "${var.eks_cluster_name}-ClusterAutoScaler"
  description = "Give the worker node running the Cluster Autoscaler access"
policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeLaunchConfigurations",
                "autoscaling:DescribeTags",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:TerminateInstanceInAutoScalingGroup"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}
 
## EKS Cluster Security Group
resource "aws_security_group" "eks-cluster-sg" {
  name          = "eks-cluster"
  description   = "Allow EKS Cluster Traffic"
  vpc_id        = module.vpc.vpc_id

  ingress {
    description = "Allow VPC Traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.aws_vpc_cidr_block}"]
  }

  ingress {
    description = "Allow VPC Traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.aws_vpc_cidr_block}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

## EKS Nodes Security Group
resource "aws_security_group" "eks-node-sg" {
  name          = "eks-node"
  description   = "Allow EKS Node Traffic"
  vpc_id        = module.vpc.vpc_id

ingress {
    description = "Allow VPC Traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.aws_vpc_cidr_block}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  }
}

resource "aws_eks_identity_provider_config" "eks_identity_provider" {
  cluster_name = "${var.eks_cluster_name}"

  oidc {
    client_id                     = "sts.amazonaws.com"
    identity_provider_config_name = "${var.eks_cluster_name}-eks-oidc"
    issuer_url                    = "${module.eks.cluster_oidc_issuer_url}"
  }
}
