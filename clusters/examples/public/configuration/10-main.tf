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
    "app.kubernetes.io/part-of"    = data.terraform_remote_state.infrastructure.outputs.cluster_name
  })

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