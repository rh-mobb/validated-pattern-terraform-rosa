variable "cluster_id" {
  description = "ID of the ROSA HCP cluster (null when persists_through_sleep is false, must be set when persists_through_sleep is true)"
  type        = string
  nullable    = true

  validation {
    # When persists_through_sleep is true, resource will be created (count = 1), so cluster_id must not be null
    # When persists_through_sleep is false, resource won't be created (count = 0), so cluster_id can be null
    condition = var.persists_through_sleep == true ? var.cluster_id != null : true
    error_message = "cluster_id must not be null when persists_through_sleep is true (resource will be created)."
  }
}

variable "admin_password" {
  description = <<EOF
  Password for the 'admin' user. Identity provider is not created if unspecified.
  Password must be 14 characters or more, contain one uppercase letter and a symbol or number.
  EOF
  type        = string
  sensitive   = true
  nullable    = false
}

variable "admin_username" {
  description = "Username for the admin user (default: 'admin')"
  type        = string
  default     = "admin"
  nullable    = false
}

variable "admin_group" {
  description = "OpenShift group to add admin user to (default: 'cluster-admins')"
  type        = string
  default     = "cluster-admins"
  nullable    = false
}

# Sleep Protection Variable
variable "persists_through_sleep" {
  description = "Set to false to put cluster in sleep mode (destroys resources). Default true keeps cluster active. To sleep cluster, set this to false and run terraform apply."
  type        = bool
  default     = true
  nullable    = false
}
