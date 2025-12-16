output "gitops_deployed" {
  description = "Whether GitOps operator was deployed"
  value       = var.deploy_gitops && length(module.gitops) > 0
  sensitive   = false
}

output "gitops_namespace" {
  description = "Namespace where GitOps operator is installed"
  value       = var.deploy_gitops && length(module.gitops) > 0 ? module.gitops[0].gitops_namespace : null
  sensitive   = false
}

# Admin user and bastion are managed in infrastructure
# Re-export infrastructure outputs for convenience
output "admin_user_created" {
  description = "Whether admin user was created (from infrastructure)"
  value       = data.terraform_remote_state.infrastructure.outputs.admin_user_created
  sensitive   = false
}

output "bastion_deployed" {
  description = "Whether bastion host was deployed (from infrastructure)"
  value       = data.terraform_remote_state.infrastructure.outputs.bastion_deployed
  sensitive   = false
}

output "bastion_instance_id" {
  description = "Bastion instance ID (from infrastructure)"
  value       = data.terraform_remote_state.infrastructure.outputs.bastion_instance_id
  sensitive   = false
}

output "bastion_ssm_command" {
  description = "Command to connect to bastion via SSM Session Manager (from infrastructure)"
  value       = data.terraform_remote_state.infrastructure.outputs.bastion_ssm_command
  sensitive   = false
}

output "bastion_sshuttle_command" {
  description = "Command to create VPN-like access via sshuttle (from infrastructure)"
  value       = data.terraform_remote_state.infrastructure.outputs.bastion_sshuttle_command
  sensitive   = false
}

# Re-export infrastructure outputs for convenience
output "cluster_id" {
  description = "ROSA HCP Cluster ID"
  value       = data.terraform_remote_state.infrastructure.outputs.cluster_id
  sensitive   = false
}

output "api_url" {
  description = "Cluster API URL"
  value       = data.terraform_remote_state.infrastructure.outputs.api_url
  sensitive   = false
}

output "console_url" {
  description = "Cluster Console URL"
  value       = data.terraform_remote_state.infrastructure.outputs.console_url
  sensitive   = false
}
