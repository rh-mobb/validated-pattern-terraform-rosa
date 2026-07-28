# Secrets Manager IAM Configuration
# Reference: ./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/3.secrets.tf
# This configuration creates an IAM role and policy for ArgoCD to access AWS Secrets Manager via OIDC.
# The role uses OIDC federation to allow the ArgoCD Vault Plugin service account to assume the role.
#
# IMPORTANT: The OIDC endpoint URL must NOT include the "https://" prefix when used in IAM trust policies.
# Reference: Red Hat documentation shows stripping https:// from the OIDC endpoint URL
#
# SECURITY: Explicit secret ARN list only — no wildcards for GetSecretValue.
# Cluster credentials ({cluster}-credentials) are intentionally NOT included: that secret is for
# bootstrap/oc login only. AVP must list app secrets via var.additional_secrets (least privilege).
# Relates to #39.

# Data sources for AVP-allowlisted secrets (lookup by name for exact ARNs)
data "aws_secretsmanager_secret" "additional" {
  for_each = local.persists_through_sleep && var.enable_secrets_manager_iam && var.additional_secrets != null ? toset(var.additional_secrets) : toset([])
  name     = each.value
}

locals {
  # AVP allowlist: only secrets explicitly named in additional_secrets
  all_secret_arns = local.persists_through_sleep && var.enable_secrets_manager_iam && var.additional_secrets != null ? [
    for secret_name in var.additional_secrets :
    data.aws_secretsmanager_secret.additional[secret_name].arn
  ] : []
}

# IAM Policy for Secrets Manager
# Grants permissions to access specific secrets via explicit ARN list
# Uses explicit ARNs for GetSecretValue (secure) and "*" for ListSecrets (required by GitOps)
resource "aws_iam_policy" "secrets_manager" {
  count = local.persists_through_sleep && var.enable_secrets_manager_iam ? 1 : 0

  name        = "${var.cluster_name}-rosa-secretsmanager"
  path        = "/"
  description = "IAM policy for ArgoCD Vault Plugin to access AWS Secrets Manager (restricted to explicit secret ARNs)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        # Restrict to explicit list of secret ARNs for maximum security
        Resource = local.all_secret_arns
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets"
        ]
        # ListSecrets requires "*" but actual secret access is restricted above
        # This allows GitOps to list secrets but only access those in the explicit ARN list
        Resource = "*"
      }
    ]
  })

  lifecycle {
    precondition {
      condition     = length(local.all_secret_arns) > 0
      error_message = "enable_secrets_manager_iam requires additional_secrets to list at least one secret name for AVP. Cluster credentials ({cluster}-credentials) are not included automatically — they are for bootstrap/oc login only."
    }
  }

  tags = merge(local.common_tags, {
    Name      = "${var.cluster_name}-rosa-secretsmanager-policy"
    Purpose   = "SecretsManager"
    ManagedBy = "Terraform"
  })
}

# IAM Role for Secrets Manager
# Uses OIDC federation to allow the ArgoCD Vault Plugin service account to assume this role
# Service account: system:serviceaccount:openshift-gitops:vplugin
resource "aws_iam_role" "secrets_manager" {
  count = local.persists_through_sleep && var.enable_secrets_manager_iam ? 1 : 0

  name                 = substr("${var.cluster_name}-rosa-secretsmanager-role-iam", 0, 64)
  permissions_boundary = var.custom_permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_endpoint_url_normalized}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_endpoint_url_normalized}:sub" = "system:serviceaccount:openshift-gitops:vplugin"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name      = "${var.cluster_name}-rosa-secretsmanager-role-iam"
    Purpose   = "SecretsManager"
    ManagedBy = "Terraform"
  })
}

# Attach the Secrets Manager policy to the role
resource "aws_iam_role_policy_attachment" "secrets_manager" {
  count = local.persists_through_sleep && var.enable_secrets_manager_iam ? 1 : 0

  role       = aws_iam_role.secrets_manager[0].name
  policy_arn = aws_iam_policy.secrets_manager[0].arn

  depends_on = [
    aws_iam_policy.secrets_manager,
    aws_iam_role.secrets_manager
  ]
}
