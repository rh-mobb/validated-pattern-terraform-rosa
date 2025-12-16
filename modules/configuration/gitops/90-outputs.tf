output "gitops_deployed" {
  description = "Whether GitOps operator was deployed"
  value       = var.deploy_gitops
  sensitive   = false
}

output "gitops_namespace" {
  description = "Namespace where GitOps operator is installed"
  value       = var.deploy_gitops ? kubernetes_namespace.gitops[0].metadata[0].name : null
  sensitive   = false
}

output "operator_channel" {
  description = "Channel used for GitOps operator subscription"
  value       = var.deploy_gitops ? var.operator_channel : null
  sensitive   = false
}

output "installed_csv" {
  description = "Name of the installed ClusterServiceVersion (CSV)"
  value       = var.deploy_gitops ? try(local.installed_csv_name, null) : null
  sensitive   = false
}

output "operator_deployment_ready" {
  description = "Whether the GitOps operator deployment is ready (true when CSV is Succeeded)"
  value       = var.deploy_gitops ? (local.installed_csv_name != null) : false
  sensitive   = false
}

output "cluster_id" {
  description = "ID of the cluster where GitOps is deployed"
  value       = var.cluster_id
  sensitive   = false
}

output "cluster_name" {
  description = "Name of the cluster where GitOps is deployed"
  value       = var.cluster_name
  sensitive   = false
}

output "api_url" {
  description = "API URL of the cluster"
  value       = var.api_url
  sensitive   = false
}
