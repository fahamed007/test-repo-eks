variable "basename" {
  type        = string
  description = "Tag substring to use for all related resources (e.g.:  test1)"
  # There should be no default for this variable.
  default ="firoj"
}


variable "aws_region" {
  type        = string
  description = "AWS Region name"
  # There should be no default for this variable.
  default ="ap-south-1"
}




resource "aws_key_pair" "infra" {
  key_name   = "${var.basename}_nodegroup_ssh_key"
  public_key = var.ssh_public_key
}

resource "aws_iam_service_linked_role" "autoscaling" {
  aws_service_name = "autoscaling.amazonaws.com"
  custom_suffix    = var.basename
  description      = "SLR for Auto Scaling with KMS EBS Volumes"
}



module "aws_eks_cluster" {
  source              = "./modules/aws/eks_cluster"
  basename            = var.basename
  eks_subnets         = module.vpc.subnets_private
  eks_version         = var.eks_version
  public_access_cidrs = var.public_access_cidrs
}

data "aws_ami" "amazon_eks_node" {
  most_recent = true
  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.eks_version}-*"]
  }
  owners = ["amazon"]
}

# EKS AMI
resource "aws_ami_copy" "amazon_encrypted_eks_node" {
  description       = "A copy of ${startswith(var.eks_node_ami_id, "ami-") ? var.eks_node_ami_id : data.aws_ami.amazon_eks_node.id}"
  encrypted         = true
  name              = "${var.basename}-amazon-eks-node"
  source_ami_id     = startswith(var.eks_node_ami_id, "ami-") ? var.eks_node_ami_id : data.aws_ami.amazon_eks_node.id
  source_ami_region = data.aws_region.current.name
}

# EKS Node Group
module "aws_eks_nodegroup" {
  source                       = "./modules/aws/eks_cluster/eks_nodegroup"
  basename                     = var.basename
  bdm_ebs_encrypted            = false
  cluster_id                   = module.aws_eks_cluster.cluster_id
  eks_certificate_auth         = module.aws_eks_cluster.eks_certificate_auth[0].data
  eks_endpoint                 = module.aws_eks_cluster.eks_endpoint
  eks_managed                  = true
  eks_subnets                  = module.vpc.subnets_private
  nodegroup_image_id           = aws_ami_copy.amazon_encrypted_eks_node.id
  nodegroup_instance_type      = var.nodegroup_instance_type
  nodegroup_key_name           = aws_key_pair.infra.id
  nodegroup_security_group_ids = [module.aws_eks_cluster.cluster_security_group_id]
  nodegroup_userdata           = var.bootstrap_extra_args
}


