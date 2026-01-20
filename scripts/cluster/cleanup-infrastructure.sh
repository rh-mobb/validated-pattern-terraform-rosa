#!/bin/bash
# scripts/cluster/cleanup-infrastructure.sh
# Sleep infrastructure (destroy with preserved resources, auto-approve, CI/CD friendly)
# This script destroys cluster resources while preserving DNS, admin password, IAM, etc.
# Used by "make sleep" target to temporarily shut down clusters for cost savings.
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

warn "WARNING: This will DESTROY the infrastructure!"
warn "AWS resources (cluster, VPC, IAM roles, etc.) will be deleted."

info "Setting persists_through_sleep=false and applying to sleep cluster..."

cd "$TERRAFORM_INFRA_DIR"

# Calculate relative path from terraform to cluster directory
CLUSTER_TFVARS="$CLUSTER_DIR/terraform.tfvars"

terraform apply \
    -var-file="$CLUSTER_TFVARS" \
    -var="persists_through_sleep=false" \
    -auto-approve

success "Infrastructure resources have been destroyed"
