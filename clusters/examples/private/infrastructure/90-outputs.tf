output "cluster_id" {
  description = "ROSA HCP Cluster ID"
  value       = module.cluster.cluster_id
  sensitive   = false
}

output "cluster_name" {
  description = "Name of the ROSA HCP cluster"
  value       = var.cluster_name
  sensitive   = false
}

output "api_url" {
  description = "Cluster API URL"
  value       = module.cluster.api_url
  sensitive   = false
}

output "console_url" {
  description = "Cluster Console URL"
  value       = module.cluster.console_url
  sensitive   = false
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
  sensitive   = false
}

output "vpc_cidr_block" {
  description = "VPC CIDR block"
  value       = module.network.vpc_cidr_block
  sensitive   = false
}

output "region" {
  description = "AWS region"
  value       = var.region
  sensitive   = false
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.network.private_subnet_ids
  sensitive   = false
}

output "admin_user_created" {
  description = "Whether admin user was created"
  value       = length(module.identity_admin) > 0
  sensitive   = false
}

output "admin_password" {
  description = "Admin password (sensitive - only output if admin user was created)"
  value       = var.admin_password
  sensitive   = true
}

output "bastion_deployed" {
  description = "Whether bastion host was deployed"
  value       = var.enable_bastion && length(module.bastion) > 0
  sensitive   = false
}

output "bastion_instance_id" {
  description = "Bastion instance ID (for SSM Session Manager access)"
  value       = var.enable_bastion && length(module.bastion) > 0 ? module.bastion[0].bastion_instance_id : null
  sensitive   = false
}

output "bastion_ssm_command" {
  description = "Command to connect to bastion via SSM Session Manager"
  value       = var.enable_bastion && length(module.bastion) > 0 ? module.bastion[0].ssm_session_command : null
  sensitive   = false
}

output "bastion_sshuttle_command" {
  description = "Command to create VPN-like access via sshuttle"
  value       = var.enable_bastion && length(module.bastion) > 0 ? module.bastion[0].sshuttle_command : null
  sensitive   = false
}
