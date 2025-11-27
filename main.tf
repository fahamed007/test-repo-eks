variable "basename" {
  type        = string
  default     = "firoj"
  description = "Tag substring to use for all related resources (e.g.: test1)"
}

variable "eks_node_ami_id" {
  type        = string
  description = "AMI ID for the EKS Node. If this value is not specified, default to latest EKS AMI ID. May force replacement after node group has been created - so beware."
  default     = ""
}

variable "asg_scaledown" {
  default     = "0 22 * * 1-5"
  description = "Cron string to set scaledown period"
  type        = string
}

variable "bootstrap_extra_args" {
  type        = string
  description = "Additional arguments for bootstrap of nodegroup"
  default     = "--use-max-pods false"
}

variable "asg_scaleup" {
  default     = "0 11 * * 1-5"
  description = "Cron string to set scaleup period"
  type        = string
}

variable "eks_version" {
  default     = "1.32"
  description = "EKS version"
  type        = string
}

variable "bdm_ebs_encrypted" {
  default     = true
  description = "Whether the ebs volume should be encrypted"
  type        = bool
}

variable "bdm_ebs_volume_type" {
  default     = "gp3"
  description = "EBS volume type for block device mappings"
  type        = string
}

variable "bdm_ebs_kms_key_id" {
  default     = null
  description = "kms key id to encrypt ebs"
  type        = string
}

variable "eks_managed" {
  default     = true
  description = "switch to setup eks_managed resource or not"
  type        = bool
}

variable "eks_schedule" {
  default     = false
  description = "switch to setup eks_managed weekday schedule"
  type        = bool
}

variable "force_update_version" {
  default     = false
  description = "Force version update if existing pods are unable to be drained due to a pod disruption budget issue."
  type        = bool
}

variable "http_put_response_hop_limit" {
  description = "The hop limit essentially restricts how far metadata requests can travel, enhancing security by limiting potential exposure."
  default     = 2
  type        = number
}

variable "nodegroup_desired" {
  default     = "1"
  description = "node group desired size"
  type        = string
}

variable "nodegroup_instance_type" {
  default     = "t3.medium"
  description = "instance type to use for eks node group"
  type        = string
}

variable "nodegroup_labels" {
  default     = {}
  description = "Key-value map of Node Group Labels"
  type        = map(string)
}

variable "nodegroup_max" {
  default     = "3"
  description = "node group max size"
  type        = string
}

variable "nodegroup_min" {
  default     = "1"
  description = "node group min size"
  type        = string
}

variable "nodegroup_monitoring" {
  default     = false
  description = "whether to enable advanced monitoring"
  type        = bool
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "nodegroup_taints" {
  default     = []
  description = "taints for the nodes within nodegroup"
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
}

variable "enable_bottlerocket" {
  description = "Use bottle rocket user data"
  type        = bool
  default     = false
}

variable "bottlerocket_admin_source" {
  description = "source for bottlerocket admin"
  type        = string
  default     = ""
}

variable "aws_region" {
  type        = string
  description = "AWS Region name"
  default     = "ap-south-1"
}

resource "aws_key_pair" "infra" {
  key_name   = "${var.basename}-keypair"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD3F6tyPEFEzV0LX3X8BsXdMsQz1x2cEikKDEY0aIj41qgxMCP/iteneqXSIFZBp5vizPvaoIR3Um9xK7PGoW8giupGn+EPuxIA4cDM4vzOqOkiMPhz5XK0whEjkVzTo4+S0puvDZuwIsdiW9mxhJc7tgBNL0cYlWSYVkz4G/fslNfRPW5mYAM49f4fhtxPb5ok4Q2Lg9dPKVHO/Bgeu5woMc7RY0p1ej6D4CKFE6lymSDJpW0YHX/wqE9+cfEauh7xZcG0q9t2ta6F6fmX0agvpFyZo8aFbXeUBr7osSCJNgvavWbM/06niWrOvYX2xwWdhXmXSrbX8ZbabVohBK41 email@example"
  tags       = var.tags
}

resource "aws_iam_service_linked_role" "autoscaling" {
  aws_service_name = "autoscaling.amazonaws.com"
  custom_suffix    = var.basename
  description      = "SLR for Auto Scaling with KMS EBS Volumes"
}

data "aws_region" "current" {}

resource "aws_iam_role" "eks_cluster" {
  name_prefix = "${var.basename}-eks-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, {
    Name    = "iam-${var.basename}-eks-cluster"
    Details = "${data.aws_region.current.name}:tf"
  })
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cluster_policy" {
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

  tags = merge(var.tags, {
    Name = "eks-demo-vpc-${var.basename}"
  })
}

