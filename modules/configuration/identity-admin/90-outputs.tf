output "identity_provider_id" {
  description = "ID of the HTPasswd identity provider"
  value       = rhcs_identity_provider.admin.id
  sensitive   = false
}

output "identity_provider_name" {
  description = "Name of the identity provider"
  value       = rhcs_identity_provider.admin.name
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
