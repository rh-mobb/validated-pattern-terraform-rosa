#!/bin/bash
# scripts/cluster/cleanup-infrastructure.sh
# Cleanup infrastructure (auto-approve, CI/CD friendly)
# Usage: cleanup-infrastructure.sh <cluster-name>

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
    error "  1. Cleanup configuration first: AUTO_APPROVE=true $SCRIPT_DIR/cleanup-configuration.sh $CLUSTER_NAME"
    error "  2. Or use: make cluster.$CLUSTER_NAME.cleanup (cleans up both in correct order)"
    exit 1
fi

info "Configuration state is empty or doesn't exist - safe to destroy infrastructure"

warn "WARNING: This will DESTROY the infrastructure!"
warn "AWS resources (cluster, VPC, IAM roles, etc.) will be deleted."

info "Setting enable_destroy=true and applying to destroy resources..."

cd "$TERRAFORM_INFRA_DIR"

# Calculate relative path from terraform/infrastructure to cluster directory
CLUSTER_TFVARS="$CLUSTER_DIR/terraform.tfvars"

terraform apply \
    -var-file="$CLUSTER_TFVARS" \
    -var="enable_destroy=true" \
    -auto-approve

success "Infrastructure resources have been destroyed"
