#!/bin/bash
# scripts/cluster/cleanup-configuration.sh
# Cleanup configuration (auto-approve, CI/CD friendly)
# Usage: cleanup-configuration.sh <cluster-name>

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

# Check if tunnel is needed (egress-zero clusters)
source "$SCRIPT_DIR/../utils/get-network-config.sh" "$CLUSTER_DIR"

if [ "$NETWORK_TYPE" = "private" ] && [ "$ENABLE_STRICT_EGRESS" = "true" ]; then
    info "Egress-zero cluster detected, starting tunnel..."
    "$SCRIPT_DIR/../tunnel/start.sh" "$CLUSTER_NAME" || warn "Tunnel start failed (continuing anyway)"
fi

warn "WARNING: This will DESTROY the configuration!"
warn "Kubernetes resources (GitOps operator) will be deleted from the cluster."

# Check if cluster is accessible
cd "$TERRAFORM_INFRA_DIR"
API_URL=$(terraform output -raw api_url 2>&1 | grep -E "^https?://" | head -1 || echo "")
cd - >/dev/null

if [ -z "$API_URL" ]; then
    warn "Warning: Cluster not deployed or api_url output not available."
    warn "Skipping configuration cleanup (infrastructure may already be destroyed)."
    exit 0
fi

# Get admin password
info "Retrieving admin password from Secrets Manager..."
ADMIN_PASSWORD=$("$PROJECT_ROOT/scripts/utils/get-admin-password.sh" "$TERRAFORM_INFRA_DIR" || echo "")

if [ -z "$ADMIN_PASSWORD" ] && [ -z "${TF_VAR_k8s_token:-}" ]; then
    warn "Warning: Cannot retrieve admin password and TF_VAR_k8s_token not set."
    warn "Configuration may already be destroyed. Skipping configuration cleanup."
    exit 0
fi

# Get Kubernetes token if cluster is accessible
if [ -n "$API_URL" ]; then
    if [ -z "${TF_VAR_k8s_token:-}" ] && [ -n "$ADMIN_PASSWORD" ]; then
        info "Obtaining Kubernetes token..."
        K8S_TOKEN=$("$PROJECT_ROOT/scripts/utils/get-k8s-token.sh" "$API_URL" "$ADMIN_PASSWORD" | tr -d '\n\r' | sed 's/[[:space:]]*$//' || echo "")
        if [ -n "$K8S_TOKEN" ]; then
            export TF_VAR_k8s_token="$K8S_TOKEN"
        fi
    else
        # Trim existing token to ensure no whitespace
        if [ -n "${TF_VAR_k8s_token:-}" ]; then
            export TF_VAR_k8s_token=$(echo "${TF_VAR_k8s_token}" | tr -d '\n\r' | sed 's/[[:space:]]*$//')
        fi
    fi

    # Extract infrastructure outputs (required for configuration variables)
    info "Extracting infrastructure outputs..."
    source "$PROJECT_ROOT/scripts/utils/get-infra-outputs.sh" "$CLUSTER_NAME" || warn "Failed to extract some infrastructure outputs (continuing anyway)"

    if [ -n "${TF_VAR_k8s_token:-}" ]; then
        cd "$TERRAFORM_CONFIG_DIR"
        CLUSTER_TFVARS="$CLUSTER_DIR/terraform.tfvars"
        CLUSTER_CONFIG_TFVARS="$CLUSTER_DIR/configuration.tfvars"
        info "Setting enable_destroy=true and applying to destroy resources..."

        if [ -f "$CLUSTER_CONFIG_TFVARS" ]; then
            terraform apply \
                -var="k8s_token=${TF_VAR_k8s_token}" \
                -var="enable_destroy=true" \
                -var-file="$CLUSTER_TFVARS" \
                -var-file="$CLUSTER_CONFIG_TFVARS" \
                -auto-approve
        else
            terraform apply \
                -var="k8s_token=${TF_VAR_k8s_token}" \
                -var="enable_destroy=true" \
                -var-file="$CLUSTER_TFVARS" \
                -auto-approve
        fi
        success "Configuration resources have been destroyed."
    else
        warn "Skipping Kubernetes authentication (cluster not available)."
        cd "$TERRAFORM_CONFIG_DIR"
        CLUSTER_TFVARS="$CLUSTER_DIR/terraform.tfvars"
        CLUSTER_CONFIG_TFVARS="$CLUSTER_DIR/configuration.tfvars"
        warn "Setting enable_destroy=true and applying to remove resources from state..."

        if [ -f "$CLUSTER_CONFIG_TFVARS" ]; then
            terraform apply \
                -var="enable_destroy=true" \
                -var-file="$CLUSTER_TFVARS" \
                -var-file="$CLUSTER_CONFIG_TFVARS" \
                -auto-approve || (warn "Configuration cleanup skipped (cluster not accessible)" && exit 0)
        else
            terraform apply \
                -var="enable_destroy=true" \
                -var-file="$CLUSTER_TFVARS" \
                -auto-approve || (warn "Configuration cleanup skipped (cluster not accessible)" && exit 0)
        fi
    fi
else
    # Try to extract infrastructure outputs even if API_URL is not available
    info "Extracting infrastructure outputs..."
    source "$PROJECT_ROOT/scripts/utils/get-infra-outputs.sh" "$CLUSTER_NAME" || warn "Failed to extract infrastructure outputs (continuing anyway)"

    warn "Skipping Kubernetes authentication (cluster not available)."
    cd "$TERRAFORM_CONFIG_DIR"
    CLUSTER_TFVARS="$CLUSTER_DIR/terraform.tfvars"
    CLUSTER_CONFIG_TFVARS="$CLUSTER_DIR/configuration.tfvars"
    warn "Setting enable_destroy=true and applying to remove resources from state..."

    if [ -f "$CLUSTER_CONFIG_TFVARS" ]; then
        terraform apply \
            -var="enable_destroy=true" \
            -var-file="$CLUSTER_TFVARS" \
            -var-file="$CLUSTER_CONFIG_TFVARS" \
            -auto-approve || (warn "Configuration cleanup skipped (cluster not accessible)" && exit 0)
    else
        terraform apply \
            -var="enable_destroy=true" \
            -var-file="$CLUSTER_TFVARS" \
            -auto-approve || (warn "Configuration cleanup skipped (cluster not accessible)" && exit 0)
    fi
fi

success "Configuration cleanup completed"
