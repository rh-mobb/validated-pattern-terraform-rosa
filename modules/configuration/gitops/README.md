# GitOps Module

This module creates the namespace for the OpenShift GitOps operator (ArgoCD) on a ROSA HCP cluster using the Kubernetes provider.

## Current Status

**Currently, this module only creates the GitOps namespace.** The operator installation resources (OperatorGroup, Subscription, CSV) are not yet implemented due to a known limitation with `kubernetes_manifest` resources that require API schema validation during planning, which currently fails with authentication errors even though the provider is correctly configured.

The namespace resource (`kubernetes_namespace_v1`) works correctly, confirming that Kubernetes provider authentication is functioning properly. The issue is specific to `kubernetes_manifest` resources.

## Features

- Creates namespace for GitOps operator with proper labels
- Supports custom namespace configuration
- Proper Terraform state management

## Planned Features (Not Yet Implemented)

- Deploy OpenShift GitOps operator via OperatorHub using Kubernetes provider
- Configurable operator channel and source
- Automatic or manual install plan approval
- Wait for operator installation to complete (CSV in Succeeded phase)
- Verify operator deployment is available

## Usage

### Prerequisites

**Configure Kubernetes Provider**: The Kubernetes provider must be configured at the root level (in your cluster configuration, not in this module):

```hcl
provider "kubernetes" {
  host     = module.cluster.api_url
  username = "admin"
  password = var.admin_password  # Sensitive variable
  insecure = false  # Set to true only for development/testing
}
```

### Basic Usage

```hcl
# Configure Kubernetes provider (required)
provider "kubernetes" {
  host     = module.cluster.api_url
  username = "admin"
  password = var.admin_password
  insecure = false
}

module "gitops" {
  source = "../../modules/gitops"

  # Required: Cluster information
  cluster_id   = module.cluster.cluster_id
  cluster_name = module.cluster.cluster_name
  api_url      = module.cluster.api_url

  # Required: Authentication (used for provider configuration)
  admin_username = "admin"
  admin_password = var.admin_password  # Sensitive variable

  # Optional: GitOps configuration
  deploy_gitops = true
}
```

### Advanced Usage

```hcl
# Configure Kubernetes provider
provider "kubernetes" {
  host     = module.cluster.api_url
  username = "admin"
  password = var.admin_password
  insecure = var.skip_tls_verify
}

module "gitops" {
  source = "../../modules/gitops"

  # Cluster information
  cluster_id   = module.cluster.cluster_id
  cluster_name = module.cluster.cluster_name
  api_url      = module.cluster.api_url

  # Authentication
  admin_username = "admin"
  admin_password = var.admin_password

  # GitOps configuration
  gitops_namespace      = "openshift-gitops-operator"
  operator_channel      = "stable"  # or "latest"
  operator_source       = "redhat-operators"
  install_plan_approval = "Automatic"  # or "Manual"
  skip_tls_verify       = false  # Not recommended for production

  labels = {
    "environment" = "production"
    "managed-by"  = "terraform"
  }
}
```

### Conditional Deployment

