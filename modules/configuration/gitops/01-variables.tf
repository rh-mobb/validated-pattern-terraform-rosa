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

variable "operator_version" {
  description = <<EOF
  Specific version of the GitOps operator to install (e.g., "1.18.2").
  If specified, this will pin the operator to this exact version via startingCSV.
  If null, the latest version from the specified channel will be installed.
  EOF
  type        = string
  default     = "1.18.2"
  nullable    = true
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
  default     = "Manual"
  nullable    = false

  validation {
    condition     = contains(["Automatic", "Manual"], var.install_plan_approval)
    error_message = "install_plan_approval must be either 'Automatic' or 'Manual'."
  }
}

# Note: The OpenShift provider must be configured at the root level with:
#   provider "openshift" {
#     host     = var.api_url
#     token    = var.k8s_token  # Bearer token for authentication
#     insecure = var.skip_tls_verify
#   }
# This module does not configure the provider - it inherits from the root configuration.

# Provider Configuration (for documentation - actual provider config is at root level)
variable "skip_tls_verify" {
  description = "Skip TLS verification for OpenShift API connection (not recommended for production). This should match the root-level provider configuration."
  type        = bool
  default     = false
  nullable    = false
}

# Labels
variable "labels" {
  description = "Labels to apply to Kubernetes resources"
  type        = map(string)
  default     = {}
  nullable    = false
}
