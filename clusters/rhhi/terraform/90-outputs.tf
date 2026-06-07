output "tekton_ecr_role_arn" {
  description = "IAM role ARN for Tekton pipeline service account (IRSA)"
  value       = aws_iam_role.tekton_ecr.arn
  sensitive   = false
}

output "ecr_operator_role_arn" {
  description = "IAM role ARN for ECR Secret Operator controller (IRSA)"
  value       = aws_iam_role.ecr_operator.arn
  sensitive   = false
}

output "ecr_repository_prefix" {
  description = "ECR pull-through cache repository prefix"
  value       = var.ecr_repository_prefix
  sensitive   = false
}

output "ecr_registry_url" {
  description = "Private ECR registry URL for the AWS account and region"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
  sensitive   = false
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
  sensitive   = false
}

output "aws_region" {
  description = "AWS region"
  value       = var.region
  sensitive   = false
}

output "tekton_namespace" {
  description = "Namespace for Tekton pipeline workloads"
  value       = var.tekton_namespace
  sensitive   = false
}

output "tekton_service_account" {
  description = "Tekton pipeline service account name"
  value       = var.tekton_service_account
  sensitive   = false
}

output "ecr_operator_namespace" {
  description = "Namespace for ECR Secret Operator"
  value       = var.ecr_operator_namespace
  sensitive   = false
}
