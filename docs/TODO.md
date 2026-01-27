# TODO: Missing Features from Pfoster Example

This document tracks features from the pfoster example (`reference/pfoster/rosa-hcp-dedicated-vpc/`) that are not yet implemented in this repository.

## Day 2 Operations

### 1. Secrets Manager IAM Integration ✅ [DONE]
**Reference**: `terraform/3.secrets.tf`

**Status**: Implemented

**What Was Implemented**:
- ✅ IAM policy for Secrets Manager access (restricted to explicit secret ARN list for security)
- ✅ IAM role with OIDC trust policy for `openshift-gitops:vplugin` service account
- ✅ Policy attachment to role
- ✅ Support for multiple secrets via `additional_secrets` variable
- ✅ Automatic inclusion of cluster credentials secret
- ✅ Data source lookups for additional secrets to get exact ARNs
- ✅ Variable `enable_secrets_manager_iam` added (default: `false`)
- ✅ Variable `additional_secrets` added (optional list of secret names)
- ✅ Outputs added to expose IAM role ARN

**Security Recommendation**:
⚠️ **CRITICAL**: The pfoster example uses `Resource = "*"` which grants access to ALL secrets in the account. This is a security risk.

**Recommended Secure Implementation: Explicit Secret List with Exact ARNs**:
For maximum security, use an explicit list of secret ARNs (obtained via data source lookups) and restrict the IAM policy to only those specific secrets.

**Benefits**:
- **Maximum Security**: Only explicitly listed secrets are accessible
- **Principle of Least Privilege**: No access to secrets from other clusters or unrelated secrets
- **Precise ARNs**: Using exact ARNs (via data sources) is more precise than wildcard patterns
- **Audit Trail**: Clear visibility of which secrets are accessible
- **Production Ready**: Best practice for production environments with strict security requirements

**Trade-offs**:
- Less flexible: Requires updating IAM policy when adding new secrets
- Requires Terraform apply when secrets are added/removed
- More explicit configuration needed
- Requires data source lookups (adds dependency on secret existence)

**Implementation Approach**:
1. **Variable**: Accept a list of secret names that should be accessible
   - Default: Include the cluster credentials secret (`${cluster_name}-credentials`)
   - Optional: Support additional secrets via `additional_secrets` variable (list of secret names)

2. **Data Sources**: Use `aws_secretsmanager_secret` data sources to lookup exact ARNs
   - Lookup secrets by name to get exact ARNs
   - Handle cases where secrets may not exist yet (use `count` or conditional lookups)
   - Build policy resource list from exact ARNs

3. **Secret Creation**: When creating additional secrets, automatically add them to the IAM policy
   - Use `for_each` to create secrets from a map
   - Use resource ARNs directly (no need for data sources if created in same module)

4. **Policy Structure**: Include `ListSecrets` action (GitOps needs this)
   - `ListSecrets` requires `Resource = "*"` but actual secret access is still restricted by explicit ARN list
   - Document that `ListSecrets` grants broader access but `GetSecretValue` is restricted

**Recommended Policy Structure**:
```hcl
# Using exact ARNs from data source lookups and created secrets
locals {
  # Default secret (created by this module)
  default_secret_arn = var.enable_gitops_bootstrap && length(aws_secretsmanager_secret.cluster_credentials) > 0 ?
    aws_secretsmanager_secret.cluster_credentials[0].arn : null

  # Lookup additional secrets by name (if they exist)
  additional_secret_arns = var.additional_secrets != null ? [
    for secret_name in var.additional_secrets :
    data.aws_secretsmanager_secret.additional[secret_name].arn
  ] : []

  # Combine all secret ARNs (filter out nulls)
  all_secret_arns = compact(concat(
    local.default_secret_arn != null ? [local.default_secret_arn] : [],
    local.additional_secret_arns
  ))
}

# Data sources for additional secrets (if provided)
data "aws_secretsmanager_secret" "additional" {
  for_each = var.additional_secrets != null ? toset(var.additional_secrets) : toset([])
  name     = each.value
}

policy = jsonencode({
  Version = "2012-10-17"
  Statement = [
    {
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = local.all_secret_arns
    },
    {
      Effect = "Allow"
      Action = [
        "secretsmanager:ListSecrets"
      ]
      # ListSecrets requires * but actual secret access is restricted above
      Resource = "*"
    }
  ]
})
```

