# Deploy OpenShift GitOps operator using OpenShift Operator Provider
# This module uses the openshift_operator resource to deploy the GitOps operator
# with proper state management, automatic InstallPlan approval, and CSV waiting
#
# IMPORTANT: The OpenShift provider must be configured at the root level (not in this module)
# The provider is automatically inherited from the root module configuration.
# Example root-level provider configuration:
#   provider "openshift" {
#     host     = var.api_url
#     token    = var.k8s_token
#     insecure = var.skip_tls_verify
#   }

locals {
  # Common labels for Kubernetes resources
  common_labels = merge(var.labels, {
    "app.kubernetes.io/managed-by" = "Terraform"
    "app.kubernetes.io/name"       = "openshift-gitops-operator"
    "app.kubernetes.io/part-of"   = var.cluster_name
  })

  # Namespace labels
  namespace_labels = merge(local.common_labels, {
    "openshift.io/cluster-monitoring" = "true"
  })
}

# Deploy GitOps operator using openshift_operator resource
# This single resource handles:
# - Namespace creation (if create_namespace = true)
# - OperatorGroup creation
# - Subscription creation
# - InstallPlan approval (automatic when version is specified)
# - CSV waiting until Succeeded phase
resource "openshift_operator" "gitops" {
  count = var.deploy_gitops && var.enable_destroy == false ? 1 : 0

  name      = "openshift-gitops-operator"
  namespace = var.gitops_namespace
  channel   = var.operator_channel
  source    = var.operator_source

  # Version pinning (optional)
  # If specified, install_plan_approval is automatically set to "Manual"
  version = var.operator_version

  # Install plan approval (only used if version is not specified)
  # If version is specified, this is automatically set to "Manual"
  install_plan_approval = var.install_plan_approval

  # Create namespace if it doesn't exist
  create_namespace = true

  # Labels for operator resources
  labels = local.common_labels

  # Labels for the namespace
  namespace_labels = local.namespace_labels

  # OperatorGroup target namespaces (empty = cluster-wide)
  operator_group_target_namespaces = []

  # Wait for CSV to reach Succeeded phase
  wait_for_csv = true

  # Timeout for CSV waiting (default is 10m, provider default is 20m for create)
  wait_timeout = "20m"
}
