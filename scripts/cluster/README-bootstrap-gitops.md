# GitOps Bootstrap Script

This script bootstraps the OpenShift GitOps operator on a ROSA HCP cluster using Helm charts. It is idempotent and can be run multiple times safely.

## Features

- **Idempotent**: Can be run multiple times safely - checks for existing resources before creating
- **Standalone**: Can be run independently or via Terraform
- **Environment Variable Based**: All configuration via environment variables
- **ACM Support**: Supports hub, spoke, and standalone cluster modes
- **Helm Chart Based**: Uses Helm charts to install GitOps operator (replicates pfoster approach)

## Prerequisites

- `oc` CLI installed and in PATH
- `helm` CLI installed and in PATH
- `jq` installed (for JSON parsing)
- `aws` CLI installed and configured
- Access to AWS Secrets Manager containing cluster credentials
- Cluster must be in ready state

## Usage

### Standalone Execution

Set required environment variables and run the script:

```bash
export CLUSTER_NAME="my-cluster"
export CREDENTIALS_SECRET="my-cluster-credentials"
export AWS_REGION="us-east-1"
export ACM_MODE="noacm"  # or "hub" or "spoke"

# Optional: Configure Helm chart versions
export HELM_CHART_VERSION="0.5.4"
export GITOPS_CSV="openshift-gitops-operator.v1.16.0-0.1746014725.p"

# Run the script
./scripts/cluster/bootstrap-gitops.sh
```

### Via Terraform

The script is designed to work with Terraform's `shell_script` provider:

```hcl
terraform {
  required_providers {
    shell = {
      source  = "scottwinkler/shell"
      version = ">= 1.7.10"
    }
  }
}

provider "shell" {
  interpreter        = ["/bin/sh", "-c"]
  enable_parallelism = false
}

resource "shell_script" "gitops_bootstrap" {
  lifecycle_commands {
    create = "${path.root}/scripts/cluster/bootstrap-gitops.sh"
    delete = "${path.root}/scripts/cluster/bootstrap-gitops.sh"
    read   = "${path.root}/scripts/cluster/bootstrap-gitops.sh"
    update = "${path.root}/scripts/cluster/bootstrap-gitops.sh"
  }

  environment = {
    CLUSTER_NAME       = "my-cluster"
    CREDENTIALS_SECRET = "my-cluster-credentials"
    AWS_REGION         = "us-east-1"
    ACM_MODE           = "noacm"
    ENABLE             = "true"
  }
}
```

## Environment Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `CLUSTER_NAME` | Name of the ROSA HCP cluster | `my-cluster` |
| `CREDENTIALS_SECRET` | AWS Secrets Manager secret name containing cluster credentials | `my-cluster-credentials` |
| `AWS_REGION` | AWS region where the cluster is located | `us-east-1` |

### ACM Configuration

| Variable | Description | Default | Required When |
|----------|-------------|---------|---------------|
| `ACM_MODE` | ACM mode: `hub`, `spoke`, or `noacm` | `noacm` | Always |
| `HUB_CREDENTIALS_SECRET` | Hub cluster credentials secret name | - | `ACM_MODE=spoke` |
| `ACM_REGION` | AWS region where ACM hub is located | - | `ACM_MODE=spoke` |

### Helm Chart Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `HELM_REPO_NAME` | Name for Helm repository | `helm_repo_new` |
| `HELM_REPO_URL` | Helm repository URL | `https://rosa-hcp-dedicated-vpc.github.io/helm-repository/` |
| `HELM_CHART` | Helm chart name (hub/standalone) | `cluster-bootstrap` |
| `HELM_CHART_VERSION` | Helm chart version | `0.5.4` |
| `GITOPS_CSV` | GitOps operator CSV | `openshift-gitops-operator.v1.16.0-0.1746014725.p` |

### ACM Spoke Helm Charts

| Variable | Description | Default |
|----------|-------------|---------|
| `HELM_CHART_ACM_SPOKE` | ACM spoke chart name | `cluster-bootstrap-acm-spoke` |
| `HELM_CHART_ACM_SPOKE_VERSION` | ACM spoke chart version | `0.6.3` |
| `HELM_CHART_ACM_HUB_REGISTRATION` | Hub registration chart name | `cluster-bootstrap-acm-hub-registration` |
| `HELM_CHART_ACM_HUB_REGISTRATION_VERSION` | Hub registration chart version | `0.1.0` |

