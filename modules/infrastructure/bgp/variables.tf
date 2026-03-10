#------------------------------------------------------------------------------
# BGP Module Variables
#------------------------------------------------------------------------------

variable "enabled" {
  description = "Enable BGP infrastructure (route server, TGW, external VPC)"
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "Name of the ROSA cluster"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the ROSA cluster"
  type        = string
}

variable "rosa_vpc_cidr" {
  description = "CIDR block of the ROSA VPC (for routing from external VPC)"
  type        = string
  default     = "10.40.0.0/16"
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
  default     = []
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "rosa_asn" {
  description = "BGP AS number for ROSA cluster (FRR/MetalLB)"
  type        = string
  default     = "65001"
}

variable "route_server_asn" {
  description = "BGP AS number for AWS VPC Route Server"
  type        = string
  default     = "65000"
}

variable "ext_vpc_cidr" {
  description = "CIDR block for the external test VPC"
  type        = string
  default     = "192.168.0.0/16"
}

variable "cudn_cidrs" {
  description = "CIDR blocks for Cluster User Defined Networks"
  type        = list(string)
  default     = ["10.100.0.0/16", "10.200.0.0/16", "10.150.0.0/16"]
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

variable "bastion_public_ssh_key" {
  description = "Path to SSH public key file for bastion access"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

# Destroy Protection Variables
variable "persists_through_sleep" {
  description = "Set to false to put cluster in sleep mode (destroys resources). Default true keeps cluster active."
  type        = bool
  default     = true
  nullable    = false
}

variable "persists_through_sleep_network" {
  description = "Override persists_through_sleep for network resources. If null, uses persists_through_sleep value."
  type        = bool
  default     = null
  nullable    = true
}
