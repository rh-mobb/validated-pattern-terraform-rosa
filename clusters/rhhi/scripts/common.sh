#!/bin/bash
# clusters/rhhi/scripts/common.sh — shared helpers for RHHI supply chain scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RHHI_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${RHHI_DIR}/../.." && pwd)"
TERRAFORM_DIR="${REPO_ROOT}/terraform"
HELM_CHART_DIR="${RHHI_DIR}/helm/rhhi-supply-chain"
# Used by render-values.sh and install.sh after sourcing this file.
# shellcheck disable=SC2034
VALUES_GENERATED="${HELM_CHART_DIR}/values.generated.yaml"

if [[ -f "${RHHI_DIR}/config.env" ]]; then
	# shellcheck disable=SC1091
	source "${RHHI_DIR}/config.env"
fi

CLUSTER_DIR="${CLUSTER_DIR:-rhhi}"
CLUSTER_NAME="${CLUSTER_NAME:-rhhi}"
TEKTON_NAMESPACE="${TEKTON_NAMESPACE:-user-workload-pipeline}"
ECR_OPERATOR_NAMESPACE="${ECR_OPERATOR_NAMESPACE:-ecr-secret-operator}"

log() { printf '[rhhi] %s\n' "$*"; }
die() {
	printf '[rhhi] ERROR: %s\n' "$*" >&2
	exit 1
}

require_cmd() {
	local cmd="$1"
	command -v "${cmd}" >/dev/null 2>&1 || die "Required command not found: ${cmd}"
}

load_terraform_outputs() {
	require_cmd terraform
	require_cmd jq
	(
		cd "${TERRAFORM_DIR}"
		terraform output -json rhhi_supply_chain 2>/dev/null
	) || die "rhhi_supply_chain output not found — run 'make cluster.${CLUSTER_DIR}.apply' with enable_rhhi_supply_chain=true"
}
