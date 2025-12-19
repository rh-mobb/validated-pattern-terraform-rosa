variable "cluster_id" {
  description = "ID of the ROSA HCP cluster"
  type        = string
  nullable    = false
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
