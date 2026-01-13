#!/bin/bash
# scripts/cluster/init-configuration.sh
# Initialize configuration Terraform backend
# Usage: init-configuration.sh <cluster-name>

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
TERRAFORM_CONFIG_DIR=$(get_terraform_dir configuration)

info "Initializing configuration..."

cd "$TERRAFORM_CONFIG_DIR"

# Setup backend config
if check_backend_config; then
    # Remote backend (S3)
    # Use -migrate-state if .terraform exists, otherwise -reconfigure
    if [ -d ".terraform" ]; then
        terraform init -migrate-state -input=false \
            -backend-config="bucket=${TF_BACKEND_CONFIG_BUCKET}" \
            -backend-config="key=clusters/${CLUSTER_NAME}/configuration.tfstate" \
            -backend-config="region=${TF_BACKEND_CONFIG_REGION:-us-east-1}" \
            $(if [ -n "${TF_BACKEND_CONFIG_DYNAMODB_TABLE:-}" ]; then echo "-backend-config=dynamodb_table=${TF_BACKEND_CONFIG_DYNAMODB_TABLE}"; fi) \
            -backend-config="encrypt=true"
    else
        terraform init -reconfigure -input=false \
            -backend-config="bucket=${TF_BACKEND_CONFIG_BUCKET}" \
            -backend-config="key=clusters/${CLUSTER_NAME}/configuration.tfstate" \
            -backend-config="region=${TF_BACKEND_CONFIG_REGION:-us-east-1}" \
            $(if [ -n "${TF_BACKEND_CONFIG_DYNAMODB_TABLE:-}" ]; then echo "-backend-config=dynamodb_table=${TF_BACKEND_CONFIG_DYNAMODB_TABLE}"; fi) \
            -backend-config="encrypt=true"
    fi
else
    # Local backend
    # Use -migrate-state if .terraform exists, otherwise -reconfigure
    if [ -d ".terraform" ]; then
        terraform init -migrate-state -input=false \
            -backend-config="path=../../${CLUSTER_DIR}/configuration.tfstate"
    else
        terraform init -reconfigure -input=false \
            -backend-config="path=../../${CLUSTER_DIR}/configuration.tfstate"
    fi
fi

success "Configuration initialized successfully"
