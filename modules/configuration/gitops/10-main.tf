# Deploy OpenShift GitOps operator using Kubernetes provider
# This module uses the Kubernetes provider to deploy the GitOps operator resources
# in a Terraform-native way with proper state management and dependency handling
#
# IMPORTANT: The Kubernetes provider must be configured at the root level (not in this module)
# Example provider configuration:
#   provider "kubernetes" {
#     host     = var.api_url
#     username = var.admin_username
#     password = var.admin_password
#     insecure = var.skip_tls_verify
#   }

locals {
  # Common tags for documentation
  common_tags = merge(var.tags, {
    ManagedBy   = "Terraform"
    ClusterName = var.cluster_name
    Module      = "gitops"
  })
}

# Create namespace for GitOps operator
resource "kubernetes_namespace" "gitops" {
  count = var.deploy_gitops ? 1 : 0

  metadata {
    name = var.gitops_namespace
    labels = merge(local.common_tags, {
      "openshift.io/cluster-monitoring" = "true"
    })
  }

  lifecycle {
    ignore_changes = [
      # OpenShift may add annotations/labels automatically
      metadata[0].annotations,
      metadata[0].labels,
    ]
  }
}

# Create OperatorGroup for GitOps operator
resource "kubernetes_manifest" "operator_group" {
  count = var.deploy_gitops ? 1 : 0

  manifest = {
    apiVersion = "operators.coreos.com/v1"
    kind       = "OperatorGroup"
    metadata = {
      name      = "openshift-gitops-operator-rg"
      namespace = kubernetes_namespace.gitops[0].metadata[0].name
    }
    spec = {
      upgradeStrategy = "Default"
    }
  }

  depends_on = [kubernetes_namespace.gitops]
}

# Create Subscription for GitOps operator
resource "kubernetes_manifest" "subscription" {
  count = var.deploy_gitops ? 1 : 0

  manifest = {
    apiVersion = "operators.coreos.com/v1alpha1"
    kind       = "Subscription"
    metadata = {
      name      = "openshift-gitops-operator"
      namespace = kubernetes_namespace.gitops[0].metadata[0].name
    }
    spec = {
      channel             = var.operator_channel
      installPlanApproval = var.install_plan_approval
      name                = "openshift-gitops-operator"
      source              = var.operator_source
      sourceNamespace     = "openshift-marketplace"
    }
  }

  depends_on = [kubernetes_manifest.operator_group]

  # Wait for subscription to be ready
  wait {
    fields = {
      "status.installedCSV" = "*"
    }
  }
}

# Read subscription status to get installed CSV name
# Note: kubernetes_manifest doesn't expose status directly, so we use kubernetes_resource data source
data "kubernetes_resource" "subscription" {
  count = var.deploy_gitops ? 1 : 0

  api_version = "operators.coreos.com/v1alpha1"
  kind        = "Subscription"

  metadata {
    name      = "openshift-gitops-operator"
    namespace = kubernetes_namespace.gitops[0].metadata[0].name
  }

  depends_on = [kubernetes_manifest.subscription]
}

# Extract CSV name from subscription status
locals {
  installed_csv_name = var.deploy_gitops ? try(
    data.kubernetes_resource.subscription[0].object.status.installedCSV,
    null
  ) : null
}

# Wait for ClusterServiceVersion (CSV) to be in Succeeded phase
# CSV name comes from subscription status.installedCSV
resource "kubernetes_manifest" "csv_wait" {
  count = var.deploy_gitops && local.installed_csv_name != null ? 1 : 0

  manifest = {
    apiVersion = "operators.coreos.com/v1alpha1"
    kind       = "ClusterServiceVersion"
    metadata = {
      name      = local.installed_csv_name
      namespace = kubernetes_namespace.gitops[0].metadata[0].name
    }
  }

  wait {
    fields = {
      "status.phase" = "Succeeded"
    }
  }

  depends_on = [data.kubernetes_resource.subscription]
}

# Note: Operator deployment verification is handled by the CSV wait condition
# Once CSV reaches Succeeded phase, the operator deployment is guaranteed to be available
