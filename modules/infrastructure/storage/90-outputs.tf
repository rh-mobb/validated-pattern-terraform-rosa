output "ebs_kms_key_id" {
  description = "ID of the KMS key for EBS encryption (null if persists_through_sleep is false)"
  value       = local.persists_through_sleep && length(aws_kms_key.ebs) > 0 ? aws_kms_key.ebs[0].key_id : null
  sensitive   = false
}

output "ebs_kms_key_arn" {
  description = "ARN of the KMS key for EBS encryption (null if persists_through_sleep is false)"
  value       = local.persists_through_sleep && length(aws_kms_key.ebs) > 0 ? aws_kms_key.ebs[0].arn : null
  sensitive   = false
}

output "efs_kms_key_id" {
  description = "ID of the KMS key for EFS encryption (null if persists_through_sleep is false)"
  value       = local.persists_through_sleep && length(aws_kms_key.efs) > 0 ? aws_kms_key.efs[0].key_id : null
  sensitive   = false
}

output "efs_kms_key_arn" {
  description = "ARN of the KMS key for EFS encryption (null if persists_through_sleep is false)"
  value       = local.persists_through_sleep && length(aws_kms_key.efs) > 0 ? aws_kms_key.efs[0].arn : null
  sensitive   = false
}

output "efs_file_system_id" {
  description = "ID of the EFS file system (null if persists_through_sleep is false or enable_efs is false)"
  value       = var.enable_efs && local.persists_through_sleep && length(aws_efs_file_system.main) > 0 ? aws_efs_file_system.main[0].id : null
  sensitive   = false
}

output "efs_file_system_arn" {
  description = "ARN of the EFS file system (null if persists_through_sleep is false or enable_efs is false)"
  value       = var.enable_efs && local.persists_through_sleep && length(aws_efs_file_system.main) > 0 ? aws_efs_file_system.main[0].arn : null
  sensitive   = false
}

output "efs_csi_role_arn" {
  description = "ARN of the IAM role for EFS CSI driver (null if persists_through_sleep is false or enable_efs is false)"
  value       = var.enable_efs && local.persists_through_sleep && length(aws_iam_role.efs_csi) > 0 ? aws_iam_role.efs_csi[0].arn : null
  sensitive   = false
}

output "kms_csi_policy_arn" {
  description = "ARN of the IAM policy for KMS CSI access (null if persists_through_sleep is false)"
  value       = local.persists_through_sleep && length(aws_iam_policy.kms_csi) > 0 ? aws_iam_policy.kms_csi[0].arn : null
  sensitive   = false
}
