terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "registry.terraform.io/hashicorp/aws"
      version = ">= 4.0.0, < 5.0.0"
    }
    kubectl = {
      source  = "registry.terraform.io/gavinbunney/kubectl"
      version = ">= 1.0.0, < 2.0.0"
    }
    null = {
      source  = "registry.terraform.io/hashicorp/null"
      version = ">= 3.0.0, < 4.0.0"
    }
    time = {
      source  = "registry.terraform.io/hashicorp/time"
      version = ">= 0.0.0, < 1.0.0"
    }
    tls = {
      source  = "registry.terraform.io/hashicorp/tls"
      version = ">= 4.0.0, < 5.0.0"
    }
  }
}

variable "basename" {
  type        = string
  description = "Tag substring to use for all related resources (e.g.:  test1)"
  # There should be no default for this variable.
}


variable "eks_subnets" {
  type        = list(any)
  description = "subnets for EKS to use"
}

variable "eks_version" {
  type        = string
  description = "Version of the eks cluster you are creating"
}


/**
 * # Module aws_eks_cluster
 *
 * This module creates an eks cluster
 */

data "aws_region" "current" {}

resource "aws_iam_role" "eks_cluster" {
  name = "${var.basename}-eks-cluster"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
  tags = {
    Name    = "iam-${var.basename}-eks-cluster"
    Details = "${data.aws_region.current.name}:tf"
  }
}

resource "aws_iam_role_policy_attachment" "amzon_eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}



#####################
# Networking (VPC)  #
#####################

resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "eks-demo-vpc"
  }
}

# Public subnets (for NAT, ALBs, etc.)
resource "aws_subnet" "public1" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name                     = "eks-public-1"
    "kubernetes.io/role/elb" = "1"
    "kubernetes.io/role/elb"                = "1"
    "kubernetes.io/cluster/example-eks"      = "owned"
  }
}

resource "aws_subnet" "public2" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true

  tags = {
    Name                     = "eks-public-2"
    "kubernetes.io/role/elb" = "1"
    "kubernetes.io/role/elb"                = "1"
    "kubernetes.io/cluster/example-eks"      = "owned"
  }
}

# Private subnets for EKS nodes
resource "aws_subnet" "private1" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = false

  tags = {
    Name                              = "eks-private-1"
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/role/elb"                = "1"
    "kubernetes.io/cluster/example-eks"      = "owned"
  }
}

resource "aws_subnet" "private2" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = false

  tags = {
    Name                              = "eks-private-2"
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/role/elb"                = "1"
    "kubernetes.io/cluster/example-eks"      = "owned"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "eks-demo-igw"
  }
}

# Public route table: IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "eks-public-rt"
  }
}

resource "aws_route_table_association" "public1" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public2" {
  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway for private subnets
resource "aws_eip" "nat" {

  tags = {
    Name = "eks-nat-eip"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public1.id

  tags = {
    Name = "eks-nat-gw"
  }

  depends_on = [aws_internet_gateway.this]
}

# Private route table: Internet via NAT
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "eks-private-rt"
  }
}

resource "aws_route_table_association" "private1" {
  subnet_id      = aws_subnet.private1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private2" {
  subnet_id      = aws_subnet.private2.id
  route_table_id = aws_route_table.private.id
}

###########################
# Security Group for EKS  #
###########################

resource "aws_security_group" "eks_cluster" {
  name        = "eks-cluster-sg"
  description = "Cluster communication with worker nodes"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Allow worker nodes to communicate with the cluster API Server"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-cluster-sg"
  }
}



resource "aws_eks_cluster" "aws_eks" {
  name                      = "${var.basename}-eks"
  role_arn                  = aws_iam_role.eks_cluster.arn
  version                   = var.eks_version


  #tfsec:ignore:aws-eks-no-public-cluster-access-to-cidr tfsec:ignore:aws-eks-no-public-cluster-access
  vpc_config {
    subnet_ids              = [aws_subnet.public1.id, aws_subnet.public2.id, aws_subnet.private1.id, aws_subnet.private2.id]
    security_group_ids = [aws_security_group.eks_cluster.id]
    endpoint_public_access  = false
    endpoint_private_access = true
  }

  tags = {
    Name    = "eks-${var.basename}-eks"
    Details = "${data.aws_region.current.name}:tf"
  }

  depends_on = [
    aws_iam_role_policy_attachment.amzon_eks_cluster_policy,
  ]
}

resource "aws_iam_role" "eks_role" {
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
  name               = "${var.basename}_eksrole"
}

resource "time_sleep" "wait_for_eks" {
  depends_on      = [aws_eks_cluster.aws_eks]
  create_duration = "30s"
}

# we had to keep the calico section within this file due to:
# https://github.com/gavinbunney/terraform-provider-kubectl/issues/61
resource "null_resource" "update_kubeconfig" {
  depends_on = [time_sleep.wait_for_eks]
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region us-east-1 --name ${var.basename}-eks"
  }
}

provider "kubectl" {
  apply_retry_count      = 3
  host                   = aws_eks_cluster.aws_eks.endpoint
  load_config_file       = true
  cluster_ca_certificate = base64decode(aws_eks_cluster.aws_eks.certificate_authority[0].data)
}

# on_failure left here to make this idempotent.  This can lead to aws-node not being removed.
resource "null_resource" "remove_aws_node" {
  depends_on = [null_resource.update_kubeconfig]
  provisioner "local-exec" {
    command    = "kubectl delete daemonset aws-node -n kube-system"
    on_failure = continue
  }
}

resource "time_sleep" "wait_for_dns" {
  depends_on      = [aws_eks_cluster.aws_eks]
  create_duration = "1m"
}

resource "null_resource" "calico_vxlan" {
  depends_on = [time_sleep.wait_for_dns]
  provisioner "local-exec" {
    command    = "kubectl apply -f ${path.module}/manifests/calico-vxlan.yaml -n kube-system"
    on_failure = continue
  }
}

resource "null_resource" "disable_src_dest_check" {
  depends_on = [null_resource.calico_vxlan]
  provisioner "local-exec" {
    command    = "kubectl -n kube-system set env daemonset/calico-node FELIX_AWSSRCDSTCHECK=Disable"
    on_failure = continue
  }
}

output "cluster_arn" {
  value       = aws_eks_cluster.aws_eks.arn
  description = "The arn for the cluster"
}

output "cluster_id" {
  value       = aws_eks_cluster.aws_eks.id
  description = "The name of the cluster"
}

output "cluster_iam_role_arn" {
  value       = aws_iam_role.eks_cluster.arn
  description = "the arn for the cluster iam role"
}

output "cluster_iam_role_id" {
  value       = aws_iam_role.eks_cluster.id
  description = "the id for the cluster iam role"
}

output "cluster_security_group_id" {
  value       = aws_eks_cluster.aws_eks.vpc_config[0].cluster_security_group_id
  description = "The id for the cluster security group"
}

output "eks_certificate_auth" {
  value       = aws_eks_cluster.aws_eks.certificate_authority
  description = "The cluster certificate authority"
}

output "eks_endpoint" {
  value       = aws_eks_cluster.aws_eks.endpoint
  description = "endpoint for the cluster"
}

output "identity" {
  value       = aws_eks_cluster.aws_eks.identity
  description = "Attribute block containing identity provider information"
}

