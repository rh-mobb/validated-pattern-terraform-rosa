variable "cluster_id" {
  description = "ID of the ROSA HCP cluster (null when enable_destroy is true, must be set when enable_destroy is false)"
  type        = string
  nullable    = true

  validation {
    # When enable_destroy is false, resource will be created (count = 1), so cluster_id must not be null
    # When enable_destroy is true, resource won't be created (count = 0), so cluster_id can be null
    condition = var.enable_destroy == false ? var.cluster_id != null : true
    error_message = "cluster_id must not be null when enable_destroy is false (resource will be created)."
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

# Destroy Protection Variable
variable "enable_destroy" {
  description = "Set to true to allow resource destruction. Default false prevents accidental destroys. To destroy resources, set this to true and run terraform apply, then terraform destroy."
  type        = bool
  default     = false
  nullable    = false
}
