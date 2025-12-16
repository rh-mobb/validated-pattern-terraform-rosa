# Identity Admin Module

This module creates an HTPasswd identity provider and admin user for ROSA HCP clusters. This is typically used as a temporary bootstrap identity provider that can be removed once an external identity provider (e.g., LDAP, OIDC) is configured.

## Features

- **HTPasswd Identity Provider**: Creates a simple username/password identity provider
- **Admin User**: Creates an admin user with cluster-admin privileges
- **Temporary by Design**: Intended to be removed after external IDP is configured
- **Lifecycle Management**: Can be easily added or removed from cluster configuration

## Usage

### Basic Usage

```hcl
module "identity_admin" {
  source = "../../modules/identity-admin"

  cluster_id    = module.cluster.cluster_id
  admin_password = var.admin_password  # Must be 14+ chars, uppercase, symbol/number
}
```

### With Custom Username and Group

```hcl
module "identity_admin" {
  source = "../../modules/identity-admin"

  cluster_id     = module.cluster.cluster_id
  admin_password  = var.admin_password
  admin_username  = "cluster-admin"
  admin_group     = "cluster-admins"
}
```

### Removing the Admin User

To remove the admin user and identity provider:

1. **Comment out or remove the module** from your cluster configuration:
```hcl
# module "identity_admin" {
#   source = "../../modules/identity-admin"
#   ...
# }
```

2. **Run Terraform destroy**:
```bash
terraform destroy -target=module.identity_admin
```

3. **Or remove from state** if already deleted manually:
```bash
terraform state rm module.identity_admin.rhcs_identity_provider.admin
terraform state rm module.identity_admin.rhcs_group_membership.admin
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| rhcs | ~> 1.7 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_id | ID of the ROSA HCP cluster | `string` | n/a | yes |
| admin_password | Password for admin user (14+ chars, uppercase, symbol/number) | `string` | n/a | yes |
| admin_username | Username for admin user | `string` | `"admin"` | no |
| admin_group | OpenShift group for admin user | `string` | `"cluster-admins"` | no |

## Outputs

| Name | Description |
|------|-------------|
| identity_provider_id | ID of the HTPasswd identity provider |
| identity_provider_name | Name of the identity provider |
| admin_username | Username of the admin user |
| admin_group | Group the admin user belongs to |

## Typical Workflow

1. **Initial Cluster Setup**: Deploy cluster with admin user module
   ```hcl
   module "identity_admin" {
     source = "../../modules/identity-admin"
     cluster_id    = module.cluster.cluster_id
     admin_password = var.admin_password
   }
   ```

2. **Configure External IDP**: Use admin user to configure LDAP, OIDC, etc. via OpenShift console or OCM

3. **Remove Admin User**: Once external IDP is working, remove the module:
   ```hcl
   # module "identity_admin" {
   #   source = "../../modules/identity-admin"
   #   ...
   # }
   ```

4. **Apply Changes**: Run `terraform apply` to remove the temporary admin user

## Security Considerations

- **Temporary Use Only**: This module is intended for temporary bootstrap access
- **Strong Passwords**: Ensure `admin_password` meets requirements (14+ chars, uppercase, symbol/number)
- **Remove After Setup**: Remove this module once external identity provider is configured
- **Sensitive Data**: Never commit passwords to version control; use environment variables or secrets management

## Deprecation Notice

The `rhcs_group_membership` resource is deprecated by the provider. This module still uses it for compatibility, but consider migrating to group membership via OCM API or console when available.

## Integration with Cluster Module

This module is designed to work alongside the `cluster` module:

```hcl
module "cluster" {
  source = "../../modules/cluster"
  # ... cluster configuration
  # Note: Do NOT pass admin_password to cluster module
}

module "identity_admin" {
  source = "../../modules/identity-admin"
  cluster_id    = module.cluster.cluster_id
  admin_password = var.admin_password
}
```

## References

- [ROSA HCP Identity Provider Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/)
- [Terraform RHCS Provider - Identity Provider](https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/resources/identity_provider)
- [Reference Implementation](https://github.com/rh-mobb/terraform-rosa/blob/main/05-identity.tf)
