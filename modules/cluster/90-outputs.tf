output "cluster_id" {
  description = "ID of the ROSA HCP cluster"
  value       = rhcs_cluster_rosa_hcp.main.id
  sensitive   = false
}

output "cluster_name" {
  description = "Name of the ROSA HCP cluster"
  value       = rhcs_cluster_rosa_hcp.main.name
  sensitive   = false
}

output "api_url" {
  description = "API URL of the cluster"
  value       = rhcs_cluster_rosa_hcp.main.api_url
  sensitive   = false
}

output "console_url" {
  description = "Console URL of the cluster"
  value       = rhcs_cluster_rosa_hcp.main.console_url
  sensitive   = false
}

# Note: kubeconfig and cluster_admin_password are not available as direct outputs
# from rhcs_cluster_rosa_hcp resource. Access these through the ROSA CLI or console.

output "state" {
  description = "State of the cluster"
  value       = rhcs_cluster_rosa_hcp.main.state
  sensitive   = false
}
