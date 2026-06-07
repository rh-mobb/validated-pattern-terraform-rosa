resource "aws_kms_key" "ecr" {
  count = var.enable_ecr_kms_encryption ? 1 : 0

  description             = "KMS key for RHHI ECR pull-through cached repositories (${var.cluster_name})"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name      = "${var.cluster_name}-rhhi-ecr"
    Purpose   = "RHHI-ECR-Encryption"
    ManagedBy = "Terraform"
  })
}

resource "aws_kms_alias" "ecr" {
  count = var.enable_ecr_kms_encryption ? 1 : 0

  name          = "alias/${var.cluster_name}-rhhi-ecr"
  target_key_id = aws_kms_key.ecr[0].key_id
}
