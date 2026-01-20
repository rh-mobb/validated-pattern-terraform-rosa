# Identity Providers and Group Memberships
# Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/05-identity.tf
# HTPasswd Identity Provider for Admin User
# This creates an admin user for initial cluster access
# This can be removed once an external identity provider is configured

# HTPasswd Identity Provider for Admin User
resource "rhcs_identity_provider" "admin" {
  count = var.enable_identity_provider && local.persists_through_sleep ? 1 : 0

  cluster = length(rhcs_cluster_rosa_hcp.main) > 0 ? one(rhcs_cluster_rosa_hcp.main[*].id) : null
  name    = var.admin_username
  htpasswd = {
    users = [{
      username = var.admin_username
      password = var.admin_password_for_bootstrap != null ? var.admin_password_for_bootstrap : "CHANGE_ME_PASSWORD_NOT_SET"
    }]
  }

  depends_on = [
    rhcs_cluster_rosa_hcp.main
  ]
}

# Add Admin User to Cluster Admins Group
# Note: Using group membership resource is deprecated, but still functional
# Consider migrating to group membership via OCM API or console when available
resource "rhcs_group_membership" "admin" {
  count = var.enable_identity_provider && local.persists_through_sleep ? 1 : 0

  user    = var.admin_username
  group   = var.admin_group
  cluster = length(rhcs_cluster_rosa_hcp.main) > 0 ? one(rhcs_cluster_rosa_hcp.main[*].id) : null

  depends_on = [rhcs_identity_provider.admin]
}
