# CloudWatch Audit Log Forwarding Configuration
# Reference: https://access.redhat.com/solutions/7002219
# This configuration creates an IAM role and policy for CloudWatch audit log forwarding.
# The role uses OIDC federation to allow the OpenShift audit log exporter service account to assume the role.
#
# IMPORTANT: The OIDC endpoint URL must NOT include the "https://" prefix when used in IAM trust policies.
# Reference: Red Hat documentation shows stripping https:// from the OIDC endpoint URL
#
# NOTE: If you see a "Provider produced inconsistent final plan" error from the time provider in the
# oidc_config_and_provider module, this is a known issue where the upstream module's time_sleep resource
# sees the OIDC endpoint URL format change. This typically resolves on the next apply. The normalization
# here only affects our IAM trust policy and does not modify the upstream module's behavior.
# The oidc_endpoint_url_normalized local is defined in 10-main.tf

# IAM Policy for CloudWatch Logging
# Grants permissions to create log groups, log streams, and write log events to CloudWatch
resource "aws_iam_policy" "cloudwatch_audit_logging" {
  count = local.persists_through_sleep && var.enable_audit_logging ? 1 : 0

  name        = "${var.cluster_name}-rosa-cloudwatch-audit-logging"
  path        = "/"
  description = "IAM policy for ROSA HCP CloudWatch audit log forwarding"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:PutRetentionPolicy"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name      = "${var.cluster_name}-rosa-cloudwatch-audit-logging-policy"
    Purpose   = "CloudWatchAuditLogging"
    ManagedBy = "Terraform"
  })
}

# IAM Role for CloudWatch Audit Logging
# Uses OIDC federation to allow the OpenShift audit log exporter service account to assume this role
# Service account: system:serviceaccount:openshift-config-managed:cloudwatch-audit-exporter
# Reference: https://access.redhat.com/solutions/7002219
# Note: The service account is different from regular CloudWatch logging (which uses openshift-logging:cluster-logging)
resource "aws_iam_role" "cloudwatch_audit_logging" {
  count = local.persists_through_sleep && var.enable_audit_logging ? 1 : 0

  name = "${var.cluster_name}-rosa-cloudwatch-audit-logging-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_endpoint_url_normalized}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_endpoint_url_normalized}:sub" = "system:serviceaccount:openshift-config-managed:cloudwatch-audit-exporter"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name      = "${var.cluster_name}-rosa-cloudwatch-audit-logging-role"
    Purpose   = "CloudWatchAuditLogging"
    ManagedBy = "Terraform"
  })
}

# Attach the CloudWatch logging policy to the role
resource "aws_iam_role_policy_attachment" "cloudwatch_audit_logging" {
  count = local.persists_through_sleep && var.enable_audit_logging ? 1 : 0

  role       = aws_iam_role.cloudwatch_audit_logging[0].name
  policy_arn = aws_iam_policy.cloudwatch_audit_logging[0].arn
}

# Configure audit log forwarding on the cluster using ROSA CLI
# Using script-based approach until audit_log_arn is available in official provider release
# Once PR is accepted, we can switch to provider-native implementation in 10-main.tf
# Reference: ./reference/rosa-hcp-dedicated-vpc/terraform/5.siem-logging.tf
resource "null_resource" "configure_audit_logging" {
  count = local.persists_through_sleep && var.enable_audit_logging && length(rhcs_cluster_rosa_hcp.main) > 0 ? 1 : 0

  triggers = {
    cluster_id   = one(rhcs_cluster_rosa_hcp.main[*].id)
    cluster_name = var.cluster_name
    role_arn     = aws_iam_role.cloudwatch_audit_logging[0].arn
    # Re-run if the role ARN changes
    role_arn_hash = sha256(aws_iam_role.cloudwatch_audit_logging[0].arn)
  }

  # Configure audit logging
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Configuring CloudWatch audit log forwarding for cluster ${var.cluster_name}..."

      # Check if rosa CLI is installed
      if ! command -v rosa &> /dev/null; then
        echo "ERROR: rosa CLI is not installed. Please install it from: https://console.redhat.com/openshift/downloads"
        exit 1
      fi

      # Check if already logged in, only login if not authenticated
      if ! rosa whoami &> /dev/null; then
        echo "Not logged in to ROSA. Attempting to login..."
        # Login to ROSA if token is available via environment variable
        if [ -n "$${OCM_TOKEN}" ]; then
          rosa login --token="$${OCM_TOKEN}" || {
            echo "ERROR: Failed to login with OCM_TOKEN"
            exit 1
          }
        elif [ -n "$${ROSA_TOKEN}" ]; then
          rosa login --token="$${ROSA_TOKEN}" || {
            echo "ERROR: Failed to login with ROSA_TOKEN"
            exit 1
          }
        else
          echo "ERROR: Not logged in and no token provided. Set OCM_TOKEN or ROSA_TOKEN environment variable."
          exit 1
        fi
      else
        echo "Already logged in to ROSA"
      fi

      # Configure audit log ARN
      rosa edit cluster -c "${var.cluster_name}" --audit-log-arn "${aws_iam_role.cloudwatch_audit_logging[0].arn}" --yes || {
        echo "WARNING: Failed to configure audit logging. Cluster may not be ready yet."
        exit 1
      }

      echo "Successfully configured CloudWatch audit log forwarding"
    EOT
  }

  # Note: No destroy provisioner needed - destroying the cluster automatically removes audit logging configuration

  depends_on = [
    rhcs_cluster_rosa_hcp.main,
    aws_iam_role.cloudwatch_audit_logging,
    aws_iam_role_policy_attachment.cloudwatch_audit_logging
  ]
}

# Note: Using script-based approach until audit_log_arn is available in official provider release.
# Once PR is accepted, we can switch to provider-native implementation using audit_log_arn attribute in 10-main.tf.
