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
  default     = true
  nullable    = false
}

variable "instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "m5.xlarge"
  nullable    = false
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
  default     = null
  nullable    = true
}

variable "openshift_version" {
  description = "OpenShift version to pin"
  type        = string
  default     = null
  nullable    = true
}

variable "service_cidr" {
  description = "CIDR block for services"
  type        = string
  default     = "172.30.0.0/16"
  nullable    = false
}

variable "pod_cidr" {
  description = "CIDR block for pods"
  type        = string
  default     = "10.128.0.0/14"
  nullable    = false
}

variable "host_prefix" {
  description = "Host prefix for subnet allocation"
  type        = number
  default     = 23
  nullable    = false
}

variable "fips" {
  description = "Enable FIPS 140-2 compliance"
  type        = bool
  default     = false
  nullable    = false
}

variable "flow_log_s3_bucket" {
  description = "S3 bucket name for VPC Flow Logs"
  type        = string
  default     = null
  nullable    = true
}

variable "tags" {
  description = "Tags to apply to all resources (from terraform.tfvars)"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "tags_override" {
  description = <<EOF
  Optional override for tags. If set, this value will be used instead of the tags variable.
  Useful for setting tags via environment variables (TF_VAR_tags_override).

  Can be provided via:
  - Environment variable: TF_VAR_tags_override (JSON format: '{"key":"value"}')
  - terraform.tfvars file
  EOF
  type        = map(string)
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

variable "admin_username" {
  description = "Admin username for cluster authentication"
  type        = string
  default     = "admin"
  nullable    = false
}

variable "admin_password_override" {
  description = <<EOF
  Optional override for admin password. If not set, a random password will be generated and stored in AWS Secrets Manager.
  Password must be 14 characters or more, contain one uppercase letter and a symbol or number.

  Can be provided via:
  - terraform.tfvars file (not recommended for production)
  - Environment variable: TF_VAR_admin_password_override

  Note: The password is never output by Terraform. Use AWS CLI to retrieve it:
    aws secretsmanager get-secret-value --secret-id <secret_arn> --query SecretString --output text
  EOF
  type        = string
  sensitive   = true
  default     = null
  nullable    = true
}

variable "enable_bastion" {
  description = <<EOF
  Enable bastion host for secure access to private cluster.

  WARNING: This bastion is provided for development and demonstration purposes only.
  For production deployments, use AWS Transit Gateway, Direct Connect, or VPN connections instead.
  EOF
  type        = bool
  default     = true
  nullable    = false
}

variable "bastion_public_ip" {
  description = "Whether the bastion should have a public IP address. If false, access is via SSM Session Manager only (more secure). For egress-zero, this should always be false."
  type        = bool
  default     = false
  nullable    = false
}

variable "bastion_public_ssh_key" {
  description = "Path to SSH public key file for bastion access"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
  nullable    = false
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
