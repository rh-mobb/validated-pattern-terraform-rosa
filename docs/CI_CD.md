# CI/CD Integration Guide

This guide provides examples and best practices for integrating ROSA HCP cluster management into CI/CD pipelines.

## Overview

The repository provides bash scripts that can be called directly from CI/CD pipelines without requiring Make. The Makefile is a convenience wrapper for local development.

## Script-Based Approach

All cluster operations are implemented as bash scripts in the `scripts/` directory:

- **`scripts/cluster/`**: Infrastructure and configuration management
- **`scripts/tunnel/`**: Tunnel management for egress-zero clusters
- **`scripts/utils/`**: Utility functions
- **`scripts/info/`**: Cluster information and access

See [scripts/README.md](../scripts/README.md) for complete documentation.

## GitHub Actions Example

```yaml
name: Deploy ROSA HCP Cluster

on:
  push:
    branches: [main]
    paths:
      - 'clusters/**'
      - 'terraform/**'
      - 'modules/**'

env:
  CLUSTER_NAME: my-cluster
  AWS_REGION: us-east-1

jobs:
  infrastructure:
    name: Deploy Infrastructure
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.5.0

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Setup backend configuration
        run: |
          export TF_BACKEND_CONFIG_BUCKET="${{ secrets.TF_STATE_BUCKET }}"
          export TF_BACKEND_CONFIG_REGION="${{ env.AWS_REGION }}"
          export TF_BACKEND_CONFIG_DYNAMODB_TABLE="${{ secrets.TF_STATE_LOCK_TABLE }}"

      - name: Initialize infrastructure
        run: ./scripts/cluster/init-infrastructure.sh ${{ env.CLUSTER_NAME }}

      - name: Plan infrastructure
        run: ./scripts/cluster/plan-infrastructure.sh ${{ env.CLUSTER_NAME }}

      - name: Apply infrastructure
        run: ./scripts/cluster/apply-infrastructure.sh ${{ env.CLUSTER_NAME }}

      - name: Generate configuration.tfvars
        run: ./scripts/cluster/generate-config-tfvars.sh ${{ env.CLUSTER_NAME }}

      - name: Upload configuration.tfvars
        uses: actions/upload-artifact@v3
        with:
          name: configuration-tfvars
          path: clusters/${{ env.CLUSTER_NAME }}/configuration.tfvars

  configuration:
    name: Deploy Configuration
    runs-on: ubuntu-latest
    needs: infrastructure
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.5.0

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Setup backend configuration
        run: |
          export TF_BACKEND_CONFIG_BUCKET="${{ secrets.TF_STATE_BUCKET }}"
          export TF_BACKEND_CONFIG_REGION="${{ env.AWS_REGION }}"
          export TF_BACKEND_CONFIG_DYNAMODB_TABLE="${{ secrets.TF_STATE_LOCK_TABLE }}"

      - name: Download configuration.tfvars
        uses: actions/download-artifact@v3
        with:
          name: configuration-tfvars
          path: clusters/${{ env.CLUSTER_NAME }}/

      - name: Setup OpenShift CLI
        run: |
          curl -sSL https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz | tar -xz
          sudo mv oc kubectl /usr/local/bin/

      - name: Initialize configuration
        run: ./scripts/cluster/init-configuration.sh ${{ env.CLUSTER_NAME }}

      - name: Plan configuration
        run: ./scripts/cluster/plan-configuration.sh ${{ env.CLUSTER_NAME }}

      - name: Apply configuration
        run: ./scripts/cluster/apply-configuration.sh ${{ env.CLUSTER_NAME }}
```

## GitLab CI Example

```yaml
stages:
  - infrastructure
  - configuration

variables:
  CLUSTER_NAME: my-cluster
  AWS_REGION: us-east-1
  TF_BACKEND_CONFIG_BUCKET: "my-terraform-state"
  TF_BACKEND_CONFIG_REGION: "us-east-1"
  TF_BACKEND_CONFIG_DYNAMODB_TABLE: "terraform-locks"

infrastructure:
  stage: infrastructure
  image: hashicorp/terraform:1.5.0
  before_script:
    - apk add --no-cache bash aws-cli jq
    - chmod +x scripts/**/*.sh
  script:
    - export TF_VAR_token="$RHCS_TOKEN"
    - ./scripts/cluster/init-infrastructure.sh $CLUSTER_NAME
    - ./scripts/cluster/plan-infrastructure.sh $CLUSTER_NAME
    - ./scripts/cluster/apply-infrastructure.sh $CLUSTER_NAME
    - ./scripts/cluster/generate-config-tfvars.sh $CLUSTER_NAME
  artifacts:
    paths:
      - clusters/$CLUSTER_NAME/configuration.tfvars
    expire_in: 1 hour
  only:
    - main
    - merge_requests

configuration:
  stage: configuration
  image: hashicorp/terraform:1.5.0
  before_script:
    - apk add --no-cache bash aws-cli jq curl
    - chmod +x scripts/**/*.sh
    # Install OpenShift CLI
    - curl -sSL https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz | tar -xz
    - mv oc kubectl /usr/local/bin/
  script:
    - ./scripts/cluster/init-configuration.sh $CLUSTER_NAME
    - ./scripts/cluster/plan-configuration.sh $CLUSTER_NAME
    - ./scripts/cluster/apply-configuration.sh $CLUSTER_NAME
  dependencies:
    - infrastructure
  only:
    - main
```

## Jenkins Pipeline Example

