#!/bin/bash
# scripts/cluster/run-gitops-bootstrap.sh
# Prepare Terraform outputs and run the GitOps bootstrap script (hub mode).
# Usage: run-gitops-bootstrap.sh <cluster-name>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../common.sh"

CLUSTER_NAME="${1:-}"
if [ -z "$CLUSTER_NAME" ]; then
	error "Usage: $0 <cluster-name>"
	exit 1
fi

CLUSTER_DIR=$(get_cluster_dir "$CLUSTER_NAME")
TERRAFORM_DIR=$(get_terraform_dir infrastructure)

cd "$TERRAFORM_DIR"

if ! terraform output -no-color gitops_bootstrap_enabled 2>/dev/null | grep -q "true"; then
	warn "GitOps bootstrap is not enabled for this cluster."
	warn "Set enable_gitops_bootstrap=true in terraform.tfvars and run terraform apply."
	exit 1
fi

SCRIPT_PATH=$(terraform output -no-color -raw gitops_bootstrap_script_path 2>/dev/null | tr -d '\n\r' | sed 's/[[:space:]]*$//')
if [ -z "$SCRIPT_PATH" ] || [ "$SCRIPT_PATH" = "null" ]; then
	error "GitOps bootstrap script path not found. Run terraform apply first."
	exit 1
fi

# Terraform outputs a path relative to the terraform/ working directory
# (e.g. ./../scripts/cluster/bootstrap-gitops.sh). Resolve from there.
if [[ "$SCRIPT_PATH" != /* ]]; then
	SCRIPT_PATH="$(cd "$TERRAFORM_DIR" && cd "$(dirname "$SCRIPT_PATH")" && pwd)/$(basename "$SCRIPT_PATH")"
fi
if [ ! -f "$SCRIPT_PATH" ]; then
	error "GitOps bootstrap script not found: $SCRIPT_PATH"
	exit 1
fi

ACM_MODE=$(terraform output -no-color -raw gitops_bootstrap_acm_mode 2>/dev/null | tr -d '\n\r' || true)
if [ "$ACM_MODE" = "spoke" ]; then
	VALUES_OUTPUT="gitops_bootstrap_spoke_values"
else
	VALUES_OUTPUT="gitops_bootstrap_hub_values"
fi

info "Writing Helm values to clusters/${CLUSTER_NAME}/cluster-bootstrap-values.yaml..."
mkdir -p "$CLUSTER_DIR"
terraform output -no-color -raw "$VALUES_OUTPUT" >"$CLUSTER_DIR/cluster-bootstrap-values.yaml"
export BOOTSTRAP_VALUES_FILE="$CLUSTER_DIR/cluster-bootstrap-values.yaml"

info "Exporting environment variables from Terraform outputs..."
# shellcheck disable=SC2046
eval $(terraform output -no-color -raw gitops_bootstrap_env_exports 2>/dev/null)

info "Running GitOps bootstrap script: $SCRIPT_PATH"
bash "$SCRIPT_PATH"
success "GitOps bootstrap completed for ${CLUSTER_NAME}"
