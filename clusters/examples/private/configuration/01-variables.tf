variable "k8s_token" {
  description = <<EOF
  Kubernetes bearer token for cluster authentication.
  Automatically obtained by Makefile via 'oc login' using admin username/password from infrastructure state.

  Can be provided via:
  - Environment variable: TF_VAR_k8s_token
  - Automatically set by Makefile from infrastructure credentials
  EOF
  type        = string
  sensitive   = true
  nullable    = false
  ephemeral   = true  # Don't save in plan files - tokens expire/rotate
}

variable "skip_tls_verify" {
  description = "Skip TLS verification for Kubernetes API connection (not recommended for production)"
  type        = bool
  default     = false
  nullable    = false
}

variable "gitops_enabled" {
  description = "Whether to deploy the OpenShift GitOps operator"
  type        = bool
  default     = true
  nullable    = false
}

variable "gitops_operator_version" {
  description = "Specific version of the GitOps operator to install (e.g., \"1.18.2\"). If null, uses latest from channel."
  type        = string
  default     = "1.18.2"
  nullable    = true
}

variable "labels" {
  description = "Labels to apply to Kubernetes resources (e.g., GitOps operator)"
  type        = map(string)
  default     = {}
  nullable    = false
}
