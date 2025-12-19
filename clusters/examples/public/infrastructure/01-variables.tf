variable "cluster_name" {
  description = "Name of the ROSA HCP cluster"
  type        = string
  nullable    = false
}

variable "region" {
  description = "AWS region"
  type        = string
  nullable    = false
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  nullable    = false
}

variable "multi_az" {
  description = "Deploy across multiple availability zones"
  type        = bool
  default     = false
  nullable    = false
}

variable "instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "m5.xlarge"
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
  nullable    = false
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


variable "enable_bastion" {
  description = "Whether to deploy a bastion host (for development/demo use only)"
  type        = bool
  default     = false
  nullable    = false
}

variable "bastion_public_ip" {
  description = "Whether to assign a public IP to the bastion host (not recommended for production)"
  type        = bool
  default     = false
  nullable    = false
}

variable "bastion_public_ssh_key" {
  description = "Public SSH key for bastion host (required if bastion_public_ip is true)"
  type        = string
  default     = null
  nullable    = true
}

# Destroy Protection Variables
variable "enable_destroy" {
  description = "Set to true to allow resource destruction. Default false prevents accidental destroys. To destroy resources, set this to true and run terraform apply, then terraform destroy."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_destroy_cluster" {
  description = "Override enable_destroy for cluster resources. If null, uses enable_destroy value."
  type        = bool
  default     = null
  nullable    = true
}

variable "enable_destroy_iam" {
  description = "Override enable_destroy for IAM resources. If null, uses enable_destroy value."
  type        = bool
  default     = null
  nullable    = true
}

variable "enable_destroy_network" {
  description = "Override enable_destroy for network resources. If null, uses enable_destroy value."
  type        = bool
  default     = null
  nullable    = true
}
