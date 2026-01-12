output "cluster_id" {
  description = "ID of the ROSA HCP cluster (null if enable_destroy is true)"
  value       = length(rhcs_cluster_rosa_hcp.main) > 0 ? one(rhcs_cluster_rosa_hcp.main[*].id) : null
  sensitive   = false
}

output "cluster_name" {
  description = "Name of the ROSA HCP cluster (null if enable_destroy is true)"
  value       = length(rhcs_cluster_rosa_hcp.main) > 0 ? one(rhcs_cluster_rosa_hcp.main[*].name) : null
  sensitive   = false
}

output "api_url" {
  description = "API URL of the cluster (null if enable_destroy is true)"
  value       = length(rhcs_cluster_rosa_hcp.main) > 0 ? one(rhcs_cluster_rosa_hcp.main[*].api_url) : null
  sensitive   = false
}

output "console_url" {
  description = "Console URL of the cluster (null if enable_destroy is true)"
  value       = length(rhcs_cluster_rosa_hcp.main) > 0 ? one(rhcs_cluster_rosa_hcp.main[*].console_url) : null
  sensitive   = false
}

# Note: kubeconfig and cluster_admin_password are not available as direct outputs
# from rhcs_cluster_rosa_hcp resource. Access these through the ROSA CLI or console.

output "state" {
  description = "State of the cluster (null if enable_destroy is true)"
  value       = length(rhcs_cluster_rosa_hcp.main) > 0 ? one(rhcs_cluster_rosa_hcp.main[*].state) : null
  sensitive   = false
}

output "cloudwatch_audit_logging_role_arn" {
  description = "ARN of the IAM role for CloudWatch audit log forwarding (null if enable_destroy is true or enable_audit_logging is false)"
  value       = local.destroy_enabled == false && var.enable_audit_logging && length(aws_iam_role.cloudwatch_audit_logging) > 0 ? aws_iam_role.cloudwatch_audit_logging[0].arn : null
  sensitive   = false
}

output "default_machine_pools" {
  description = "Map of default machine pool IDs keyed by pool name"
  value = local.destroy_enabled == false ? {
    for idx, pool_name in local.hcp_machine_pools : pool_name => rhcs_hcp_machine_pool.default[idx].id
  } : {}
  sensitive = false
}

output "additional_machine_pools" {
  description = "Map of additional machine pool IDs keyed by pool name"
  value = local.destroy_enabled == false ? {
    for k, v in rhcs_hcp_machine_pool.additional : k => v.id
  } : {}
  sensitive = false
}

output "all_machine_pools" {
  description = "Map of all machine pool IDs (default + additional) keyed by pool name"
  value = merge(
    local.destroy_enabled == false ? {
      for idx, pool_name in local.hcp_machine_pools : pool_name => rhcs_hcp_machine_pool.default[idx].id
    } : {},
    local.destroy_enabled == false ? {
      for k, v in rhcs_hcp_machine_pool.additional : k => v.id
    } : {}
  )
  sensitive = false
}
