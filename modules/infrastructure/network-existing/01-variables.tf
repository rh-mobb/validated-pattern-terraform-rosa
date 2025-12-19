variable "name_prefix" {
  description = "Prefix for all resource names (typically cluster name). Used for tagging only."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "Name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "vpc_id" {
  description = "ID of the existing VPC"
  type        = string
  nullable    = false
}

variable "vpc_cidr" {
  description = "CIDR block of the existing VPC (required for outputs and validation)"
  type        = string
  nullable    = false

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_ids" {
  description = "List of existing private subnet IDs (for worker nodes). These will be tagged with kubernetes.io/role/internal-elb"
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.private_subnet_ids) > 0
    error_message = "At least one private subnet ID must be provided."
  }
}

variable "public_subnet_ids" {
  description = "List of existing public subnet IDs (optional, for load balancers). These will be tagged with kubernetes.io/role/elb"
  type        = list(string)
  default     = []
  nullable    = false
}

variable "tags" {
  description = "Additional tags to apply to subnet tags (in addition to ROSA-required tags)"
  type        = map(string)
  default     = {}
  nullable    = false
}
