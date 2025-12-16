variable "admin_username" {
  description = "Admin username for cluster authentication"
  type        = string
  default     = "admin"
  nullable    = false
}

variable "admin_password" {
  description = <<EOF
  Password for the 'admin' user. Identity provider is not created if unspecified.
  Password must be 14 characters or more, contain one uppercase letter and a symbol or number.

  Can be provided via:
  - terraform.tfvars file (not recommended for production)
  - Environment variable: TF_VAR_admin_password
  EOF
  type        = string
  sensitive   = true
  default     = null
  nullable    = true
}

variable "token" {
  description = <<EOF
  OCM token used to authenticate against the OpenShift Cluster Manager API.
  See https://console.redhat.com/openshift/token/rosa/show to access your token.

  Can be provided via:
  - terraform.tfvars file (not recommended for production)
  - Environment variable: TF_VAR_token
  - Environment variable: OCM_TOKEN or ROSA_TOKEN (provider will check these if token is not set)
  EOF
  type        = string
  sensitive   = true
  nullable    = false
}

variable "skip_tls_verify" {
  description = "Skip TLS verification for Kubernetes API connection (not recommended for production)"
  type        = bool
  default     = false
  nullable    = false
}

variable "deploy_gitops" {
  description = "Whether to deploy the OpenShift GitOps operator"
  type        = bool
  default     = true
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
  nullable    = false
}