```hcl
module "gitops" {
  source = "../../modules/gitops"

  cluster_id   = module.cluster.cluster_id
  cluster_name = module.cluster.cluster_name
  api_url      = module.cluster.api_url

  admin_username = "admin"
  admin_password = var.admin_password

  # Deploy GitOps only in production
  deploy_gitops = var.environment == "production"
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| kubernetes | ~> 2.30 |

## Prerequisites

1. **Kubernetes Provider**: Must be configured at the root level with cluster credentials
2. **Cluster Access**: Must be able to authenticate to the cluster API
3. **Cluster Ready**: Cluster must be in a ready state before deploying GitOps operator

## Inputs

### Required

| Name | Description | Type |
|------|-------------|------|
| cluster_id | ID of the ROSA HCP cluster | `string` |
| cluster_name | Name of the ROSA HCP cluster | `string` |
| api_url | API URL of the cluster (for Kubernetes provider) | `string` |
| admin_username | Admin username for cluster authentication | `string` |
| admin_password | Admin password for cluster authentication | `string` (sensitive) |

### Optional

| Name | Description | Type | Default |
|------|-------------|------|---------|
| deploy_gitops | Whether to deploy the OpenShift GitOps operator | `bool` | `true` |
| gitops_namespace | Namespace for the GitOps operator | `string` | `"openshift-gitops-operator"` |
| operator_channel | Channel for the GitOps operator subscription | `string` | `"latest"` |
| operator_source | Operator source catalog | `string` | `"redhat-operators"` |
| install_plan_approval | Install plan approval strategy (Automatic or Manual) | `string` | `"Automatic"` |
| skip_tls_verify | Skip TLS verification for Kubernetes API connection | `bool` | `false` |
| labels | Labels to apply to Kubernetes resources | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| gitops_deployed | Whether GitOps operator was deployed |
| gitops_namespace | Namespace where GitOps operator is installed |
| operator_channel | Channel used for GitOps operator subscription |
| installed_csv | Name of the installed ClusterServiceVersion (CSV) |
| operator_deployment_ready | Whether the GitOps operator deployment is ready |
| cluster_id | ID of the cluster where GitOps is deployed |
| cluster_name | Name of the cluster where GitOps is deployed |
| api_url | API URL of the cluster |

## How It Works

1. **Namespace Creation**: Creates the GitOps operator namespace using `kubernetes_namespace`
2. **OperatorGroup**: Creates an OperatorGroup to define operator installation scope
3. **Subscription**: Creates a Subscription to install the GitOps operator from OperatorHub
4. **Wait for CSV**: Waits for the ClusterServiceVersion (CSV) to be installed and reach "Succeeded" phase
5. **Verification**: Verifies that the operator deployment is available and running

## Dependencies

This module depends on:
- Cluster module outputs (`cluster_id`, `cluster_name`, `api_url`)
- Kubernetes provider configured at root level with cluster credentials
- Admin credentials for cluster authentication

## Common Issues

### Provider Not Configured

**Error**: `Provider "kubernetes" not configured`

**Solution**: Configure the Kubernetes provider at the root level (in your cluster configuration):
```hcl
provider "kubernetes" {
  host     = module.cluster.api_url
  username = "admin"
  password = var.admin_password
  insecure = false
}
```

### Authentication Failed

**Error**: `Unable to connect to the server: unauthorized`

**Solution**:
- Verify admin credentials are correct
- Ensure cluster API URL is accessible
- For private clusters, ensure you have network access (bastion, VPN, etc.)
- Check that the cluster is in a ready state

### TLS Verification Errors

**Error**: TLS verification failures during provider initialization

**Solution**:
- For development/testing: Set `insecure = true` in provider configuration (not recommended for production)
- For production: Ensure proper TLS certificates are configured

### CSV Not Found

**Error**: `ClusterServiceVersion not found`

**Solution**:
- Wait for the subscription to install the CSV (this happens automatically)
- Check subscription status: `oc get subscription -n openshift-gitops-operator`
- Verify operator catalog is accessible

## Integration with Cluster Module

This module is designed to work with the cluster module:

```hcl
# Configure providers
provider "kubernetes" {
  host     = module.cluster.api_url
  username = "admin"
  password = var.admin_password
  insecure = false
}

module "cluster" {
  source = "../../modules/cluster"
  # ... cluster configuration
}

module "gitops" {
  source = "../../modules/gitops"

  cluster_id   = module.cluster.cluster_id
  cluster_name = module.cluster.cluster_name
  api_url      = module.cluster.api_url

  admin_username = "admin"
  admin_password = var.admin_password

  # Wait for cluster to be ready before deploying GitOps
  depends_on = [module.cluster]
}
```

## Known Limitations

### kubernetes_manifest Authentication Issue

The `kubernetes_manifest` resource type requires API schema validation during Terraform planning, which makes an authenticated API call to discover the schema. Even though the Kubernetes provider is correctly configured with username/password credentials (as evidenced by `kubernetes_namespace_v1` working correctly), `kubernetes_manifest` resources fail with "system:anonymous" errors during the schema discovery phase.

This is a known limitation of `kubernetes_manifest` - it needs API access during planning, not just during apply. Until this is resolved, operator resources (OperatorGroup, Subscription, CSV) cannot be managed via Terraform.

**Workaround**: After the namespace is created, install the operator manually:
- **OpenShift Console**: Operators → OperatorHub → Search "OpenShift GitOps" → Install
- **oc CLI**: Create OperatorGroup and Subscription YAML files and apply them manually

## Post-Deployment

After the namespace is created, you can manually install the GitOps operator. Once installed, you can:

1. **Access ArgoCD Console**: The operator creates an ArgoCD instance in the `openshift-gitops` namespace
2. **Get ArgoCD Admin Password**:
   ```bash
   oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d
   ```
3. **Access ArgoCD Route**:
   ```bash
   oc get route openshift-gitops-server -n openshift-gitops
   ```

## Security Considerations

- **Admin Credentials**: Store `admin_password` as a sensitive variable (never commit to Git)
- **TLS Verification**: Keep `insecure = false` in provider configuration for production environments
- **Network Access**: For private clusters, ensure proper network access is configured before deploying GitOps
- **Operator Permissions**: The GitOps operator requires cluster-admin permissions to manage cluster resources

## Architecture Decision

This module uses the **Kubernetes provider** instead of `local-exec` because:

1. **State Management**: Terraform tracks resources in state, enabling proper updates and deletes
2. **Dependency Handling**: Terraform's dependency graph ensures proper resource ordering
3. **Idempotency**: Terraform handles resource state automatically
4. **Error Handling**: Better error messages and retry logic
5. **Terraform-Native**: Aligns with Terraform's declarative approach
6. **No External Dependencies**: No need for `oc` CLI to be installed

## References

- [OpenShift GitOps Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [OpenShift OperatorHub](https://operatorhub.io/)
- [Terraform Kubernetes Provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)
