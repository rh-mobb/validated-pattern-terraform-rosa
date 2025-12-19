variable "name_prefix" {
  description = "Prefix for all resource names (typically cluster name). Ensures unique resource names across clusters."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "Name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  nullable    = false

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

# Note: availability_zones are automatically determined from AWS data source based on multi_az setting

variable "multi_az" {
  description = "Create resources across multiple availability zones for high availability"
  type        = bool
  default     = true
  nullable    = false
}

variable "subnet_cidr_size" {
  description = "CIDR size for each subnet (e.g., 20 for /20). If not provided, will be automatically calculated based on VPC CIDR size and number of subnets needed. Must be larger than VPC CIDR size."
  type        = number
  default     = null
  nullable    = true

  validation {
    condition     = var.subnet_cidr_size == null || (var.subnet_cidr_size > 16 && var.subnet_cidr_size <= 28)
    error_message = "Subnet CIDR size must be between 17 and 28 if provided."
  }
}

variable "flow_log_s3_bucket" {
  description = "S3 bucket name for VPC Flow Logs (optional)"
  type        = string
  default     = null
  nullable    = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "cluster_id" {
  description = "Optional ROSA HCP cluster ID. If provided, will look up the ROSA-created VPC endpoint for API server access. Used for visibility and validation that NACL rules allow traffic to it."
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

variable "enable_destroy_network" {
  description = "Override enable_destroy for network resources. If null, uses enable_destroy value. Allows destroying network resources while preserving other resources."
  type        = bool
  default     = null
  nullable    = true
}
