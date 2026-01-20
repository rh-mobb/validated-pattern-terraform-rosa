# GitOps Bootstrap using Helm Charts
# This resource uses a standalone bootstrap script to install GitOps operator via Helm charts
# Reference: ./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/9.bootstrap.tf
#
# The bootstrap script (scripts/cluster/bootstrap-gitops.sh) is idempotent and can be run
# independently or via Terraform. It uses environment variables for configuration.
#
# NOTE: The shell provider must be configured at the root level (not in this module)
# to avoid making this a "legacy module" that cannot use depends_on

# Get script path relative to repository root
locals {
  # Get the path to the script relative to the root module directory
  # path.root is the root module directory (terraform/)
  # From there, scripts are at ../scripts/cluster/ relative to repo root
  # But since we're in a module, we need to calculate the relative path
  # From modules/infrastructure/cluster/ to scripts/cluster/:
  # - Up to repo root: ../../../
  # - Then to script: scripts/cluster/bootstrap-gitops.sh
  # path.root is the root module directory (terraform/)
  # From there, scripts are at ../scripts/cluster/bootstrap-gitops.sh (relative to repo root)
  script_path = "${path.root}/../scripts/cluster/bootstrap-gitops.sh"

  # Get AWS account ID
  aws_account_id = data.aws_caller_identity.current.account_id
}


# Cluster credentials secret for bootstrap script
# This secret stores cluster credentials in the format expected by the bootstrap script:
# {
#   "user": "cluster-admin",
#   "password": "...",
#   "url": "https://api.cluster.example.com:6443"
# }
# This secret persists through sleep operations to preserve credentials for cluster restart.
resource "aws_secretsmanager_secret" "cluster_credentials" {
  # Always create secret if GitOps bootstrap is enabled (persists through sleep)
  # Secret persists even when persists_through_sleep=false (sleep operation)
  count = var.enable_gitops_bootstrap ? 1 : 0

  name                    = "${var.cluster_name}-credentials"
  description              = "Cluster credentials for ROSA HCP cluster ${var.cluster_name} (used by GitOps bootstrap, persists through sleep)"
  recovery_window_in_days  = 0

  tags = merge(local.common_tags, {
    Name    = "${var.cluster_name}-credentials"
    Purpose = "ClusterCredentials"
    persists_through_sleep = "true"
  })

  depends_on = [
    rhcs_cluster_rosa_hcp.main
  ]
}

# Store cluster credentials in the secret
# Password should be provided via admin_password_for_bootstrap variable from infrastructure level
# If not provided, secret will be created with placeholder that must be updated manually
# The secret can be updated later via AWS CLI or console if password is not available during cluster creation
# Only create/update secret version when cluster exists (not during sleep)
resource "aws_secretsmanager_secret_version" "cluster_credentials" {
  count = var.enable_gitops_bootstrap && local.persists_through_sleep ? 1 : 0

  secret_id = aws_secretsmanager_secret.cluster_credentials[0].id
  secret_string = jsonencode({
    user     = var.admin_username
    password = var.admin_password_for_bootstrap != null ? var.admin_password_for_bootstrap : "CHANGE_ME_PASSWORD_NOT_SET"
    url      = length(rhcs_cluster_rosa_hcp.main) > 0 ? one(rhcs_cluster_rosa_hcp.main[*].api_url) : ""
  })

  # Allow secret to be updated manually if password changes
  # The bootstrap script will read the current value from Secrets Manager
  lifecycle {
    ignore_changes = [
      secret_string
    ]
  }

  depends_on = [
    rhcs_cluster_rosa_hcp.main,
    aws_secretsmanager_secret.cluster_credentials
    # Note: identity_admin module should be created before this runs, but it's in the root module
    # The root module should ensure identity_admin is created before calling this module
  ]
}

# Bootstrap GitOps operator using Helm charts
# NOTE: GitOps bootstrap is now run manually using terraform output values
# The shell_script resource is commented out - use the gitops_bootstrap_command output to run it manually
#
# resource "shell_script" "gitops_bootstrap" {
#   count = var.enable_gitops_bootstrap && local.persists_through_sleep ? 1 : 0
#
#   lifecycle_commands {
#     create = "${local.script_path}"
#     delete = "ENABLE=false ${local.script_path}"  # Pass ENABLE=false for cleanup
#     read   = "${local.script_path}"
#     update = "${local.script_path}"
#   }
#
#   environment = {
#     # ... (see gitops_bootstrap_command output for all environment variables)
#   }
#
#   depends_on = [
#     rhcs_cluster_rosa_hcp.main,
#     aws_secretsmanager_secret_version.cluster_credentials,
#     rhcs_identity_provider.admin,
#   ]
# }
