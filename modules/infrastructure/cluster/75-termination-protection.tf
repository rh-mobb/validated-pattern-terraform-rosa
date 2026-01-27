# Cluster Termination Protection
# Reference: ./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/13.termination-protection.tf
# This resource enables/disables cluster termination protection using the ROSA CLI
# Termination protection prevents accidental cluster deletion

# Script path is defined in 10-main.tf as termination_protection_script_path

# Enable/Disable Termination Protection using ROSA CLI
# Reference: ./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/13.termination-protection.tf
resource "shell_script" "termination_protection" {
  count = local.persists_through_sleep && var.enable_termination_protection ? 1 : 0

  lifecycle_commands {
    create = <<-EOT
      export CLUSTER_NAME='${var.cluster_name}'
      export ENABLE='true'
      "${local.termination_protection_script_path}"
    EOT
    delete = <<-EOT
      export CLUSTER_NAME='${var.cluster_name}'
      export ENABLE='false'
      "${local.termination_protection_script_path}"
    EOT
    read   = <<-EOT
      # Check current termination protection status
      rosa describe cluster -c '${var.cluster_name}' --output json 2>/dev/null | jq -r '.delete_protection.enabled // false' || echo "false"
    EOT
    update = <<-EOT
      export CLUSTER_NAME='${var.cluster_name}'
      export ENABLE='true'
      "${local.termination_protection_script_path}"
    EOT
  }

  environment = {}

  depends_on = [
    rhcs_cluster_rosa_hcp.main
  ]
}
