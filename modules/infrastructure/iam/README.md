# IAM Module

This module creates the IAM roles and OIDC configuration required for ROSA HCP clusters.

## Features

- Managed OIDC configuration
- AWS IAM OIDC provider
- Account roles (Installer, Support, Worker) using terraform-redhat/rosa-hcp/rhcs module
- Operator roles for ROSA HCP:
  - Ingress Operator
  - Control Plane Operator
  - CSI Driver Operator
  - Image Registry Operator
  - Network Operator
  - Node Pool Operator
- Role prefixing for uniqueness across clusters

## Usage

```hcl
module "iam" {
  source = "../../modules/iam"

  cluster_name         = "my-rosa-cluster"
  account_role_prefix  = "my-rosa-cluster-"  # Optional, defaults to cluster_name
  operator_role_prefix = "my-rosa-cluster-"  # Optional, defaults to cluster_name

  tags = {
    Environment = "production"
    Project     = "rosa-hcp"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | ~> 5.0 |
| rhcs | ~> 1.7 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | Name of the ROSA HCP cluster | `string` | n/a | yes |
| account_role_prefix | Prefix for account roles to ensure uniqueness. Defaults to cluster_name | `string` | `null` | no |
| operator_role_prefix | Prefix for operator roles to ensure uniqueness. Defaults to cluster_name | `string` | `null` | no |
| zero_egress | Enable zero egress mode. When true, attaches AmazonEC2ContainerRegistryReadOnly policy to worker role (required for egress-zero clusters) | `bool` | `false` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| oidc_config_id | ID of the OIDC configuration |
| oidc_endpoint_url | OIDC endpoint URL |
| oidc_provider_arn | ARN of the OIDC provider |
| installer_role_arn | ARN of the Installer account role |
| support_role_arn | ARN of the Support account role |
| worker_role_arn | ARN of the Worker account role |
| operator_role_arns | Map of operator role names to ARNs |

## Account Roles

The module uses the `terraform-redhat/rosa-hcp/rhcs` module to create account roles:

- **Installer Role**: Used during cluster installation
- **Support Role**: Used by Red Hat support
- **Worker Role**: Used by worker nodes

These roles are account-wide but prefixed to ensure uniqueness across clusters.

## Operator Roles

The module creates the following operator roles required for ROSA HCP:

- **ingress**: Ingress Operator for load balancers
- **control-plane**: Control Plane Operator
- **csi-driver**: CSI Driver Operator for storage
- **image-registry**: Image Registry Operator
- **network**: Network Operator
- **node-pool**: Node Pool Operator

All operator roles are linked to the OIDC provider and use least-privilege principles.

## Role Prefixing

By default, roles are prefixed with the cluster name to ensure uniqueness. You can override this with the `account_role_prefix` and `operator_role_prefix` variables.

Example:
- Cluster name: `prod-hcp-01`
- Account role prefix: `prod-hcp-01-` (default)
- Operator role prefix: `prod-hcp-01-` (default)

This ensures multiple clusters can coexist in the same AWS account without role name conflicts.

## Dependencies

- Requires AWS credentials with permissions to create IAM roles and OIDC providers
- Requires RHCS provider token or AWS SSO access
- Account roles module requires specific permissions (see terraform-redhat/rosa-hcp documentation)
