#------------------------------------------------------------------------------
# BGP Security Groups Module Variables
#------------------------------------------------------------------------------

variable "enabled" {
  description = "Enable BGP security groups"
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "Name of the ROSA cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the ROSA cluster"
  type        = string
}

variable "owner_tag" {
  description = "Owner tag for BGP resources"
  type        = string
  default     = "rosa-bgp"
}

variable "project_tag" {
  description = "Project tag for BGP resources"
  type        = string
  default     = "ROSA-Virt BGP"
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
