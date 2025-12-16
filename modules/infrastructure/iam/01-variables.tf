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
