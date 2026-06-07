# IAM roles for Tekton pipeline (push/pull) and ECR Secret Operator (GetAuthorizationToken).
# Reference: reference/rhhi-blueprint.md §3.1–§3.2
# IRSA pattern: modules/infrastructure/iam/40-secrets-manager-iam.tf

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  oidc_endpoint_url_normalized = replace(var.oidc_endpoint_url, "https://", "")
  common_tags = merge(var.tags, {
    ManagedBy   = "Terraform"
    ClusterName = var.cluster_name
    Purpose     = "RHHI-SupplyChain"
  })
  ecr_repository_arn = "arn:${data.aws_partition.current.partition}:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/${var.ecr_repository_prefix}/*"
}

resource "aws_iam_policy" "tekton_ecr" {
  name        = "${var.cluster_name}-rhhi-tekton-ecr"
  description = "ECR create/push/pull for RHHI Tekton pipeline on ${var.ecr_repository_prefix}/* (repos created on demand by pipeline)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuthToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "ECRPullPushCacheAccess"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:CreateRepository",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = local.ecr_repository_arn
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role" "tekton_ecr" {
  name = "${var.cluster_name}-rhhi-tekton-ecr"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_endpoint_url_normalized}:sub" = "system:serviceaccount:${var.tekton_namespace}:${var.tekton_service_account}"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "tekton_ecr" {
  role       = aws_iam_role.tekton_ecr.name
  policy_arn = aws_iam_policy.tekton_ecr.arn
}

resource "aws_iam_policy" "ecr_operator" {
  name        = "${var.cluster_name}-rhhi-ecr-operator"
  description = "ECR GetAuthorizationToken for RHHI ECR Secret Operator"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuthToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role" "ecr_operator" {
  name = "${var.cluster_name}-rhhi-ecr-operator"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_endpoint_url_normalized}:sub" = "system:serviceaccount:${var.ecr_operator_namespace}:ecr-secret-operator-controller-manager"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecr_operator" {
  role       = aws_iam_role.ecr_operator.name
  policy_arn = aws_iam_policy.ecr_operator.arn
}
