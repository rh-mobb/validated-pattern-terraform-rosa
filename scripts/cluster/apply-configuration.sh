#!/bin/bash
# scripts/cluster/apply-configuration.sh
# Apply configuration changes
# Usage: apply-configuration.sh <cluster-name>

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

# Always regenerate plan to ensure fresh token (token is ephemeral and shouldn't be in plan anyway)
# But check if plan exists and is recent (< 5 minutes old) to avoid unnecessary replanning
if [ -f "$TERRAFORM_CONFIG_DIR/terraform.tfplan" ]; then
    PLAN_AGE=$(($(date +%s) - $(stat -f %m "$TERRAFORM_CONFIG_DIR/terraform.tfplan" 2>/dev/null || echo 0)))
    if [ $PLAN_AGE -gt 300 ]; then
        info "Plan is older than 5 minutes, regenerating to ensure fresh token..."
        "$SCRIPT_DIR/plan-configuration.sh" "$CLUSTER_NAME"
    else
        info "Using existing plan (less than 5 minutes old)"
    fi
else
    info "Plan not found, planning first..."
    "$SCRIPT_DIR/plan-configuration.sh" "$CLUSTER_NAME"
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

info "Applying configuration..."

# Get API URL and admin password for token refresh
cd "$TERRAFORM_INFRA_DIR"
API_URL=$(terraform output -raw api_url 2>/dev/null || echo "")
cd - >/dev/null

if [ -n "$API_URL" ]; then
# Get admin password
ADMIN_PASSWORD=$("$PROJECT_ROOT/scripts/utils/get-admin-password.sh" "$TERRAFORM_INFRA_DIR" 2>/dev/null || echo "")

    # Get Kubernetes token if not already set
    if [ -z "${TF_VAR_k8s_token:-}" ] && [ -n "$ADMIN_PASSWORD" ]; then
        info "Obtaining Kubernetes token..."
        K8S_TOKEN=$("$PROJECT_ROOT/scripts/utils/get-k8s-token.sh" "$API_URL" "$ADMIN_PASSWORD" | tr -d '\n\r' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        export TF_VAR_k8s_token="$K8S_TOKEN"

        if [ -z "$K8S_TOKEN" ]; then
            error "Failed to obtain Kubernetes token"
            exit 1
        fi
    else
        # Trim existing token to ensure no whitespace
        if [ -n "${TF_VAR_k8s_token:-}" ]; then
            export TF_VAR_k8s_token=$(echo "${TF_VAR_k8s_token}" | tr -d '\n\r' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        else
            error "No Kubernetes token available"
            exit 1
        fi
    fi

    # Verify token is set
    if [ -z "${TF_VAR_k8s_token:-}" ]; then
        error "Kubernetes token is empty after processing"
        exit 1
    fi
fi

# Extract infrastructure outputs
info "Extracting infrastructure outputs..."
source "$PROJECT_ROOT/scripts/utils/get-infra-outputs.sh" "$CLUSTER_NAME"

# Run terraform apply
info "Running Terraform apply in $TERRAFORM_CONFIG_DIR..."

cd "$TERRAFORM_CONFIG_DIR"

# Verify token is available
if [ -z "${TF_VAR_k8s_token:-}" ]; then
    error "TF_VAR_k8s_token is empty! Cannot proceed."
    exit 1
fi

# Export to ensure it's available to Terraform
export TF_VAR_k8s_token

CLUSTER_TFVARS="$CLUSTER_DIR/terraform.tfvars"
CLUSTER_CONFIG_TFVARS="$CLUSTER_DIR/configuration.tfvars"

# Pass token explicitly via -var to ensure it's used even with plan files
# The k8s_token variable is marked ephemeral, so it won't be in the plan file
if [ -f "$CLUSTER_CONFIG_TFVARS" ]; then
    info "Using configuration.tfvars file..."
    terraform apply \
        -var="k8s_token=${TF_VAR_k8s_token}" \
        -var-file="$CLUSTER_TFVARS" \
        -var-file="$CLUSTER_CONFIG_TFVARS" \
        terraform.tfplan
else
    terraform apply \
        -var="k8s_token=${TF_VAR_k8s_token}" \
        terraform.tfplan
fi

success "Configuration applied successfully"
