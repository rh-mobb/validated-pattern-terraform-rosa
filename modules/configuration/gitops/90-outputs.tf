output "gitops_deployed" {
  description = "Whether GitOps operator was deployed (null if enable_destroy is true)"
  value       = var.deploy_gitops && var.enable_destroy == false ? true : null
  sensitive   = false
}

output "gitops_namespace" {
  description = "Namespace where GitOps operator is installed (null if enable_destroy is true)"
  value       = var.deploy_gitops && var.enable_destroy == false && length(openshift_operator.gitops) > 0 ? openshift_operator.gitops[0].namespace : null
  sensitive   = false
}

output "operator_channel" {
  description = "Channel used for GitOps operator subscription (null if enable_destroy is true)"
  value       = var.deploy_gitops && var.enable_destroy == false && length(openshift_operator.gitops) > 0 ? openshift_operator.gitops[0].channel : null
  sensitive   = false
}

output "installed_csv" {
  description = "Name of the installed ClusterServiceVersion (CSV) (null if enable_destroy is true)"
  value       = var.deploy_gitops && var.enable_destroy == false && length(openshift_operator.gitops) > 0 ? openshift_operator.gitops[0].installed_csv : null
  sensitive   = false
}

output "csv_phase" {
  description = "Current phase of the CSV (e.g., 'Succeeded', 'Installing', 'Failed') (null if enable_destroy is true)"
  value       = var.deploy_gitops && var.enable_destroy == false && length(openshift_operator.gitops) > 0 ? openshift_operator.gitops[0].csv_phase : null
  sensitive   = false
}

output "operator_deployment_ready" {
  description = "Whether the GitOps operator deployment is ready (true when CSV is Succeeded) (false if enable_destroy is true)"
  value       = var.deploy_gitops && var.enable_destroy == false && length(openshift_operator.gitops) > 0 ? openshift_operator.gitops[0].csv_phase == "Succeeded" : false
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
