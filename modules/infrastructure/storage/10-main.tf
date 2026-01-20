# Storage Module for ROSA HCP
# Creates KMS keys for EBS and EFS encryption, EFS file system, and required IAM policies
# Reference: ./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/7.storage.tf

locals {
  persists_through_sleep = var.persists_through_sleep

  common_tags = merge(var.tags, {
    ManagedBy   = "Terraform"
    ClusterName = var.cluster_name
  })
}

# Get AWS account ID and partition
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

######################
# KMS Keys
######################

# KMS key for EBS volume encryption
resource "aws_kms_key" "ebs" {
  count = local.persists_through_sleep ? 1 : 0

  description             = "KMS key for EBS volumes for cluster ${var.cluster_name}"
  deletion_window_in_days = var.kms_key_deletion_window

  tags = merge(local.common_tags, {
    Name     = "${var.cluster_name}-ebs-kms-key"
    Purpose  = "EBSEncryption"
    "red-hat" = "true"
  })
}

# KMS key alias for EBS
resource "aws_kms_alias" "ebs" {
  count = local.persists_through_sleep ? 1 : 0

  name          = "alias/${var.cluster_name}-ebs"
  target_key_id = aws_kms_key.ebs[0].key_id
}

# KMS key for EFS encryption
resource "aws_kms_key" "efs" {
  count = local.persists_through_sleep ? 1 : 0

  description             = "KMS key for EFS encryption for cluster ${var.cluster_name}"
  deletion_window_in_days = var.kms_key_deletion_window

  tags = merge(local.common_tags, {
    Name     = "${var.cluster_name}-efs-kms-key"
    Purpose  = "EFSEncryption"
    "red-hat" = "true"
  })
}

# KMS key alias for EFS
resource "aws_kms_alias" "efs" {
  count = local.persists_through_sleep ? 1 : 0

  name          = "alias/${var.cluster_name}-efs"
  target_key_id = aws_kms_key.efs[0].key_id
}

######################
# IAM Policies for KMS Access
######################

# IAM policy for KMS access (used by both EBS and EFS CSI drivers)
resource "aws_iam_policy" "kms_csi" {
  count = local.persists_through_sleep ? 1 : 0

  name        = "${var.cluster_name}-rosa-kms-csi"
  path        = "/"
  description = "KMS access policy for EBS and EFS CSI drivers for cluster ${var.cluster_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlainText",
          "kms:DescribeKey"
        ]
        Resource = [
          aws_kms_key.ebs[0].arn,
          aws_kms_key.efs[0].arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:RevokeGrant",
          "kms:CreateGrant",
          "kms:ListGrants"
        ]
        Resource = [
          aws_kms_key.ebs[0].arn,
          aws_kms_key.efs[0].arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DeleteAccessPoint"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

######################
# Attach KMS Policy to EBS CSI Driver Operator Role
######################

# Attach KMS policy to EBS CSI driver operator role
# The role name follows the pattern: {cluster_name}-openshift-cluster-csi-drivers-ebs-cloud-credentials
# This role is created automatically by ROSA when the cluster is created
resource "aws_iam_role_policy_attachment" "kms_csi_ebs" {
  count = local.persists_through_sleep ? 1 : 0

  role       = "${var.cluster_name}-openshift-cluster-csi-drivers-ebs-cloud-credentials"
  policy_arn = aws_iam_policy.kms_csi[0].arn

  depends_on = [
    aws_iam_policy.kms_csi
  ]
}

######################
# EFS Resources
######################

# IAM policy for EFS CSI driver
resource "aws_iam_policy" "efs_csi" {
  count = var.enable_efs && local.persists_through_sleep ? 1 : 0

  name        = "${var.cluster_name}-rosa-efs-csi"
  path        = "/"
  description = "EFS CSI driver policy for cluster ${var.cluster_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets",
          "elasticfilesystem:TagResource",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:CreateAccessPoint"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:RequestTag/efs.csi.aws.com/cluster" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DeleteAccessPoint"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/efs.csi.aws.com/cluster" = "true"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM role for EFS CSI driver
resource "aws_iam_role" "efs_csi" {
  count = var.enable_efs && local.persists_through_sleep ? 1 : 0

  name = "${var.cluster_name}-rosa-efs-csi-role-iam"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(var.oidc_endpoint_url, "https://", "")}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${var.oidc_endpoint_url}:sub" = [
              "system:serviceaccount:openshift-cluster-csi-drivers:aws-efs-csi-driver-operator",
              "system:serviceaccount:openshift-cluster-csi-drivers:aws-efs-csi-driver-controller-sa"
            ]
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach EFS CSI policy to EFS CSI role
resource "aws_iam_role_policy_attachment" "efs_csi" {
  count = var.enable_efs && local.persists_through_sleep ? 1 : 0

  role       = aws_iam_role.efs_csi[0].name
  policy_arn = aws_iam_policy.efs_csi[0].arn

  depends_on = [
    aws_iam_role.efs_csi,
    aws_iam_policy.efs_csi
  ]
}

# Attach KMS policy to EFS CSI role
resource "aws_iam_role_policy_attachment" "kms_csi_efs" {
  count = var.enable_efs && local.persists_through_sleep ? 1 : 0

  role       = aws_iam_role.efs_csi[0].name
  policy_arn = aws_iam_policy.kms_csi[0].arn

  depends_on = [
    aws_iam_role.efs_csi,
    aws_iam_policy.kms_csi
  ]
}

# EFS file system
resource "aws_efs_file_system" "main" {
  count = var.enable_efs && local.persists_through_sleep ? 1 : 0

  encrypted  = true
  kms_key_id = aws_kms_key.efs[0].arn

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-rosa-efs"
  })
}

# Get the default security group for the cluster
# The security group is tagged with the cluster ID by ROSA
# cluster_id is optional - if not provided, EFS resources won't be created
data "aws_security_groups" "cluster_default" {
  count = var.enable_efs && local.persists_through_sleep && var.cluster_id != null ? 1 : 0

  filter {
    name   = "tag:Name"
    values = ["${var.cluster_id}-default-sg"]
  }
}

# Security group ingress rules for EFS (port 2049)
# Allow access from private subnets
# Only create if cluster_id is provided
resource "aws_vpc_security_group_ingress_rule" "efs" {
  for_each = var.enable_efs && local.persists_through_sleep && var.cluster_id != null && length(data.aws_security_groups.cluster_default) > 0 ? toset(var.private_subnet_cidrs) : toset([])

  security_group_id = data.aws_security_groups.cluster_default[0].ids[0]
  cidr_ipv4         = each.value
  from_port         = 2049
  to_port           = 2049
  ip_protocol       = "tcp"
  description       = "Allow EFS access from ${each.value}"

  lifecycle {
    ignore_changes = [
      security_group_id
    ]
  }

  depends_on = [
    aws_efs_file_system.main
  ]
}

# EFS mount targets in each private subnet
# Only create if cluster_id is provided
resource "aws_efs_mount_target" "main" {
  for_each = var.enable_efs && local.persists_through_sleep && var.cluster_id != null && length(data.aws_security_groups.cluster_default) > 0 ? toset(var.private_subnet_ids) : toset([])

  file_system_id  = aws_efs_file_system.main[0].id
  subnet_id       = each.value
  security_groups = [data.aws_security_groups.cluster_default[0].ids[0]]

  lifecycle {
    ignore_changes = [
      security_groups
    ]
  }

  depends_on = [
    aws_efs_file_system.main
  ]
}
