#!/usr/bin/env bash
# Run account + network prerequisite validation for a cluster directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../common.sh"

CLUSTER_NAME="${1:-}"
if [[ -z "$CLUSTER_NAME" ]]; then
	error "Usage: $0 <cluster-name>"
	exit 1
fi

CLUSTER_DIR=$(get_cluster_dir "$CLUSTER_NAME")
REGION=$(get_tfvar "$CLUSTER_DIR" "region" "us-east-1")
NETWORK_TYPE=$(get_tfvar "$CLUSTER_DIR" "network_type" "public")
ZERO_EGRESS=$(get_tfvar "$CLUSTER_DIR" "zero_egress" "false")
MULTI_AZ=$(get_tfvar "$CLUSTER_DIR" "multi_az" "true")
VPC_ID=$(get_tfvar "$CLUSTER_DIR" "existing_vpc_id" "")
# Covers: env:CHECK_SUBNET_TAG_CAPACITY
# Does: Reads the cluster's opt-in for the additional tag capacity reads.
# Why: False preserves existing validation until the cluster explicitly enables it.
# Change: A missing file or key uses false; only the parsed true value enables it.
# Trap: This input selects check, never clean, and adds no OCM credential.
# Evidence: Syntax-only: get_tfvar reads the same cluster file used by the other validation inputs.
CHECK_SUBNET_TAG_CAPACITY=$(get_tfvar "$CLUSTER_DIR" "check_subnet_tag_capacity" "false")
CW_LOGS=$(get_tfvar "$CLUSTER_DIR" "control_plane_log_cloudwatch_enabled" "false")

ACCOUNT_ARGS=(--region "$REGION")
NETWORK_ARGS=(--region "$REGION")

if [[ "$ZERO_EGRESS" == "true" ]]; then
	NETWORK_ARGS+=(--zero-egress)
fi
if [[ "$MULTI_AZ" == "true" ]]; then
	NETWORK_ARGS+=(--multi-az)
else
	NETWORK_ARGS+=(--single-az)
fi
if [[ "$CW_LOGS" == "true" ]]; then
	NETWORK_ARGS+=(--require-cloudwatch)
fi

# Covers: --check-subnet-tag-capacity
# Does: Passes the opt-in once to both BYO and Terraform-discovered VPC paths.
# Why: Both network invocations consume the same shared argument array.
# Change: All values other than true leave the additional check disabled.
# Trap: Unreadable tags fail opted-in validation, including transient EC2 failures.
# Evidence: Syntax-only: both invocations below consume NETWORK_ARGS and preserve failure handling.
if [[ "$CHECK_SUBNET_TAG_CAPACITY" == "true" ]]; then
	NETWORK_ARGS+=(--check-subnet-tag-capacity)
fi

info "Validating account prerequisites for cluster: $CLUSTER_NAME (region: $REGION)"
"$SCRIPT_DIR/account.sh" "${ACCOUNT_ARGS[@]}" || ACCOUNT_EXIT=$?
ACCOUNT_EXIT=${ACCOUNT_EXIT:-0}

NETWORK_EXIT=0
if [[ "$NETWORK_TYPE" == "existing" ]]; then
	if [[ -z "$VPC_ID" ]]; then
		error "network_type=existing but existing_vpc_id not set in terraform.tfvars"
		exit 1
	fi
	NETWORK_ARGS+=(--vpc-id "$VPC_ID")
	info "Validating BYO VPC: $VPC_ID"
	"$SCRIPT_DIR/byo-network.sh" "${NETWORK_ARGS[@]}" || NETWORK_EXIT=$?
else
	use_cluster_tf_data_dir "$CLUSTER_NAME"
	TERRAFORM_DIR=$(get_terraform_dir infrastructure)
	if cluster_tf_initialized; then
		TF_VPC=$(cd "$TERRAFORM_DIR" && terraform output -raw vpc_id 2>/dev/null || true)
		if [[ -n "$TF_VPC" && "$TF_VPC" != "null" ]]; then
			info "Validating Terraform-managed VPC: $TF_VPC"
			"$SCRIPT_DIR/byo-network.sh" "${NETWORK_ARGS[@]}" --vpc-id "$TF_VPC" || NETWORK_EXIT=$?
		else
			info "Skipping VPC validation — run after 'make cluster.$CLUSTER_NAME.init' and apply network, or use validate-network with --vpc-id"
			if [[ "$CHECK_SUBNET_TAG_CAPACITY" == "true" ]]; then
				info "Subnet tag capacity: requested, but network validation was skipped (no VPC id resolved) — check did not run"
			fi
		fi
	else
		info "Skipping VPC validation — cluster not initialized (no terraform output yet)"
		if [[ "$CHECK_SUBNET_TAG_CAPACITY" == "true" ]]; then
			info "Subnet tag capacity: requested, but network validation was skipped (no VPC id resolved) — check did not run"
		fi
	fi
fi

if [[ "$ACCOUNT_EXIT" -ne 0 || "$NETWORK_EXIT" -ne 0 ]]; then
	error "Prerequisite validation failed"
	exit 1
fi

success "All prerequisite checks passed for cluster: $CLUSTER_NAME"
