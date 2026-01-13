# GitOps Operator
# Note: Admin user and bastion are created in infrastructure, not configuration
# Configuration reads admin credentials from infrastructure state
# Using the openshift provider for simplified operator management
resource "openshift_operator" "gitops" {
  provider = openshift

  count = var.gitops_enabled && var.enable_destroy == false ? 1 : 0

  name      = "openshift-gitops-operator"
  namespace = "openshift-gitops-operator"
  channel   = "latest"
  source    = "redhat-operators"
  version   = var.gitops_operator_version != null ? var.gitops_operator_version : null

  # When version is specified, install_plan_approval must be "Manual"
  # Otherwise, use "Automatic" (default)
  install_plan_approval = var.gitops_operator_version != null ? "Manual" : "Automatic"

  labels = merge(var.labels, {
    "app.kubernetes.io/managed-by" = "Terraform"
    "app.kubernetes.io/part-of"    = var.cluster_name
  })

  # Create namespace if it doesn't exist
  create_namespace = true

  namespace_labels = {
    "openshift.io/cluster-monitoring" = "true"
  }

  wait_for_csv = true
  wait_timeout = "10m"

  lifecycle {
    # OpenShift automatically adds labels like "operators.coreos.com/openshift-gitops-operator.openshift-gitops-operator"
    # We should not remove those when applying our labels
    ignore_changes = [labels]
  }
}

# Data source to fetch the GitOps server route
# The route is created by the GitOps operator in the openshift-gitops namespace
# Note: This is the ArgoCD instance route, not the operator namespace (openshift-gitops-operator)
# The route is created automatically when the GitOps operator installs ArgoCD
# Using kubernetes_resource data source to read OpenShift Route resource
# Reference: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/data-sources/resource
data "kubernetes_resource" "gitops_route" {
  count = var.gitops_enabled && var.enable_destroy == false && length(openshift_operator.gitops) > 0 ? 1 : 0

  api_version = "route.openshift.io/v1"
  kind        = "Route"

  metadata {
    name      = "openshift-gitops-server"
    namespace = "openshift-gitops"
  }

  # Wait for the operator to be ready and CSV to be Succeeded before trying to fetch the route
  # The route is created by the ArgoCD instance, which is deployed after the operator CSV succeeds
  depends_on = [openshift_operator.gitops]
}
