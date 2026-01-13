output "gitops_deployed" {
  description = "Whether GitOps operator was deployed"
  value       = var.gitops_enabled && length(openshift_operator.gitops) > 0
  sensitive   = false
}

output "gitops_namespace" {
  description = "Namespace where GitOps operator is installed"
  value       = var.gitops_enabled && length(openshift_operator.gitops) > 0 ? openshift_operator.gitops[0].namespace : null
  sensitive   = false
}

output "gitops_csv" {
  description = "Name of the installed GitOps operator CSV"
  value       = var.gitops_enabled && length(openshift_operator.gitops) > 0 ? openshift_operator.gitops[0].installed_csv : null
  sensitive   = false
}

output "gitops_csv_phase" {
  description = "Current phase of the GitOps operator CSV"
  value       = var.gitops_enabled && length(openshift_operator.gitops) > 0 ? openshift_operator.gitops[0].csv_phase : null
  sensitive   = false
}

# Admin user and bastion are managed in infrastructure
# Re-export infrastructure outputs for convenience (now passed as input variables)
output "admin_user_created" {
  description = "Whether admin user was created (from infrastructure)"
  value       = var.admin_user_created
  sensitive   = false
}

output "bastion_deployed" {
  description = "Whether bastion host was deployed (from infrastructure)"
  value       = var.bastion_deployed
  sensitive   = false
}

output "bastion_instance_id" {
  description = "Bastion instance ID (from infrastructure)"
  value       = var.bastion_instance_id
  sensitive   = false
}

output "bastion_ssm_command" {
  description = "Command to connect to bastion via SSM Session Manager (from infrastructure)"
  value       = var.bastion_ssm_command
  sensitive   = false
}

output "bastion_sshuttle_command" {
  description = "Command to create VPN-like access via sshuttle (from infrastructure)"
  value       = var.bastion_sshuttle_command
  sensitive   = false
}

# Re-export infrastructure outputs for convenience
output "cluster_id" {
  description = "ROSA HCP Cluster ID"
  value       = var.cluster_id
  sensitive   = false
}

output "api_url" {
  description = "Cluster API URL"
  value       = var.api_url
  sensitive   = false
}

output "console_url" {
  description = "Cluster Console URL"
  value       = var.console_url
  sensitive   = false
}

output "gitops_route_url" {
  description = "Full URL of the GitOps (ArgoCD) server route (null if gitops not enabled, route not found, or operator not ready)"
  value = var.gitops_enabled && var.enable_destroy == false && length(openshift_operator.gitops) > 0 && length(data.kubernetes_resource.gitops_route) > 0 ? try(
    "https://${data.kubernetes_resource.gitops_route[0].object.spec.host}",
    null
  ) : null
  sensitive = false
}

output "gitops_route_host" {
  description = "Hostname of the GitOps (ArgoCD) server route (null if gitops not enabled, route not found, or operator not ready)"
  value = var.gitops_enabled && var.enable_destroy == false && length(openshift_operator.gitops) > 0 && length(data.kubernetes_resource.gitops_route) > 0 ? try(
    data.kubernetes_resource.gitops_route[0].object.spec.host,
    null
  ) : null
  sensitive = false
}
