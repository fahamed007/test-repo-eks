terraform {
  required_version = ">= 1.9.1, < 2.0.0"

  required_providers {
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = ">= 2.3.7, < 3.0.0"
    }
  }
}
variable "asg_scaledown" {
  default     = "0 22 * * 1-5"
  description = "Cron string to set scaledown period"
  type        = string
}

variable "asg_scaleup" {
  default     = "0 11 * * 1-5"
  description = "Cron string to set scaleup period"
  type        = string
}

variable "basename" {
  description = "Tag substring to use for all related resources (e.g.:  test1)"
  type        = string
  # There should be no default for this variable.
}

variable "bdm_ebs_encrypted" {
  default     = false
  description = "Whether the ebs volume should be encrypted"
  type        = bool
}

variable "bdm_ebs_kms_key_id" {
  default     = null
  description = "kms key id to encrypt ebs"
  type        = string
}

variable "bdm_ebs_volume_type" {
  default     = "gp3"
  description = "Volume type for ebs volume"
  type        = string
}

variable "cluster_id" {
  description = "id of the cluster"
  type        = string
}

variable "eks_certificate_auth" {
  description = "certificate authority for cluster"
  type        = string
}

variable "eks_endpoint" {
  description = "eks endpoint"
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

variable "eks_subnets" {
  description = "subnets for EKS to use"
  type        = list(any)
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

variable "nodegroup_image_id" {
  default     = null
  description = "AMI image id"
  type        = string
}

variable "nodegroup_instance_type" {
  default     = "t3.medium"
  description = "instance type to use for eks node group"
  type        = string
}

variable "nodegroup_key_name" {
  description = "ssh key into instance"
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

variable "nodegroup_security_group_ids" {
  default     = []
  description = "list of security groups"
  type        = list(any)
}

variable "nodegroup_userdata" {
  default     = ""
  description = "user data for the instances within nodegroup"
  type        = string
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

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
/**
 * # Module aws_eks_nodegroup
 *
 * This module creates an eks nodegroup currently on a public subnet.
 */

resource "aws_iam_role" "eks_nodegroup_role" {
  name = "${var.basename}_nodegroup_role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      }
    }
  ]

}
POLICY
  tags               = merge(var.tags)
}

resource "aws_iam_role_policy_attachment" "amzon_eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodegroup_role.name
}

resource "aws_iam_role_policy_attachment" "amzon_eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodegroup_role.name
}

resource "aws_iam_role_policy_attachment" "amzon_ec2_container_registry_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodegroup_role.name
}

data "aws_default_tags" "default_tags" {} # pull tags from the environment so you don't need to add another var

data "cloudinit_config" "userdata" {
  gzip          = false
  base64_encode = true
  # https://docs.aws.amazon.com/eks/latest/userguide/launch-templates.html
  boundary = "==BOUNDARY=="

  part {
    content_type = "text/x-shellscript"
    content      = <<USERDATA
#!/bin/bash
set -ex
/etc/eks/bootstrap.sh ${var.cluster_id} \
  --b64-cluster-ca ${var.eks_certificate_auth} \
  ${var.nodegroup_userdata} \
  --apiserver-endpoint ${var.eks_endpoint}
USERDATA
  }
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

locals {
  asg_resources_to_tag = ["instance", "volume"]
  bottlerocket_userdata = base64encode(templatefile("${path.module}/templates/bottlerocket_config.toml.tpl",
    {
      cluster_name                 = var.cluster_id
      cluster_endpoint             = var.eks_endpoint
      cluster_ca_data              = var.eks_certificate_auth
      admin_container_enabled      = true
      admin_container_superpowered = true
      admin_container_source       = var.bottlerocket_admin_source
  }))
}

data "aws_ami" "nodegroup_ami" {
  filter {
    name   = "image-id"
    values = [var.nodegroup_image_id]
  }
}

#tfsec:ignore:aws-ec2-enforce-launch-config-http-token-imds
resource "aws_launch_template" "nodegroup_launchtemplate" {
  name = "${var.basename}_nodegroup_launchtemplate"

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = var.http_put_response_hop_limit
  }

  dynamic "block_device_mappings" {
    for_each = data.aws_ami.nodegroup_ami.block_device_mappings
    iterator = bdm_name
    content {
      device_name = bdm_name.value.device_name

      ebs {
        encrypted   = var.bdm_ebs_encrypted
        volume_size = bdm_name.value.ebs.volume_size
        volume_type = var.bdm_ebs_volume_type
      }
    }
  }


  dynamic "iam_instance_profile" {
    for_each = var.eks_managed ? [] : [1]
    content {
      name = aws_iam_instance_profile.unmanaged_instance_profile[0].id
    }
  }

  image_id      = var.nodegroup_image_id
  instance_type = var.nodegroup_instance_type
  key_name      = var.nodegroup_key_name

  monitoring {
    enabled = var.nodegroup_monitoring
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = var.nodegroup_security_group_ids
  }

  user_data = var.enable_bottlerocket ? local.bottlerocket_userdata : data.cloudinit_config.userdata.rendered

  # Default tags are currently not propagated to ASG created resources, need to set allocation
  dynamic "tag_specifications" {
    for_each = {
      for type in local.asg_resources_to_tag : type => data.aws_default_tags.default_tags
    }
    content {
      resource_type = tag_specifications.key
      tags = merge(
        tag_specifications.value.tags,
        {
          Name = "eks-${var.basename}"
        },
        var.tags
      )
    }
  }
}