**Note**:
- `ListSecrets` action requires `Resource = "*"` and cannot be restricted to specific secrets
- This is acceptable for GitOps use case - the action allows listing but actual secret access is still restricted by the explicit ARN list in the first statement
- The policy follows principle of least privilege for actual secret retrieval while allowing necessary listing functionality

**Implementation Notes**:
- Create IAM policy for Secrets Manager access (restricted to explicit list of exact secret ARNs)
- Create IAM role with OIDC trust policy for `openshift-gitops:vplugin` service account
- Attach policy to role
- **Variable Design**:
  - `enable_secrets_manager_iam` (bool, default: false) - Enable IAM role creation
  - `additional_secrets` (list(string), optional) - Additional secret names to grant access to (e.g., `["secret-1", "secret-2"]`)
- **Secret Management**:
  - Default secret (`${cluster_name}-credentials`) is always included in policy (if GitOps bootstrap is enabled)
  - Additional secrets are looked up by name using `aws_secretsmanager_secret` data sources
  - Secrets can be created by this module OR referenced by name if created elsewhere
  - All secrets should be tagged with `Cluster = var.cluster_name` for organization
- **Policy Construction**:
  - Use exact ARNs from:
    1. Created secrets: `aws_secretsmanager_secret.cluster_credentials[0].arn` (if created in module)
    2. Data source lookups: `data.aws_secretsmanager_secret.additional[secret_name].arn` (for additional secrets)
  - Build ARN list by combining default and additional secret ARNs
  - Include `ListSecrets` action with `Resource = "*"` (required for GitOps, actual access still restricted by explicit ARN list)
