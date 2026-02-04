# Control Plane Log Forwarding Configuration
# Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/security_and_compliance/rosa-forwarding-control-plane-logs
# This configuration configures the cluster to forward control plane logs using ROSA's managed log forwarder.
# The IAM role and policies are created in the IAM module.
# CloudWatch log group and S3 bucket are created in this module (22-control-plane-log-forwarding-resources.tf).
#
# NOTE: The IAM role ARN is provided via control_plane_log_forwarding_role_arn variable (from IAM module output)

# Generate log forwarder YAML configuration
locals {
  # Convert log group names to lowercase (ROSA CLI requires lowercase despite documentation showing capitalized)
  # Workaround for bug: Documentation shows "API", "Authentication", etc. but CLI expects "api", "authentication", etc.
  normalized_log_groups = [
    for group in var.control_plane_log_groups : lower(group)
  ]

  # Build CloudWatch configuration if enabled
  cloudwatch_config = var.control_plane_log_cloudwatch_enabled && var.control_plane_log_forwarding_role_arn != null ? {
    cloudwatch_log_role_arn    = var.control_plane_log_forwarding_role_arn
    cloudwatch_log_group_name  = var.control_plane_log_cloudwatch_log_group_name != null ? var.control_plane_log_cloudwatch_log_group_name : "${var.cluster_name}-control-plane-logs"
    applications               = length(var.control_plane_log_applications) > 0 ? var.control_plane_log_applications : null
    groups                     = local.normalized_log_groups
  } : null

  # Build S3 configuration if enabled
  # Reference the bucket resource from 22-control-plane-log-forwarding-resources.tf
  # The bucket resource will have either the provided name or a generated name with random suffix
  s3_config = var.control_plane_log_s3_enabled && length(aws_s3_bucket.control_plane_logs) > 0 ? {
    s3_config_bucket_name   = aws_s3_bucket.control_plane_logs[0].id
    s3_config_bucket_prefix = var.control_plane_log_s3_bucket_prefix != null ? var.control_plane_log_s3_bucket_prefix : null
    applications            = length(var.control_plane_log_applications) > 0 ? var.control_plane_log_applications : null
    groups                  = local.normalized_log_groups
  } : null

  # Build complete log forwarder configuration
  log_forwarder_config = {
    cloudwatch = local.cloudwatch_config
    s3         = local.s3_config
  }

  # Convert to YAML (remove null values)
  log_forwarder_yaml = yamlencode({
    for key, value in local.log_forwarder_config : key => value
    if value != null
  })
}

# Write YAML configuration to temporary file
resource "local_file" "log_forwarder_config" {
  count = local.persists_through_sleep && var.enable_control_plane_log_forwarding ? 1 : 0

  content  = local.log_forwarder_yaml
  filename = "${path.module}/.terraform/log-forwarder-${var.cluster_name}.yaml"

  # Ensure directory exists
  directory_permission = "0755"
  file_permission      = "0644"
}

# Configure log forwarder on the cluster using ROSA CLI
resource "null_resource" "configure_control_plane_log_forwarding" {
  count = local.persists_through_sleep && var.enable_control_plane_log_forwarding ? 1 : 0

  triggers = {
    cluster_id   = one(rhcs_cluster_rosa_hcp.main[*].id)
    cluster_name = var.cluster_name
    # Re-run if configuration changes
    role_arn                    = try(var.control_plane_log_forwarding_role_arn, "")
    cloudwatch_enabled         = var.control_plane_log_cloudwatch_enabled
    cloudwatch_log_group_name  = var.control_plane_log_cloudwatch_log_group_name != null ? var.control_plane_log_cloudwatch_log_group_name : "${var.cluster_name}-control-plane-logs"
    s3_enabled                 = var.control_plane_log_s3_enabled
    s3_bucket_name            = length(aws_s3_bucket.control_plane_logs) > 0 ? aws_s3_bucket.control_plane_logs[0].id : ""
    s3_bucket_prefix          = try(var.control_plane_log_s3_bucket_prefix, "")
    log_groups                = join(",", var.control_plane_log_groups)
    log_applications          = join(",", var.control_plane_log_applications)
    config_hash               = sha256(local.log_forwarder_yaml)
  }

  # Configure log forwarder
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Configuring control plane log forwarding for cluster ${var.cluster_name}..."

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

      # Check if role ARN is available
      if [ -z "${var.control_plane_log_forwarding_role_arn}" ] || [ "${var.control_plane_log_forwarding_role_arn}" = "null" ]; then
        echo "ERROR: control_plane_log_forwarding_role_arn is not set. IAM role may not be created yet."
        exit 1
      fi

      # Check if at least one destination is enabled
      if [ "${var.control_plane_log_cloudwatch_enabled}" != "true" ] && [ "${var.control_plane_log_s3_enabled}" != "true" ]; then
        echo "ERROR: At least one destination (CloudWatch or S3) must be enabled."
        exit 1
      fi

      # S3 bucket name is auto-generated if not provided, so no need to check

      # Check if log forwarder already exists
      # Workaround for ROSA CLI bug: rosa create log-forwarder doesn't support -o json output,
      # so we must use rosa list log-forwarder to get the ID after creation. Since only one
      # config per type (cloudwatch/s3) is allowed, we can safely use the first result.
      LOG_FORWARDER_ID=$(rosa list log-forwarder -c "${var.cluster_name}" --output json 2>/dev/null | jq -r '.[0].id // empty' || echo "")

      if [ -n "$${LOG_FORWARDER_ID}" ]; then
        echo "Log forwarder already exists (ID: $${LOG_FORWARDER_ID}). Updating..."
        rosa edit log-forwarder -c "${var.cluster_name}" "$${LOG_FORWARDER_ID}" --log-fwd-config="${local_file.log_forwarder_config[0].filename}" || {
          echo "WARNING: Failed to update log forwarder. Cluster may not be ready yet."
          exit 1
        }
        echo "Successfully updated control plane log forwarder"
      else
        echo "Creating new log forwarder..."
        rosa create log-forwarder -c "${var.cluster_name}" --log-fwd-config="${local_file.log_forwarder_config[0].filename}" || {
          echo "WARNING: Failed to create log forwarder. Cluster may not be ready yet."
          exit 1
        }
        echo "Successfully created control plane log forwarder"
      fi
    EOT
  }

  # Cleanup: Delete log forwarder when resource is destroyed
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e
      echo "Deleting control plane log forwarder for cluster ${self.triggers.cluster_name}..."

      # Check if rosa CLI is installed
      if ! command -v rosa &> /dev/null; then
        echo "WARNING: rosa CLI is not installed. Skipping log forwarder deletion."
        exit 0
      fi

      # Check if already logged in
      if ! rosa whoami &> /dev/null; then
        echo "WARNING: Not logged in to ROSA. Skipping log forwarder deletion."
        exit 0
      fi

      # Get log forwarder ID
      LOG_FORWARDER_ID=$(rosa list log-forwarder -c "${self.triggers.cluster_name}" --output json 2>/dev/null | jq -r '.[0].id // empty' || echo "")

      if [ -n "$${LOG_FORWARDER_ID}" ]; then
        rosa delete log-forwarder -c "${self.triggers.cluster_name}" "$${LOG_FORWARDER_ID}" --yes || {
          echo "WARNING: Failed to delete log forwarder. It may have already been deleted."
        }
        echo "Successfully deleted control plane log forwarder"
      else
        echo "No log forwarder found to delete"
      fi
    EOT
  }

  depends_on = [
    rhcs_cluster_rosa_hcp.main,
    local_file.log_forwarder_config,
    aws_s3_bucket.control_plane_logs
  ]
}
