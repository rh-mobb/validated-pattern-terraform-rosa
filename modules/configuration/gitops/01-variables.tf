# Cluster Information (Required)
variable "cluster_id" {
  description = "ID of the ROSA HCP cluster"
  type        = string
  nullable    = false
}

variable "cluster_name" {
  description = "Name of the ROSA HCP cluster"
  type        = string
  nullable    = false
}

variable "api_url" {
  description = "API URL of the cluster (for oc login)"
  type        = string
  nullable    = false
}

# Authentication (Required)
variable "admin_username" {
  description = "Admin username for cluster authentication"
  type        = string
  default     = "admin"
  nullable    = false
}

variable "admin_password" {
  description = "Admin password for cluster authentication"
  type        = string
  sensitive   = true
  nullable    = false
}

# GitOps Configuration
variable "deploy_gitops" {
  description = "Whether to deploy the OpenShift GitOps operator"
  type        = bool
  default     = true
  nullable    = false
}

variable "gitops_namespace" {
  description = "Namespace for the GitOps operator"
  type        = string
  default     = "openshift-gitops-operator"
  nullable    = false
}

variable "operator_channel" {
  description = "Channel for the GitOps operator subscription (latest, stable, etc.)"
  type        = string
  default     = "latest"
  nullable    = false
}

variable "operator_source" {
  description = "Operator source catalog (redhat-operators, certified-operators, etc.)"
  type        = string
  default     = "redhat-operators"
  nullable    = false
}

variable "install_plan_approval" {
  description = "Install plan approval strategy (Automatic or Manual)"
  type        = string
  default     = "Automatic"
  nullable    = false

  validation {
    condition     = contains(["Automatic", "Manual"], var.install_plan_approval)
    error_message = "install_plan_approval must be either 'Automatic' or 'Manual'."
  }
}

# Note: wait_timeout removed - Kubernetes provider handles waiting automatically
# The provider will wait for resources to be ready based on wait conditions

# Kubernetes Provider Configuration
variable "skip_tls_verify" {
  description = "Skip TLS verification for Kubernetes API connection (not recommended for production)"
  type        = bool
  default     = false
  nullable    = false
}

# Tags
variable "tags" {
  description = "Tags to apply to resources (for documentation purposes)"
  type        = map(string)
  default     = {}
  nullable    = false
}