- **Data Source Handling**:
  - Use `for_each` with `toset()` to create data sources for each additional secret name
  - Handle cases where secrets may not exist (data source will fail if secret doesn't exist - document this requirement)
  - Consider adding validation to ensure secrets exist before creating IAM policy

**Files Created/Modified**:
- ✅ `modules/infrastructure/cluster/40-secrets-manager-iam.tf` (created)
  - IAM policy with explicit secret ARN list
  - IAM role with OIDC trust policy for `openshift-gitops:vplugin`
  - Policy attachment
  - Data sources for additional secrets lookup
  - Locals for building secret ARN list
- ✅ `modules/infrastructure/cluster/01-variables.tf` (added variables)
  - `enable_secrets_manager_iam` variable (bool, default: false)
  - `additional_secrets` variable (list(string), optional)
- ✅ `modules/infrastructure/cluster/90-outputs.tf` (added output)
  - `secrets_manager_role_arn` output
- ✅ `terraform/01-variables.tf` (added variables)
  - `enable_secrets_manager_iam` variable
  - `additional_secrets` variable
- ✅ `terraform/10-main.tf` (passed variables to cluster module)
- ✅ `terraform/90-outputs.tf` (exposed secrets_manager_role_arn from cluster module)

**Security Implementation**:
- ✅ Uses explicit secret ARN list instead of wildcards (`Resource = "*"`)
- ✅ `GetSecretValue` and `DescribeSecret` restricted to explicit ARN list
- ✅ `ListSecrets` uses `Resource = "*"` (required by GitOps, but actual access is restricted)
- ✅ Cluster credentials secret automatically included
- ✅ Additional secrets looked up by name via data sources to get exact ARNs

---

### 2. CloudWatch Logging for OpenShift Logging Operator ✅ [DONE]
**Reference**: `terraform/4.logging.tf`

**Status**: Implemented

**What Was Implemented**:
- ✅ IAM policy for CloudWatch Logs access (CreateLogGroup, CreateLogStream, DescribeLogGroups, DescribeLogStreams, PutLogEvents, PutRetentionPolicy)
- ✅ IAM role with OIDC trust policy for `openshift-logging:logging` service account (used by ClusterLogForwarder)
- ✅ Policy attachment to role
- ✅ Variable `enable_cloudwatch_logging` added (default: `false`)
- ✅ Outputs added to expose IAM role ARN
- ✅ Role name matches pfoster reference: `${cluster_name}-rosa-cloudwatch-role-iam`

**Files Created/Modified**:
- ✅ `modules/infrastructure/cluster/21-cloudwatch-logging.tf` (created)
- ✅ `modules/infrastructure/cluster/01-variables.tf` (added `enable_cloudwatch_logging` variable)
- ✅ `modules/infrastructure/cluster/90-outputs.tf` (added `cloudwatch_logging_role_arn` output)
- ✅ `terraform/01-variables.tf` (added `enable_cloudwatch_logging` variable)
- ✅ `terraform/10-main.tf` (passed variable to cluster module)
- ✅ `terraform/90-outputs.tf` (exposed cloudwatch_logging_role_arn from cluster module)

---

### 3. Cert Manager IAM Roles ✅ [DONE]
**Reference**: `terraform/6.cert-manager.tf`

**Status**: Implemented

**What Was Implemented**:
- ✅ IAM policy for AWS Private CA access (`acm-pca:DescribeCertificateAuthority`, `acm-pca:GetCertificate`, `acm-pca:IssueCertificate`)
- ✅ IAM role with OIDC trust policy for `cert-manager:cert-manager` service account
- ✅ Policy attachment to role
- ✅ Bootstrap script updated to use `CERT_MANAGER_ROLE_ARN` environment variable from Terraform output
- ✅ Outputs added to expose IAM role ARN
- ✅ Variable `enable_cert_manager_iam` added (default: `false`)

**Files Created/Modified**:
- ✅ `modules/infrastructure/cluster/50-cert-manager-iam.tf` (created)
- ✅ `modules/infrastructure/cluster/01-variables.tf` (added `enable_cert_manager_iam` variable)
- ✅ `modules/infrastructure/cluster/90-outputs.tf` (added `cert_manager_role_arn` output and included in bootstrap env vars)
- ✅ `scripts/cluster/bootstrap-gitops.sh` (updated to use `CERT_MANAGER_ROLE_ARN` if provided)
- ✅ `modules/infrastructure/cluster/README.md` (documented new variable and output)
- ✅ `terraform/90-outputs.tf` (exposed cert_manager_role_arn from cluster module)

---

### 4. ETCD KMS Key ✅ [DONE]
**Reference**: `terraform/1.main.tf` (lines 5-12)

**Status**: Implemented

**What Was Implemented**:
- ✅ Created `aws_kms_key.etcd` resource in `11-storage.tf`
- ✅ Created `aws_kms_alias.etcd` resource
- ✅ KMS key is created when `enable_storage = true` and `etcd_encryption = true`
- ✅ Cluster resource uses `etcd_kms_key_arn` field when `etcd_encryption = true`
- ✅ Key persists through sleep operations (like EBS/EFS keys)
- ✅ New outputs: `etcd_kms_key_id` and `etcd_kms_key_arn`

**Files Created/Modified**:
- ✅ `modules/infrastructure/cluster/11-storage.tf` (added etcd KMS key and alias)
- ✅ `modules/infrastructure/cluster/10-main.tf` (added `etcd_kms_key_arn` to cluster resource)
- ✅ `modules/infrastructure/cluster/90-outputs.tf` (added etcd KMS key outputs)
- ✅ `terraform/90-outputs.tf` (exposed etcd KMS key outputs from cluster module)
- ✅ `modules/infrastructure/cluster/README.md` (documented new outputs)

---

### 5. Ingress Controller Deployment with Route53 📋 [PLANNED]
**Reference**: `terraform/11.ingress.tf` and `scripts/ingress.tftpl`

**Status**: Implementation plan documented

**Approach**: Use cert-manager and external-dns operators for automatic certificate and DNS management (GitOps-first approach)

**Implementation Plan**: See [`docs/improvements/ingress.md`](improvements/ingress.md) for detailed implementation plan

**What Will Be Implemented**:
- Route53 private hosted zone creation (Terraform)
- IAM role for external-dns to manage Route53 records (Terraform)
- cert-manager and external-dns deployment via Helm/GitOps
- Ingress controller deployment via Helm/GitOps
- Automatic certificate creation via cert-manager
- Automatic DNS record creation via external-dns

**Key Design Decisions**:
- Minimal Terraform: Only AWS infrastructure (Route53 zone, IAM roles)
- GitOps-First: All Kubernetes resources deployed via Helm/GitOps
- Operator-Based: cert-manager and external-dns handle automation
- No Scripts: Eliminates need for shell scripts or Helm CLI calls from Terraform

---

### 6. Termination Protection ✅ [DONE]
**Reference**: `terraform/13.termination-protection.tf` and `scripts/termination-protection.tftpl`

**Status**: Implemented

**What Was Implemented**:
- ✅ Created `scripts/cluster/termination-protection.sh` script
- ✅ Script uses ROSA CLI (`rosa edit cluster --enable-delete-protection`) to enable protection
- ✅ Created `shell_script` resource in `modules/infrastructure/cluster/75-termination-protection.tf`
- ✅ Added `enable_termination_protection` variable (default: `false`)
- ✅ Script is idempotent and handles both enable/disable operations
- ✅ Script uses existing ROSA login session (no token required)
- ✅ Note: Disabling protection cannot be done via CLI (requires OCM console), script documents this

**Files Created/Modified**:
- ✅ `scripts/cluster/termination-protection.sh` (created)
- ✅ `modules/infrastructure/cluster/75-termination-protection.tf` (created)
- ✅ `modules/infrastructure/cluster/01-variables.tf` (added `enable_termination_protection` variable)
- ✅ `modules/infrastructure/cluster/README.md` (documented new variable)
- ✅ `CHANGELOG.md` (documented new feature)

---

## Infrastructure Features

### 7. EFS Backup Configuration
**Reference**: `terraform/7.storage.tf` (lines 256-336, commented out)

**What's Missing**:
- AWS Backup configuration for EFS
- Backup vault, plan, and selection
- Automated EFS backup scheduling

**Implementation Notes**:
- Create AWS Backup vault with KMS encryption
- Create backup plan with schedule
- Create backup selection targeting EFS file system
- IAM role for AWS Backup service

**Files to Create/Modify**:
- `modules/infrastructure/cluster/12-efs-backup.tf` (new)
- Update `modules/infrastructure/cluster/01-variables.tf` to add:
  - `enable_efs_backup` variable
  - `efs_backup_schedule` variable
  - `efs_backup_retention_days` variable
- Update `modules/infrastructure/cluster/90-outputs.tf` to expose backup plan/vault IDs

---

## Implementation Priority

### High Priority (Core Day 2 Operations)
1. **Cert Manager IAM Roles** - Required for AWS Private CA Issuer to work
2. **CloudWatch Logging** - Common production requirement
3. **ETCD KMS Key** - Security best practice for etcd encryption

### Medium Priority (Useful Day 2 Operations)
4. **Secrets Manager IAM Integration** ✅ - Useful for GitOps secrets management
5. **Ingress Controller Deployment** - Common requirement for application access
6. **Termination Protection** ✅ - Safety feature for production clusters

### Low Priority (Specialized Features)
7. **EFS Backup** - Nice-to-have for data protection

---

## Notes

- All new features should follow existing patterns:
  - Use `persists_through_sleep` variable for resource lifecycle
  - Add `persists_through_sleep = "true"` tag to resources that should persist
  - Use `shell_script` provider for scripts that interact with cluster
  - Follow existing module structure and naming conventions
  - Update CHANGELOG.md when implementing features
  - Update PLAN.md if architecture changes

- Reference implementations:
  - Pfoster example: `reference/pfoster/rosa-hcp-dedicated-vpc/terraform/`
  - Script templates: `reference/pfoster/rosa-hcp-dedicated-vpc/terraform/scripts/`

- Testing considerations:
  - Test with both public and private clusters
  - Test with `persists_through_sleep = true` and `false`
  - Verify idempotency of scripts
  - Test cleanup/destroy operations
