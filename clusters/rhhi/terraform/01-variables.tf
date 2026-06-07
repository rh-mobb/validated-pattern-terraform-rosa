variable "cluster_name" {
  description = "ROSA HCP cluster name (used for tagging and IAM role naming)"
  type        = string
  nullable    = false
}

variable "region" {
  description = "AWS region for ECR and Secrets Manager resources"
  type        = string
  nullable    = false
}

variable "account_role_prefix" {
  description = "Prefix for ROSA account IAM roles (matches module.iam account_role_prefix)"
  type        = string
  nullable    = false
}

variable "oidc_provider_arn" {
  description = "ARN of the ROSA cluster OIDC provider for IRSA trust policies"
  type        = string
  nullable    = false
}

variable "oidc_endpoint_url" {
  description = "OIDC endpoint URL from ROSA (may include https:// prefix)"
  type        = string
  nullable    = false
}

variable "ecr_repository_prefix" {
  description = "ECR pull-through cache repository prefix (e.g. quay-cache)"
  type        = string
  default     = "quay-cache"
  nullable    = false
}

variable "upstream_registry_url" {
  description = "Upstream container registry URL for pull-through cache (e.g. quay.io)"
  type        = string
  default     = "quay.io"
  nullable    = false
}

variable "enable_ecr_kms_encryption" {
  description = "Use a customer-managed KMS key for ECR repository creation template encryption"
  type        = bool
  default     = false
  nullable    = false
}

variable "persists_through_sleep" {
  description = "Whether cluster IAM roles exist (gate worker ECR policy attachment)"
  type        = bool
  default     = true
  nullable    = false
}

variable "tags" {
  description = "Tags applied to RHHI AWS resources"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "tekton_namespace" {
  description = "OpenShift namespace for Tekton pipeline workloads"
  type        = string
  default     = "user-workload-pipeline"
  nullable    = false
}

variable "tekton_service_account" {
  description = "Service account name used by Tekton pipeline tasks"
  type        = string
  default     = "ecr-pipeline-sa"
  nullable    = false
}

variable "ecr_operator_namespace" {
  description = "Namespace where the ECR Secret Operator controller runs"
  type        = string
  default     = "ecr-secret-operator"
  nullable    = false
}
