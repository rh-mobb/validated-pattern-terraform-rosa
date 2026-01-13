#!/bin/bash
# scripts/cluster/plan-configuration.sh
# Plan configuration changes
# Usage: plan-configuration.sh <cluster-name>

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

# Ensure initialized
if [ ! -d "$TERRAFORM_CONFIG_DIR/.terraform" ]; then
    info "Not initialized, initializing first..."
    "$SCRIPT_DIR/init-configuration.sh" "$CLUSTER_NAME"
fi

# Check if tunnel is needed (egress-zero clusters)
source "$SCRIPT_DIR/../utils/get-network-config.sh" "$CLUSTER_DIR"

if [ "$NETWORK_TYPE" = "private" ] && [ "$ENABLE_STRICT_EGRESS" = "true" ]; then
    info "Egress-zero cluster detected, checking bastion..."
    cd "$TERRAFORM_INFRA_DIR"
    BASTION_ID=$(terraform output -no-color -raw bastion_instance_id 2>/dev/null | tr -d '\n\r' | sed 's/[[:space:]]*$//' || echo "")
    cd - >/dev/null

    if [ -z "$BASTION_ID" ] || [ "$BASTION_ID" = "null" ]; then
        warn "Egress-zero cluster requires bastion for tunnel access. Bastion not found."
        warn "Set enable_bastion=true in terraform.tfvars and apply infrastructure first."
    else
        info "Starting tunnel for egress-zero cluster..."
        "$SCRIPT_DIR/../tunnel/start.sh" "$CLUSTER_NAME" || warn "Tunnel start failed (continuing anyway)"
    fi
fi

info "Planning configuration..."

# Check infrastructure is deployed
cd "$TERRAFORM_INFRA_DIR"
API_URL=$(terraform output -raw api_url 2>/dev/null || echo "")
cd - >/dev/null

if [ -z "$API_URL" ]; then
    error "Cluster not deployed or api_url output not available"
    error "Apply infrastructure first: $SCRIPT_DIR/apply-infrastructure.sh $CLUSTER_NAME"
    exit 1
fi

info "API URL: $API_URL"

# Get admin password
info "Retrieving admin password from Secrets Manager..."
ADMIN_PASSWORD=$("$PROJECT_ROOT/scripts/utils/get-admin-password.sh" "$TERRAFORM_INFRA_DIR" 2>/dev/null || echo "")

if [ -z "$ADMIN_PASSWORD" ] && [ -z "${TF_VAR_k8s_token:-}" ]; then
    error "Admin password not found and TF_VAR_k8s_token not set"
    error "You may need to:"
    error "  1. Re-apply infrastructure: $SCRIPT_DIR/apply-infrastructure.sh $CLUSTER_NAME"
    error "  2. Or set TF_VAR_k8s_token environment variable"
    exit 1
fi

# Get Kubernetes token
if [ -z "${TF_VAR_k8s_token:-}" ]; then
    info "Obtaining Kubernetes token..."
    K8S_TOKEN=$("$PROJECT_ROOT/scripts/utils/get-k8s-token.sh" "$API_URL" "$ADMIN_PASSWORD" | tr -d '\n\r' | sed 's/[[:space:]]*$//')
    export TF_VAR_k8s_token="$K8S_TOKEN"
else
    info "Using TF_VAR_k8s_token from environment"
    # Trim existing token to ensure no whitespace
    export TF_VAR_k8s_token=$(echo "${TF_VAR_k8s_token}" | tr -d '\n\r' | sed 's/[[:space:]]*$//')
fi

# Extract infrastructure outputs
info "Extracting infrastructure outputs..."
source "$PROJECT_ROOT/scripts/utils/get-infra-outputs.sh" "$CLUSTER_NAME"

# Run terraform plan
info "Running Terraform plan in $TERRAFORM_CONFIG_DIR..."

cd "$TERRAFORM_CONFIG_DIR"

CLUSTER_TFVARS="$CLUSTER_DIR/terraform.tfvars"
CLUSTER_CONFIG_TFVARS="$CLUSTER_DIR/configuration.tfvars"

# Ensure token is exported
export TF_VAR_k8s_token

# Verify token is set
if [ -z "${TF_VAR_k8s_token:-}" ]; then
    error "TF_VAR_k8s_token is not set - cannot create plan"
    exit 1
fi

# Pass token explicitly via -var to ensure it's used

if [ -f "$CLUSTER_CONFIG_TFVARS" ]; then
    info "Using configuration.tfvars file..."
    terraform plan \
        -var="k8s_token=${TF_VAR_k8s_token}" \
        -var-file="$CLUSTER_TFVARS" \
        -var-file="$CLUSTER_CONFIG_TFVARS" \
        -out=terraform.tfplan
else
    terraform plan \
        -var="k8s_token=${TF_VAR_k8s_token}" \
        -var-file="$CLUSTER_TFVARS" \
        -out=terraform.tfplan
fi

success "Configuration plan created: terraform.tfplan"