# aws_eks_node_groups depend on the AWSServiceRoleForAutoScaling role being created.
# This is created by the first ASG created in the account.  Currently, 10-13-2022, there is
# no way of adding a non default ServiceRoleForAutoScaling to managed node groups.
# https://github.com/aws/containers-roadmap/issues/1698

resource "aws_eks_node_group" "node_group" {
  count                = var.eks_managed ? 1 : 0
  cluster_name         = var.cluster_id
  node_group_name      = "${var.basename}_node_group"
  node_role_arn        = aws_iam_role.eks_nodegroup_role.arn
  subnet_ids           = var.eks_subnets
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

  labels = merge(var.nodegroup_labels, { Environment = var.basename }, { ClusterId = var.cluster_id })

  dynamic "taint" {
    for_each = var.nodegroup_taints
    content {
      key    = taint.value["key"]
      value  = taint.value["value"]
      effect = taint.value["effect"]
    }
  }

  update_config {
    max_unavailable = 1
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  # https://github.com/hashicorp/terraform/issues/24188
  # dynamic "lifecycle" {
  #   for_each = var.lifecycle_boolean_nodegroup_desired ? [] : [1]
  #   content {
  #     ignore_changes = [scaling_config[0].desired_size]
  #   }
  # }

  # this depends on should now be a module depends on?
  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.amzon_eks_worker_node_policy,
    aws_iam_role_policy_attachment.amzon_eks_cni_policy,
    aws_iam_role_policy_attachment.amzon_ec2_container_registry_read_only,
  ]

  tags = merge(var.tags)
}

resource "aws_autoscaling_schedule" "scale_down" {
  count                  = var.eks_schedule ? 1 : 0
  scheduled_action_name  = "scale_down"
  min_size               = 0
  max_size               = 1
  desired_capacity       = 0
  recurrence             = var.asg_scaledown
  autoscaling_group_name = aws_eks_node_group.node_group[0].resources[0].autoscaling_groups[0].name
}

resource "aws_autoscaling_schedule" "scale_up" {
  count                  = var.eks_schedule ? 1 : 0
  scheduled_action_name  = "scale_up"
  min_size               = var.nodegroup_min
  max_size               = var.nodegroup_max
  desired_capacity       = var.nodegroup_desired
  recurrence             = var.asg_scaleup
  autoscaling_group_name = aws_eks_node_group.node_group[0].resources[0].autoscaling_groups[0].name
}

########## Unmanaged ############
resource "aws_iam_instance_profile" "unmanaged_instance_profile" {
  count = var.eks_managed ? 0 : 1
  name  = "${var.basename}_instance_profile"
  role  = aws_iam_role.eks_nodegroup_role.name
  tags  = merge(var.tags)
}

resource "aws_autoscaling_group" "unmanaged_nodegroup" {
  count               = var.eks_managed ? 0 : 1
  desired_capacity    = var.nodegroup_desired
  max_size            = var.nodegroup_max
  min_size            = var.nodegroup_min
  vpc_zone_identifier = var.eks_subnets

  launch_template {
    id      = aws_launch_template.nodegroup_launchtemplate.id
    version = aws_launch_template.nodegroup_launchtemplate.latest_version
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_id}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.cluster_id}"
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
    aws_iam_role_policy_attachment.amzon_eks_worker_node_policy,
    aws_iam_role_policy_attachment.amzon_eks_cni_policy,
    aws_iam_role_policy_attachment.amzon_ec2_container_registry_read_only,
  ]
}
output "node_group_arn" {
  value       = concat(aws_eks_node_group.node_group[*].arn)
  description = "The node group arn"
}

output "node_group_id" {
  value       = concat(aws_eks_node_group.node_group[*].id)
  description = "The node group id"
}

output "node_group_resources" {
  value       = concat(aws_eks_node_group.node_group[*].resources)
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

