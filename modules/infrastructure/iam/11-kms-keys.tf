######################
# KMS Keys
# Reference: ./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/7.storage.tf
# KMS keys for EBS, EFS, and ETCD encryption
# These are infrastructure-level resources that can be created independently of the cluster
######################

# KMS key for EBS volume encryption
# Persists through sleep operation (not gated by persists_through_sleep)
resource "aws_kms_key" "ebs" {
  count = var.enable_storage ? 1 : 0

  description             = "KMS key for EBS volumes for cluster ${var.cluster_name}"
  deletion_window_in_days = var.kms_key_deletion_window

  tags = merge(local.common_tags, {
    Name                   = "${var.cluster_name}-ebs-kms-key"
    Purpose                = "EBSEncryption"
    "red-hat"              = "true"
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
# Note: EFS file system is in cluster module, but KMS key is infrastructure-level
resource "aws_kms_key" "efs" {
  count = var.enable_storage ? 1 : 0

  description             = "KMS key for EFS encryption for cluster ${var.cluster_name}"
  deletion_window_in_days = var.kms_key_deletion_window

  tags = merge(local.common_tags, {
    Name                   = "${var.cluster_name}-efs-kms-key"
    Purpose                = "EFSEncryption"
    "red-hat"              = "true"
    persists_through_sleep = "true"
  })
}

# KMS key alias for EFS
# Persists through sleep operation (not gated by persists_through_sleep)
resource "aws_kms_alias" "efs" {
  count = var.enable_storage ? 1 : 0

  name          = "alias/${var.cluster_name}-efs"
  target_key_id = aws_kms_key.efs[0].key_id
}

# KMS key for etcd encryption
# Persists through sleep operation (not gated by persists_through_sleep)
# Reference: ./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/1.main.tf:5-12
resource "aws_kms_key" "etcd" {
  count = var.enable_storage && var.etcd_encryption ? 1 : 0

  description             = "KMS key for etcd encryption for cluster ${var.cluster_name}"
  deletion_window_in_days = var.kms_key_deletion_window

  tags = merge(local.common_tags, {
    Name                   = "${var.cluster_name}-etcd-kms-key"
    Purpose                = "EtcdEncryption"
    "red-hat"              = "true"
    persists_through_sleep = "true"
  })
}

# KMS key alias for etcd
# Persists through sleep operation (not gated by persists_through_sleep)
resource "aws_kms_alias" "etcd" {
  count = var.enable_storage && var.etcd_encryption ? 1 : 0

  name          = "alias/${var.cluster_name}-etcd"
  target_key_id = aws_kms_key.etcd[0].key_id
}