resource "aws_subnet" "public1" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                              = "eks-public-1-${var.basename}"
    "kubernetes.io/role/elb"          = "1"
    "kubernetes.io/cluster/${var.basename}-eks" = "owned"
  })
}

resource "aws_subnet" "public2" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                              = "eks-public-2-${var.basename}"
    "kubernetes.io/role/elb"          = "1"
    "kubernetes.io/cluster/${var.basename}-eks" = "owned"
  })
}

resource "aws_subnet" "private1" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name                              = "eks-private-1-${var.basename}"
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${var.basename}-eks" = "owned"
  })
}

resource "aws_subnet" "private2" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name                              = "eks-private-2-${var.basename}"
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${var.basename}-eks" = "owned"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "eks-demo-igw-${var.basename}"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "eks-public-rt-${var.basename}"
  })
}

resource "aws_route_table_association" "public1" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public2" {
  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "eks-nat-eip-${var.basename}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public1.id

  tags = merge(var.tags, {
    Name = "eks-nat-gw-${var.basename}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "eks-private-rt-${var.basename}"
  })
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
  name_prefix = "eks-cluster-sg-${var.basename}"
  description = "Cluster communication with worker nodes"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Allow worker nodes to communicate with the cluster API Server"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "eks-cluster-sg-${var.basename}"
  })
}

resource "aws_eks_cluster" "aws_eks" {
  name     = "${var.basename}-eks"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_version

  vpc_config {
    subnet_ids             = [aws_subnet.public1.id, aws_subnet.public2.id, aws_subnet.private1.id, aws_subnet.private2.id]
    security_group_ids     = [aws_security_group.eks_cluster.id]
    endpoint_public_access = false
    endpoint_private_access = true
  }

  tags = merge(var.tags, {
    Name    = "eks-${var.basename}"
    Details = "${data.aws_region.current.name}:tf"
  })

  depends_on = [aws_iam_role_policy_attachment.amazon_eks_cluster_policy]
}

data "tls_certificate" "ekscert" {
  url = aws_eks_cluster.aws_eks.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "open_connect_provider" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.ekscert.certificates[0].sha1_fingerprint]
  url             = data.tls_certificate.ekscert.url
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.open_connect_provider.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:${var.basename}-aws-node"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.open_connect_provider.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "eks_role" {
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
  name               = "${var.basename}_eksrole"
  tags               = var.tags
}

resource "time_sleep" "wait_for_eks" {
  depends_on      = [aws_eks_cluster.aws_eks]
  create_duration = "30s"
}

resource "null_resource" "update_kubeconfig" {
  depends_on = [time_sleep.wait_for_eks]
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region ${var.aws_region} --name ${var.basename}-eks"
  }
}

data "aws_ami" "amazon_eks_node" {
  most_recent = true
  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.eks_version}-*"]
  }
  owners = ["amazon"]
}