### Optional Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `GIT_PATH` | Git path for environment extraction (e.g., `nonprod/np-ai-1`) | - |
| `AWS_ACCOUNT_ID` | AWS account ID | - |
| `ECR_ACCOUNT` | ECR account ID for image pulls | - |
| `EBS_KMS_KEY_ARN` | KMS key ARN for EBS encryption | - |
| `EFS_FILE_SYSTEM_ID` | EFS file system ID | - |
| `AWS_PRIVATE_CA_ARN` | AWS Private CA ARN | - |
| `AWSPCA_CSV` | AWS Private CA Issuer CSV | `cert-manager-operator.v1.17.0` |
| `AWSPCA_ISSUER` | AWS Private CA Issuer name | - |
| `ZONE_NAME` | Zone name for AWS Private CA | - |
| `ENABLE` | Enable bootstrap (`true`) or cleanup (`false`) | `true` |

## Cluster Credentials Secret Format

The script expects cluster credentials to be stored in AWS Secrets Manager with the following JSON structure:

```json
{
  "url": "https://api.cluster.example.com:6443",
  "user": "admin",
  "password": "admin-password"
}
```

## Idempotency

The script is designed to be idempotent:

- **Helm Releases**: Checks if Helm releases are already deployed before installing
- **Cluster Login**: Verifies existing cluster context before logging in
- **ACM Resources**: Checks for existing resources before creating (ManagedCluster, GitOpsCluster, etc.)
- **Storage Classes**: Only patches if not already configured

## Operation Modes

### Standalone/Hub Cluster (`ACM_MODE=noacm` or `ACM_MODE=hub`)

Installs GitOps operator directly on the cluster:

1. Logs into cluster
2. Sets up Helm repository
3. Installs `cluster-bootstrap` Helm chart
4. Optionally installs AWS Private CA Issuer
5. Configures storage classes

### ACM Spoke Cluster (`ACM_MODE=spoke`)

Registers cluster with ACM hub and installs GitOps:

1. Logs into spoke cluster
2. Installs `cluster-bootstrap-acm-spoke` Helm chart on spoke
3. Logs into hub cluster
4. Installs hub registration chart
5. Retrieves ACM import manifests
6. Applies ACM CRDs and import manifest to spoke
7. Verifies ArgoCD integration

## Cleanup

To cleanup resources, set `ENABLE=false`:

```bash
export ENABLE="false"
export CLUSTER_NAME="my-cluster"
export CREDENTIALS_SECRET="my-cluster-credentials"
export AWS_REGION="us-east-1"
export ACM_MODE="spoke"  # If cleaning up spoke cluster
export HUB_CREDENTIALS_SECRET="hub-credentials"
export ACM_REGION="us-east-1"

./scripts/cluster/bootstrap-gitops.sh
```

## Error Handling

The script includes comprehensive error handling:

- **Validation**: Validates required environment variables before execution
- **Retry Logic**: Retries cluster login up to 5 times with 30-second intervals
- **Error Messages**: Provides clear error messages with line numbers
- **Exit Codes**: Returns JSON status for programmatic use

## Output

The script outputs JSON status messages:

- **Success**: `{"status": "success", "message": "..."}`
- **Failure**: `{"status": "failure", "message": "..."}`

## Troubleshooting

### Cluster Login Fails

- Verify cluster is in ready state: `rosa describe cluster -c ${CLUSTER_NAME}`
- Check credentials secret exists and has correct format
- Verify network access to cluster API endpoint
- For private clusters, ensure you're using bastion or VPN

### Helm Chart Installation Fails

- Verify Helm repository is accessible
- Check chart version exists in repository
- Ensure cluster has internet access (for Helm repo)
- Check Helm release status: `helm list -A`

### ACM Spoke Registration Fails

- Verify hub cluster credentials are correct
- Check ACM hub is accessible from spoke region
- Verify import secret exists on hub: `oc get secret -n ${CLUSTER_NAME} ${CLUSTER_NAME}-import`
- Check klusterlet status: `oc get klusterlet klusterlet`

## References

- Reference Implementation: `./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/9.bootstrap.tf`
- Helm Repository: https://rosa-hcp-dedicated-vpc.github.io/helm-repository/
- OpenShift GitOps Documentation: https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/
