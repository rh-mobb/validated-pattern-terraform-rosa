variable "cluster_name" {
  description = "Name of the ROSA HCP cluster"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "Cluster name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "account_role_prefix" {
  description = "Prefix for account roles to ensure uniqueness. Defaults to cluster_name"
  type        = string
  default     = null
  nullable    = true
}

variable "operator_role_prefix" {
  description = "Prefix for operator roles to ensure uniqueness. Defaults to cluster_name"
  type        = string
  default     = null
  nullable    = true
}

variable "zero_egress" {
  description = "Enable zero egress mode. When true, attaches AmazonEC2ContainerRegistryReadOnly policy to worker role (required for egress-zero clusters)"
  type        = bool
  default     = false
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
  nullable    = false
}

# Destroy Protection Variables
variable "enable_destroy" {
  description = "Set to true to allow resource destruction. Default false prevents accidental destroys. To destroy resources, set this to true and run terraform apply, then terraform destroy."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_destroy_iam" {
  description = "Override enable_destroy for IAM resources. If null, uses enable_destroy value. Allows destroying IAM roles while preserving OIDC configuration for reuse across clusters."
  type        = bool
  default     = null
  nullable    = true
}
