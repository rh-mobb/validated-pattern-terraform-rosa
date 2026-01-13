#!/bin/bash
# scripts/cluster/generate-config-tfvars.sh
# Generate configuration.tfvars from infrastructure outputs
# Usage: generate-config-tfvars.sh <cluster-name>

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

info "Generating configuration.tfvars from infrastructure outputs..."

cd "$TERRAFORM_INFRA_DIR"

# Extract outputs
API_URL=$(terraform output -raw api_url 2>/dev/null || echo "")
CLUSTER_ID=$(terraform output -raw cluster_id 2>/dev/null || echo "")
CLUSTER_NAME_OUT=$(terraform output -raw cluster_name 2>/dev/null || echo "")
CONSOLE_URL=$(terraform output -raw console_url 2>/dev/null || echo "")
ADMIN_USER_CREATED=$(terraform output -raw admin_user_created 2>/dev/null || echo "false")
BASTION_DEPLOYED=$(terraform output -raw bastion_deployed 2>/dev/null || echo "false")
BASTION_ID=$(terraform output -raw bastion_instance_id 2>/dev/null || echo "")
BASTION_SSM=$(terraform output -raw bastion_ssm_command 2>/dev/null || echo "")
BASTION_SSHUTTLE=$(terraform output -raw bastion_sshuttle_command 2>/dev/null || echo "")

# Generate tfvars file
{
    echo "# Auto-generated from infrastructure outputs"
    echo "# Do not edit manually - regenerated on each infrastructure apply"
    echo "# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo "api_url = \"$API_URL\""
    echo "cluster_id = \"$CLUSTER_ID\""
    echo "cluster_name = \"$CLUSTER_NAME_OUT\""
    echo "console_url = \"$CONSOLE_URL\""
    echo "admin_user_created = $ADMIN_USER_CREATED"
    echo "bastion_deployed = $BASTION_DEPLOYED"

    if [ "$BASTION_ID" != "null" ] && [ -n "$BASTION_ID" ]; then
        echo "bastion_instance_id = \"$BASTION_ID\""
    else
        echo "bastion_instance_id = null"
    fi

    if [ "$BASTION_SSM" != "null" ] && [ -n "$BASTION_SSM" ]; then
        echo "bastion_ssm_command = \"$BASTION_SSM\""
    else
        echo "bastion_ssm_command = null"
    fi

    if [ "$BASTION_SSHUTTLE" != "null" ] && [ -n "$BASTION_SSHUTTLE" ]; then
        echo "bastion_sshuttle_command = \"$BASTION_SSHUTTLE\""
    else
        echo "bastion_sshuttle_command = null"
    fi
} > "../../$CLUSTER_DIR/configuration.tfvars"

success "Generated $CLUSTER_DIR/configuration.tfvars"