# FIXED: Create encrypted AMI copy with consistent encryption settings
resource "aws_ami_copy" "amazon_encrypted_eks_node" {
  name              = "${var.basename}-amazon-eks-node"
  description       = "Encrypted copy of EKS Node AMI ${var.eks_version}"
  source_ami_id     = var.eks_node_ami_id != "" ? var.eks_node_ami_id : data.aws_ami.amazon_eks_node.id
  source_ami_region = var.aws_region
  
  # FIXED: Encryption settings consistent with launch template
  encrypted   = var.bdm_ebs_encrypted
  kms_key_id  = var.bdm_ebs_encrypted && var.bdm_ebs_kms_key_id != null ? var.bdm_ebs_kms_key_id : null

  tags = merge(var.tags, {
    Name = "${var.basename}-amazon-eks-node"
  })
}

resource "aws_iam_role" "eks_nodegroup_role" {
  name = "${var.basename}_nodegroup_role"
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "amazon_eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodegroup_role.name
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodegroup_role.name
}

resource "aws_iam_role_policy_attachment" "amazon_ec2_container_registry_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodegroup_role.name
}

data "aws_default_tags" "default_tags" {}

locals {
  asg_resources_to_tag          = ["instance", "volume"]
  cluster_id                    = aws_eks_cluster.aws_eks.id
  eks_subnets                   = [aws_subnet.public1.id, aws_subnet.public2.id, aws_subnet.private1.id, aws_subnet.private2.id]
  nodegroup_image_id            = aws_ami_copy.amazon_encrypted_eks_node.id
  nodegroup_key_name            = aws_key_pair.infra.key_name
  eks_endpoint                  = aws_eks_cluster.aws_eks.endpoint
  nodegroup_security_group_ids  = aws_eks_cluster.aws_eks.vpc_config[0].cluster_security_group_id
}

# FIXED: Data source for the copied encrypted AMI
data "aws_ami" "nodegroup_ami" {
  most_recent = true
  filter {
    name   = "image-id"
    values = [local.nodegroup_image_id]
  }
  owners = ["self"]
}

# FIXED: Launch template with consistent encryption settings
resource "aws_launch_template" "nodegroup_launchtemplate" {
  name_prefix   = "${var.basename}_nodegroup_launchtemplate_"
  image_id      = local.nodegroup_image_id
  instance_type = var.nodegroup_instance_type
  key_name      = local.nodegroup_key_name

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = var.http_put_response_hop_limit
  }

  monitoring {
    enabled = var.nodegroup_monitoring
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [local.nodegroup_security_group_ids]
  }

  # FIXED: Block device mappings with consistent encryption matching AMI copy
  dynamic "block_device_mappings" {
    for_each = data.aws_ami.nodegroup_ami.block_device_mappings
    content {
      device_name = block_device_mappings.value.device_name

      ebs {
        encrypted   = var.bdm_ebs_encrypted  # Matches aws_ami_copy encryption
        volume_size = block_device_mappings.value.ebs.volume_size
        volume_type = var.bdm_ebs_volume_type
        kms_key_id  = var.bdm_ebs_encrypted && var.bdm_ebs_kms_key_id != null ? var.bdm_ebs_kms_key_id : null
      }
    }
  }

  dynamic "iam_instance_profile" {
    for_each = var.eks_managed ? [] : [1]
    content {
      name = aws_iam_instance_profile.unmanaged_instance_profile[0].name
    }
  }

  dynamic "tag_specifications" {
    for_each = {
      for type in local.asg_resources_to_tag : type => data.aws_default_tags.default_tags
    }
    content {
      resource_type = tag_specifications.key
      tags = merge(
        tag_specifications.value.tags,
        {
          Name       = "eks-${var.basename}"
          ClusterId  = local.cluster_id
        },
        var.tags
      )
    }
  }

  tags = var.tags
}

