# Core cluster information (required - from infrastructure outputs)
variable "api_url" {
  description = "Cluster API URL (from infrastructure outputs)"
  type        = string
  nullable    = false
}

variable "cluster_id" {
  description = "ROSA HCP Cluster ID (from infrastructure outputs)"
  type        = string
  nullable    = false
}

variable "cluster_name" {
  description = "Name of the ROSA HCP cluster (from infrastructure outputs)"
  type        = string
  nullable    = false
}

variable "console_url" {
  description = "Cluster Console URL (from infrastructure outputs)"
  type        = string
  nullable    = false
}

# Optional infrastructure outputs (for re-exporting)
variable "admin_user_created" {
  description = "Whether admin user was created (from infrastructure outputs)"
  type        = bool
  default     = false
  nullable    = false
}

variable "bastion_deployed" {
  description = "Whether bastion host was deployed (from infrastructure outputs)"
  type        = bool
  default     = false
  nullable    = false
}

variable "bastion_instance_id" {
  description = "Bastion instance ID (from infrastructure outputs, optional)"
  type        = string
  default     = null
  nullable    = true
}

variable "bastion_ssm_command" {
  description = "Command to connect to bastion via SSM Session Manager (from infrastructure outputs, optional)"
  type        = string
  default     = null
  nullable    = true
}

variable "bastion_sshuttle_command" {
  description = "Command to create VPN-like access via sshuttle (from infrastructure outputs, optional)"
  type        = string
  default     = null
  nullable    = true
}

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

# Destroy Protection Variable
variable "enable_destroy" {
  description = "Set to true to allow resource destruction. Default false prevents accidental destroys. To destroy resources, set this to true and run terraform apply, then terraform destroy."
  type        = bool
  default     = false
  nullable    = false
}
