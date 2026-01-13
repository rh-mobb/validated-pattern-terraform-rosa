#!/bin/bash
# scripts/cluster/destroy-infrastructure.sh
# Destroy infrastructure (with confirmation)
# Usage: destroy-infrastructure.sh <cluster-name>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../common.sh"

CLUSTER_NAME="${1:-}"
if [ -z "$CLUSTER_NAME" ]; then
    error "Usage: $0 <cluster-name>"
    exit 1
fi

CLUSTER_DIR=$(get_cluster_dir "$CLUSTER_NAME")
TERRAFORM_INFRA_DIR=$(get_terraform_dir infrastructure)
TERRAFORM_CONFIG_DIR=$(get_terraform_dir configuration)

# Check if configuration state has resources
info "Checking configuration state..."
if ! check_configuration_state_empty "$CLUSTER_NAME" "$TERRAFORM_CONFIG_DIR" "$CLUSTER_DIR"; then
    error "Configuration state still contains resources!"
    error "Configuration must be destroyed before infrastructure can be destroyed."
    error ""
    error "This is a safety check because configuration may create resources"
    error "external to the cluster (e.g., GitOps operators, external services)."
    error ""
    error "To proceed:"
    error "  1. Destroy configuration first: $SCRIPT_DIR/destroy-configuration.sh $CLUSTER_NAME"
    error "  2. Or use: make cluster.$CLUSTER_NAME.destroy (destroys both in correct order)"
    exit 1
fi

info "Configuration state is empty or doesn't exist - safe to destroy infrastructure"

warn "WARNING: This will destroy the infrastructure!"
warn "AWS resources (cluster, VPC, IAM roles, etc.) will be deleted."

# Prompt for confirmation unless AUTO_APPROVE is set
if [ "${AUTO_APPROVE:-}" != "true" ]; then
    echo -n "Are you sure you want to continue? (yes/no): "
    read -r confirmation
    if [ "$confirmation" != "yes" ]; then
        info "Destroy cancelled"
        exit 0
    fi
fi

info "Setting enable_destroy=true and applying to destroy resources..."

cd "$TERRAFORM_INFRA_DIR"

# Calculate relative path from terraform/infrastructure to cluster directory
CLUSTER_TFVARS="$CLUSTER_DIR/terraform.tfvars"

terraform apply \
    -var-file="$CLUSTER_TFVARS" \
    -var="enable_destroy=true" \
    -auto-approve

success "Infrastructure destroyed successfully"
