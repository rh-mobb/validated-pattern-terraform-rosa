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

variable "enable_persistent_dns_domain" {
  description = "Enable persistent DNS domain registration. When true, creates rhcs_dns_domain resource that persists between cluster creations. When false, ROSA uses default DNS domain."
  type        = bool
  default     = false
  nullable    = false
}

variable "additional_machine_pools" {
  description = <<EOF
  Map of additional machine pools to create beyond the default pools.
  Key is the pool name, value is the pool configuration.

  subnet_index: Index of the private subnet to use (0, 1, 2, etc.). Automatically maps to the actual subnet ID.

  Example:
  additional_machine_pools = {
    "compute-0" = {
      subnet_index        = 0
      instance_type       = "m5.2xlarge"
      autoscaling_enabled = true
      min_replicas        = 1
      max_replicas        = 3
    }
  }
  EOF
  type = map(object({
    subnet_index        = number # Index of private subnet (0, 1, 2, etc.)
    instance_type       = string
    autoscaling_enabled = optional(bool, true)
    min_replicas        = optional(number)
    max_replicas        = optional(number)
    replicas            = optional(number) # Only if autoscaling_enabled = false
    auto_repair         = optional(bool, true)
    labels              = optional(map(string), {})
    taints = optional(list(object({
      key          = string
      value        = string
      schedule_type = string # "NoSchedule", "PreferNoSchedule", "NoExecute"
    })), [])
    additional_security_group_ids = optional(list(string), [])
    capacity_reservation_id       = optional(string)
    disk_size                     = optional(number)
    ec2_metadata_http_tokens      = optional(string, "required")
    tags                          = optional(map(string), {})
    version                       = optional(string)
    upgrade_acknowledgements_for  = optional(string)
    kubelet_configs              = optional(string)
    tuning_configs               = optional(list(string), [])
    ignore_deletion_error         = optional(bool, false)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for k, v in var.additional_machine_pools : (
        (v.autoscaling_enabled && v.min_replicas != null && v.max_replicas != null && v.replicas == null) ||
        (!v.autoscaling_enabled && v.replicas != null && v.min_replicas == null && v.max_replicas == null)
      )
    ])
    error_message = "For each additional machine pool: if autoscaling_enabled is true, min_replicas and max_replicas must be set and replicas must be null. If autoscaling_enabled is false, replicas must be set and min_replicas/max_replicas must be null."
  }
}
