# Identity Providers and Group Memberships
# Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/05-identity.tf
# HTPasswd Identity Provider for Admin User
resource "rhcs_identity_provider" "admin" {
  count = var.persists_through_sleep ? 1 : 0

  cluster = var.cluster_id
  name    = var.admin_username
  htpasswd = {
    users = [{
      username = var.admin_username
      password = var.admin_password
    }]
  }
}

# Add Admin User to Cluster Admins Group
# Note: Using group membership resource is deprecated, but still functional
# Consider migrating to group membership via OCM API or console when available
resource "rhcs_group_membership" "admin" {
  count = var.persists_through_sleep ? 1 : 0

  user    = one(rhcs_identity_provider.admin[*].htpasswd.users[0].username)
  group   = var.admin_group
  cluster = var.cluster_id

  depends_on = [rhcs_identity_provider.admin]
}
