output "identity_provider_id" {
  description = "ID of the HTPasswd identity provider (null if enable_destroy is true)"
  value       = length(rhcs_identity_provider.admin) > 0 ? one(rhcs_identity_provider.admin[*].id) : null
  sensitive   = false
}

output "identity_provider_name" {
  description = "Name of the identity provider (null if enable_destroy is true)"
  value       = length(rhcs_identity_provider.admin) > 0 ? one(rhcs_identity_provider.admin[*].name) : null
  sensitive   = false
}

output "admin_username" {
  description = "Username of the admin user"
  value       = var.admin_username
  sensitive   = false
}

output "admin_group" {
  description = "Group the admin user belongs to"
  value       = var.admin_group
  sensitive   = false
}
