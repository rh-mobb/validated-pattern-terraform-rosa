######################
# Storage Resources (KMS Keys and EFS)
# Reference: ./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/7.storage.tf
######################

# Get AWS partition (needed for IAM ARNs)
data "aws_partition" "current" {}

######################
# KMS Keys
######################

# KMS key for EBS volume encryption
# Persists through sleep operation (not gated by persists_through_sleep)
resource "aws_kms_key" "ebs" {
  count = var.enable_storage ? 1 : 0

  description             = "KMS key for EBS volumes for cluster ${var.cluster_name}"
  deletion_window_in_days = var.kms_key_deletion_window

  tags = merge(local.common_tags, {
    Name                 = "${var.cluster_name}-ebs-kms-key"
    Purpose              = "EBSEncryption"
    "red-hat"            = "true"
    persists_through_sleep = "true"
  })
}

# KMS key alias for EBS
# Persists through sleep operation (not gated by persists_through_sleep)
resource "aws_kms_alias" "ebs" {
  count = var.enable_storage ? 1 : 0

  name          = "alias/${var.cluster_name}-ebs"
  target_key_id = aws_kms_key.ebs[0].key_id
}

# KMS key for EFS encryption
# Persists through sleep operation (not gated by persists_through_sleep)
resource "aws_kms_key" "efs" {
  count = var.enable_storage && var.enable_efs ? 1 : 0

  description             = "KMS key for EFS encryption for cluster ${var.cluster_name}"
  deletion_window_in_days = var.kms_key_deletion_window

  tags = merge(local.common_tags, {
    Name                 = "${var.cluster_name}-efs-kms-key"
    Purpose              = "EFSEncryption"
    "red-hat"            = "true"
    persists_through_sleep = "true"
  })
}

# KMS key alias for EFS
# Persists through sleep operation (not gated by persists_through_sleep)
resource "aws_kms_alias" "efs" {
  count = var.enable_storage && var.enable_efs ? 1 : 0

  name          = "alias/${var.cluster_name}-efs"
  target_key_id = aws_kms_key.efs[0].key_id
}

######################
# IAM Policies for KMS Access
######################

# IAM policy for KMS access (used by both EBS and EFS CSI drivers)
resource "aws_iam_policy" "kms_csi" {
  count = local.persists_through_sleep && var.enable_storage ? 1 : 0

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
        Resource = concat(
          length(aws_kms_key.ebs) > 0 ? [aws_kms_key.ebs[0].arn] : [],
          length(aws_kms_key.efs) > 0 ? [aws_kms_key.efs[0].arn] : []
        )
      },
      {
        Effect = "Allow"
        Action = [
          "kms:RevokeGrant",
          "kms:CreateGrant",
          "kms:ListGrants"
        ]
        Resource = concat(
          length(aws_kms_key.ebs) > 0 ? [aws_kms_key.ebs[0].arn] : [],
          length(aws_kms_key.efs) > 0 ? [aws_kms_key.efs[0].arn] : []
        )
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
  count = local.persists_through_sleep && var.enable_storage ? 1 : 0

  role       = "${var.cluster_name}-openshift-cluster-csi-drivers-ebs-cloud-credentials"
  policy_arn = aws_iam_policy.kms_csi[0].arn

  depends_on = [
    rhcs_cluster_rosa_hcp.main,
    aws_iam_policy.kms_csi
  ]
}

######################
# EFS Resources
######################

# IAM policy for EFS CSI driver
resource "aws_iam_policy" "efs_csi" {
  count = var.enable_storage && var.enable_efs && local.persists_through_sleep ? 1 : 0

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
  count = var.enable_storage && var.enable_efs && local.persists_through_sleep ? 1 : 0

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

  depends_on = [
    rhcs_cluster_rosa_hcp.main
  ]
}

# Attach EFS CSI policy to EFS CSI role
resource "aws_iam_role_policy_attachment" "efs_csi" {
  count = var.enable_storage && var.enable_efs && local.persists_through_sleep ? 1 : 0

  role       = aws_iam_role.efs_csi[0].name
  policy_arn = aws_iam_policy.efs_csi[0].arn

  depends_on = [
    aws_iam_role.efs_csi,
    aws_iam_policy.efs_csi
  ]
}

# Attach KMS policy to EFS CSI role
resource "aws_iam_role_policy_attachment" "kms_csi_efs" {
  count = var.enable_storage && var.enable_efs && local.persists_through_sleep ? 1 : 0

  role       = aws_iam_role.efs_csi[0].name
  policy_arn = aws_iam_policy.kms_csi[0].arn

  depends_on = [
    aws_iam_role.efs_csi,
    aws_iam_policy.kms_csi
  ]
}

# EFS file system
# Persists through sleep operation (not gated by persists_through_sleep)
# Note: depends_on cluster is kept for initial creation order, but EFS persists even when cluster is destroyed
resource "aws_efs_file_system" "main" {
  count = var.enable_storage && var.enable_efs ? 1 : 0

  encrypted  = true
  kms_key_id = aws_kms_key.efs[0].arn

  tags = merge(local.common_tags, {
    Name                 = "${var.cluster_name}-rosa-efs"
    persists_through_sleep = "true"
  })

  depends_on = [
    aws_kms_key.efs
  ]
}

# Get the default security group for the cluster
# The security group is tagged with the cluster ID by ROSA
data "aws_security_groups" "cluster_default" {
  count = var.enable_storage && var.enable_efs && local.persists_through_sleep && length(rhcs_cluster_rosa_hcp.main) > 0 ? 1 : 0

  filter {
    name   = "tag:Name"
    values = ["${one(rhcs_cluster_rosa_hcp.main[*].id)}-default-sg"]
  }

  depends_on = [
    rhcs_cluster_rosa_hcp.main
  ]
}

# Security group ingress rules for EFS (port 2049)
# Allow access from private subnets
# Use count instead of for_each because var.private_subnet_cidrs may not be fully known at plan time
resource "aws_vpc_security_group_ingress_rule" "efs" {
  count = var.enable_storage && var.enable_efs && local.persists_through_sleep && length(var.private_subnet_cidrs) > 0 && length(rhcs_cluster_rosa_hcp.main) > 0 ? length(var.private_subnet_cidrs) : 0

  security_group_id = data.aws_security_groups.cluster_default[0].ids[0]
  cidr_ipv4         = var.private_subnet_cidrs[count.index]
  from_port         = 2049
  to_port           = 2049
  ip_protocol       = "tcp"
  description       = "Allow EFS access from ${var.private_subnet_cidrs[count.index]}"

  lifecycle {
    ignore_changes = [
      security_group_id
    ]
  }

  depends_on = [
    aws_efs_file_system.main,
    data.aws_security_groups.cluster_default
  ]
}

# EFS mount targets in each private subnet
# IMPORTANT: EFS mount targets should only be created in PRIVATE subnets, not public subnets
# For public clusters, subnet_ids includes both private and public subnets, so we use private_subnet_ids instead
# Use count instead of for_each because var.private_subnet_ids may not be fully known at plan time
resource "aws_efs_mount_target" "main" {
  count = var.enable_storage && var.enable_efs && local.persists_through_sleep && length(rhcs_cluster_rosa_hcp.main) > 0 ? length(var.private_subnet_ids) : 0

  file_system_id  = aws_efs_file_system.main[0].id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [data.aws_security_groups.cluster_default[0].ids[0]]

  lifecycle {
    ignore_changes = [
      security_groups
    ]
  }

  depends_on = [
    aws_efs_file_system.main,
    data.aws_security_groups.cluster_default
  ]
}