```groovy
pipeline {
    agent any

    environment {
        CLUSTER_NAME = 'my-cluster'
        AWS_REGION = 'us-east-1'
        TF_BACKEND_CONFIG_BUCKET = credentials('tf-state-bucket')
        TF_BACKEND_CONFIG_REGION = 'us-east-1'
        TF_BACKEND_CONFIG_DYNAMODB_TABLE = credentials('tf-state-lock-table')
    }

    stages {
        stage('Infrastructure') {
            steps {
                sh '''
                    chmod +x scripts/**/*.sh
                    ./scripts/cluster/init-infrastructure.sh ${CLUSTER_NAME}
                    ./scripts/cluster/plan-infrastructure.sh ${CLUSTER_NAME}
                    ./scripts/cluster/apply-infrastructure.sh ${CLUSTER_NAME}
                    ./scripts/cluster/generate-config-tfvars.sh ${CLUSTER_NAME}
                '''
            }
        }

        stage('Configuration') {
            steps {
                sh '''
                    chmod +x scripts/**/*.sh
                    ./scripts/cluster/init-configuration.sh ${CLUSTER_NAME}
                    ./scripts/cluster/plan-configuration.sh ${CLUSTER_NAME}
                    ./scripts/cluster/apply-configuration.sh ${CLUSTER_NAME}
                '''
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'clusters/${CLUSTER_NAME}/configuration.tfvars', fingerprint: true
        }
    }
}
```

## Environment Variables

### Required Variables

- `TF_VAR_token`: Red Hat Cloud Services (RHCS) token
- `TF_VAR_admin_password`: Admin password (optional, can be generated)

### Backend Configuration

For remote S3 backend:

```bash
export TF_BACKEND_CONFIG_BUCKET="my-terraform-state-bucket"
export TF_BACKEND_CONFIG_REGION="us-east-1"
export TF_BACKEND_CONFIG_DYNAMODB_TABLE="terraform-state-lock"  # Optional
```

### CI/CD Specific Variables

- `AUTO_APPROVE=true`: Skip confirmation prompts (used by sleep/cleanup scripts)
- `TF_VAR_k8s_token`: Kubernetes token (if not set, script will obtain via oc login)

## Destroy vs Sleep

- **`destroy-*`**: Shows warnings, prompts for confirmation (interactive). For permanent cluster removal.
- **`cleanup-*`** (used by `make sleep`): Same as destroy but uses `-auto-approve` flag (non-interactive). Designed for temporarily shutting down clusters while preserving resources.

**Sleep** preserves:
- DNS domain (if `enable_persistent_dns_domain=true`)
- Admin password in AWS Secrets Manager
- IAM roles and OIDC configuration
- KMS keys and EFS (if not explicitly destroyed)
- GitOps configurations (automatically redeployed when cluster is recreated)

**Note**: Sleep does NOT hibernate the cluster - it destroys cluster resources. The cluster must be recreated using `make apply` to "wake" it. Since GitOps manages all important configurations and applications, they will be automatically redeployed.

For CI/CD pipelines, use `cleanup-*` scripts or set `AUTO_APPROVE=true`:

```bash
# Sleep cluster (preserves resources for easy restart)
AUTO_APPROVE=true ./scripts/cluster/cleanup-infrastructure.sh my-cluster
```

## Best Practices

### 1. Separate Infrastructure and Configuration Stages

Infrastructure and configuration should be deployed in separate pipeline stages:

- **Infrastructure stage**: Deploys VPC, IAM roles, and cluster
- **Configuration stage**: Deploys GitOps operator and other Day 2 configurations

This separation allows:
- Independent state management
- Different approval workflows
- Better error isolation

### 2. Generate configuration.tfvars

After infrastructure deployment, generate `configuration.tfvars`:

```bash
./scripts/cluster/generate-config-tfvars.sh my-cluster
```

This file can be:
- Uploaded as an artifact
- Passed to the configuration stage
- Used for configuration planning

### 3. Use Remote Backend

Always use a remote backend (S3, Terraform Cloud, etc.) for production:

```bash
export TF_BACKEND_CONFIG_BUCKET="my-terraform-state"
export TF_BACKEND_CONFIG_REGION="us-east-1"
export TF_BACKEND_CONFIG_DYNAMODB_TABLE="terraform-locks"
```

### 4. Handle Egress-Zero Clusters

For egress-zero clusters, tunnel management is handled automatically by the scripts. However, ensure:

- Bastion is deployed (`enable_bastion=true`)
- SSM VPC endpoints are configured
- AWS credentials have SSM permissions

### 5. Error Handling

Scripts use `set -euo pipefail` for strict error handling. Ensure your pipeline:

- Fails fast on errors
- Captures error output
- Provides clear error messages

### 6. Secrets Management

Store sensitive values in CI/CD secrets:

- `TF_VAR_token`: RHCS token
- `TF_VAR_admin_password`: Admin password
- AWS credentials: Access key ID and secret access key

Never commit secrets to version control.

## Troubleshooting

### Script Not Found

Ensure scripts are executable:

```bash
chmod +x scripts/**/*.sh
```

### Backend Configuration Errors

Verify backend environment variables are set:

```bash
echo $TF_BACKEND_CONFIG_BUCKET
echo $TF_BACKEND_CONFIG_REGION
```

### Tunnel Issues (Egress-Zero)

For egress-zero clusters, ensure:

1. Bastion is deployed
2. SSM agent is online
3. VPC endpoints are configured
4. AWS credentials have SSM permissions

Check tunnel status:

```bash
./scripts/tunnel/status.sh my-cluster
```

### Infrastructure Outputs Not Available

If configuration layer can't access infrastructure outputs:

1. Ensure infrastructure has been applied
2. Generate configuration.tfvars: `./scripts/cluster/generate-config-tfvars.sh my-cluster`
3. Verify infrastructure outputs: `cd terraform && terraform output`

## See Also

- [scripts/README.md](../scripts/README.md) - Complete script documentation
- [clusters/README.md](../clusters/README.md) - Cluster configuration guide
- [Main README](../README.md) - Project overview
