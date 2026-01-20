# Data source for AWS account ID and partition (needed for role ARNs)
# These must be declared before the locals block that uses them
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  # Determine if cluster persists/is active (use override if provided, else global)
  persists_through_sleep = var.persists_through_sleep_iam != null ? var.persists_through_sleep_iam : var.persists_through_sleep

  # Use cluster_name as prefix if not provided
  account_role_prefix_final  = var.account_role_prefix != null ? var.account_role_prefix : var.cluster_name
  operator_role_prefix_final = var.operator_role_prefix != null ? var.operator_role_prefix : var.cluster_name

  # Common tags
  common_tags = merge(var.tags, {
    ManagedBy   = "Terraform"
    ClusterName = var.cluster_name
  })

  # Operator role names for ROSA HCP
  operator_roles = {
    ingress        = "ingress"
    control_plane  = "control-plane"
    csi_driver     = "csi-driver"
    image_registry = "image-registry"
    network        = "network"
    node_pool      = "node-pool"
  }

  # Construct role ARNs based on the naming pattern used by the modules
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/03-roles.tf
  role_prefix = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.account_role_prefix_final}"

  # HCP account roles use different naming: {prefix}-HCP-ROSA-{RoleName}-Role
  installer_role_arn = "${local.role_prefix}-HCP-ROSA-Installer-Role"
  support_role_arn   = "${local.role_prefix}-HCP-ROSA-Support-Role"
  worker_role_arn    = "${local.role_prefix}-HCP-ROSA-Worker-Role"

}

# Account Roles using terraform-redhat/rosa-hcp/rhcs module
# Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/03-roles.tf
# CRITICAL: Destroy order must be enforced via depends_on in the calling configuration
# The calling configuration should create a null_resource that depends on the cluster
# and then make this module depend on that null_resource to ensure cluster is destroyed first
  # Gate with persists_through_sleep flag - allows preserving IAM roles for reuse across clusters
module "account_roles" {
  count = local.persists_through_sleep ? 1 : 0

  source  = "terraform-redhat/rosa-hcp/rhcs//modules/account-iam-resources"
  version = "~> 1.7"

  account_role_prefix = local.account_role_prefix_final
  tags                = local.common_tags
}

# OIDC Configuration and Provider using terraform-redhat/rosa-hcp/rhcs module
# Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/03-roles.tf
# CRITICAL: Destroy order is handled by Terraform's implicit dependency graph
module "oidc_config_and_provider" {
  source  = "terraform-redhat/rosa-hcp/rhcs//modules/oidc-config-and-provider"
  version = "~> 1.7"

  managed = true
  tags    = local.common_tags
}

# Operator Roles using terraform-redhat/rosa-hcp/rhcs module
# Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/03-roles.tf
# CRITICAL: Destroy order is handled by Terraform's implicit dependency graph
# Gate with persists_through_sleep flag - allows preserving IAM roles for reuse across clusters
module "operator_roles" {
  count = local.persists_through_sleep ? 1 : 0

  source  = "terraform-redhat/rosa-hcp/rhcs//modules/operator-roles"
  version = "~> 1.7"

  oidc_endpoint_url    = module.oidc_config_and_provider.oidc_endpoint_url
  operator_role_prefix = local.operator_role_prefix_final
  tags                 = local.common_tags
}

# Additional policy for worker role when zero_egress is enabled
# Reference: ECR read-only access is required for egress-zero clusters to pull container images via VPC endpoints
# The worker role name follows the pattern: {account_role_prefix}-HCP-ROSA-Worker-Role
# Gate with persists_through_sleep flag and zero_egress flag
resource "aws_iam_role_policy_attachment" "worker_ecr_readonly" {
  count = var.zero_egress && local.persists_through_sleep ? 1 : 0

  role       = "${local.account_role_prefix_final}-HCP-ROSA-Worker-Role"
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"

  # Ensure the account_roles module has created the worker role before attaching the policy
  depends_on = [module.account_roles]
}
