# ECR pull-through cache and repository creation template for RHHI images.
# Reference: reference/rhhi-blueprint.md §2.2–§2.3

# Public quay.io/hummingbird/* images do not require upstream credentials.
# To use registry.redhat.io or a private quay namespace, add an
# ecr-pullthroughcache/ Secrets Manager secret and credential_arn (see blueprint §2.1).
resource "aws_ecr_pull_through_cache_rule" "quay_cache" {
  ecr_repository_prefix = var.ecr_repository_prefix
  upstream_registry_url = var.upstream_registry_url
}

resource "aws_ecr_repository_creation_template" "hardened" {
  prefix               = var.ecr_repository_prefix
  description          = "Automated security baseline for RHHI cached repositories"
  image_tag_mutability = "IMMUTABLE"

  applied_for = ["PULL_THROUGH_CACHE"]

  encryption_configuration {
    encryption_type = var.enable_ecr_kms_encryption ? "KMS" : "AES256"
    kms_key         = var.enable_ecr_kms_encryption ? aws_kms_key.ecr[0].arn : null
  }

  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Purge intermediate and untagged builds after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })

  depends_on = [aws_ecr_pull_through_cache_rule.quay_cache]
}