resource "aws_eks_node_group" "node_group" {
  count                = var.eks_managed ? 1 : 0
  cluster_name         = local.cluster_id
  node_group_name      = "${var.basename}_node_group"
  node_role_arn        = aws_iam_role.eks_nodegroup_role.arn
  subnet_ids           = local.eks_subnets
  force_update_version = var.force_update_version

  launch_template {
    id      = aws_launch_template.nodegroup_launchtemplate.id
    version = aws_launch_template.nodegroup_launchtemplate.latest_version
  }

  scaling_config {
    desired_size = var.nodegroup_desired
    max_size     = var.nodegroup_max
    min_size     = var.nodegroup_min
  }

  labels = merge(var.nodegroup_labels, {
    Environment = var.basename
    ClusterId   = local.cluster_id
  })

  dynamic "taint" {
    for_each = var.nodegroup_taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  update_config {
    max_unavailable = 1
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [
    aws_iam_role_policy_attachment.amazon_eks_worker_node_policy,
    aws_iam_role_policy_attachment.amazon_eks_cni_policy,
    aws_iam_role_policy_attachment.amazon_ec2_container_registry_read_only,
  ]

  tags = var.tags
}

resource "aws_autoscaling_schedule" "scale_down" {
  count                  = var.eks_schedule && var.eks_managed ? 1 : 0
  scheduled_action_name  = "scale_down"
  min_size               = 0
  max_size               = 1
  desired_capacity       = 0
  recurrence             = var.asg_scaledown
  autoscaling_group_name = aws_eks_node_group.node_group[0].resources[0].autoscaling_groups[0].name
}

resource "aws_autoscaling_schedule" "scale_up" {
  count                  = var.eks_schedule && var.eks_managed ? 1 : 0
  scheduled_action_name  = "scale_up"
  min_size               = var.nodegroup_min
  max_size               = var.nodegroup_max
  desired_capacity       = var.nodegroup_desired
  recurrence             = var.asg_scaleup
  autoscaling_group_name = aws_eks_node_group.node_group[0].resources[0].autoscaling_groups[0].name
}

# Unmanaged node group resources
resource "aws_iam_instance_profile" "unmanaged_instance_profile" {
  count = var.eks_managed ? 0 : 1
  name  = "${var.basename}_instance_profile"
  role  = aws_iam_role.eks_nodegroup_role.name
  tags  = var.tags
}

resource "aws_autoscaling_group" "unmanaged_nodegroup" {
  count = var.eks_managed ? 0 : 1

  name                = "${var.basename}-unmanaged-nodegroup"
  desired_capacity    = var.nodegroup_desired
  max_size            = var.nodegroup_max
  min_size            = var.nodegroup_min
  vpc_zone_identifier = local.eks_subnets

  launch_template {
    id      = aws_launch_template.nodegroup_launchtemplate.id
    version = aws_launch_template.nodegroup_launchtemplate.latest_version
  }

  tag {
    key                 = "kubernetes.io/cluster/${local.cluster_id}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/${local.cluster_id}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.amazon_eks_worker_node_policy,
    aws_iam_role_policy_attachment.amazon_eks_cni_policy,
    aws_iam_role_policy_attachment.amazon_ec2_container_registry_read_only,
  ]

}

# Outputs
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

output "eks_endpoint" {
  value       = aws_eks_cluster.aws_eks.endpoint
  description = "endpoint for the cluster"
}

output "identity" {
  value       = aws_eks_cluster.aws_eks.identity
  description = "Attribute block containing identity provider information"
}

output "node_group_arn" {
  value       = concat(aws_eks_node_group.node_group[*].arn, aws_autoscaling_group.unmanaged_nodegroup[*].arn)
  description = "The node group arn"
}

output "node_group_id" {
  value       = concat(aws_eks_node_group.node_group[*].id, aws_autoscaling_group.unmanaged_nodegroup[*].id)
  description = "The node group id"
}

output "node_group_resources" {
  value       = concat(aws_eks_node_group.node_group[*].resources, [])
  description = "The node group resources"
}

output "node_group_role_arn" {
  value       = aws_iam_role.eks_nodegroup_role.arn
  description = "The node group role arn"
}

output "node_group_role_id" {
  value       = aws_iam_role.eks_nodegroup_role.id
  description = "The node group role id"
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = [aws_subnet.public1.id, aws_subnet.public2.id]
}

output "private_subnet_ids" {
  value = [aws_subnet.private1.id, aws_subnet.private2.id]
}

