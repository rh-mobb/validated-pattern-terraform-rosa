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

info "Destroying infrastructure..."

cd "$TERRAFORM_INFRA_DIR"

# Calculate relative path from terraform to cluster directory
CLUSTER_TFVARS="$CLUSTER_DIR/terraform.tfvars"

terraform destroy \
    -var-file="$CLUSTER_TFVARS" \
    -auto-approve

success "Infrastructure destroyed successfully"
