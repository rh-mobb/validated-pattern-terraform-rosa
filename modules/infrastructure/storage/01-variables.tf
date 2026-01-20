# Required Variables
variable "cluster_name" {
  description = "Name of the ROSA HCP cluster"
  type        = string
  nullable    = false
}

variable "cluster_id" {
  description = "ID of the ROSA HCP cluster (used for security group lookup, required for EFS)"
  type        = string
  nullable    = true
  default     = null
}

variable "oidc_endpoint_url" {
  description = "OIDC endpoint URL (used for IAM role trust policies)"
  type        = string
  nullable    = false
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EFS mount targets"
  type        = list(string)
  nullable    = false
}

variable "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks for EFS security group rules"
  type        = list(string)
  nullable    = false
}

# Optional Variables
variable "enable_efs" {
  description = "Enable EFS file system creation"
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_efs_backup" {
  description = "Enable EFS backup (not yet implemented)"
  type        = bool
  default     = false
  nullable    = false
}

variable "kms_key_deletion_window" {
  description = "Deletion window in days for KMS keys"
  type        = number
  default     = 10
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "persists_through_sleep" {
  description = "Set to false to put cluster in sleep mode (destroys resources). Default true keeps cluster active. To sleep cluster, set this to false and run terraform apply."
  type        = bool
  default     = true
  nullable    = false
}
