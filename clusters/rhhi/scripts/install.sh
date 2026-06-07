#!/bin/bash
# clusters/rhhi/scripts/install.sh — helm upgrade --install RHHI supply chain chart

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

"${SCRIPT_DIR}/render-values.sh"

RELEASE_NAME="rhhi-supply-chain"
INSTALL_NS="${TEKTON_NAMESPACE}"
HELM_ARGS=(
	-f "${HELM_CHART_DIR}/values.yaml"
	-f "${VALUES_GENERATED}"
	-n "${INSTALL_NS}"
	--create-namespace
)

require_cmd helm
require_cmd oc

wait_for_csv() {
	local ns="$1"
	local pattern="$2"
	local timeout="${3:-600}"
	log "Waiting for CSV matching '${pattern}' in ${ns} (timeout ${timeout}s)..."
	local elapsed=0
	while [[ ${elapsed} -lt ${timeout} ]]; do
		if oc get csv -n "${ns}" 2>/dev/null | grep -qi "${pattern}"; then
			if oc get csv -n "${ns}" -o json | jq -e --arg p "${pattern}" '.items[] | select(.metadata.name | test($p;"i")) | select(.status.phase=="Succeeded")' >/dev/null 2>&1; then
				log "  CSV ready: ${pattern}"
				return 0
			fi
		fi
		sleep 10
		elapsed=$((elapsed + 10))
	done
	die "Timed out waiting for CSV: ${pattern} in ${ns}"
}

wait_for_crd() {
	local crd="$1"
	local timeout="${2:-300}"
	log "Waiting for CRD ${crd} (timeout ${timeout}s)..."
	local elapsed=0
	while [[ ${elapsed} -lt ${timeout} ]]; do
		if oc get crd "${crd}" >/dev/null 2>&1; then
			log "  CRD ready: ${crd}"
			return 0
		fi
		sleep 5
		elapsed=$((elapsed + 5))
	done
	die "Timed out waiting for CRD: ${crd}"
}

wait_for_deployment() {
	local ns="$1"
	local name="$2"
	local timeout="${3:-600}"
	log "Waiting for deployment ${ns}/${name} (timeout ${timeout}s)..."
	if ! oc wait --for=condition=Available "deployment/${name}" -n "${ns}" --timeout="${timeout}s"; then
		die "Timed out waiting for deployment: ${ns}/${name}"
	fi
	log "  Deployment ready: ${ns}/${name}"
}

log "Phase 1: Installing operators (supplyChain.enabled=false)..."
helm upgrade --install "${RELEASE_NAME}" "${HELM_CHART_DIR}" \
	"${HELM_ARGS[@]}" \
	--set supplyChain.enabled=false \
	--wait \
	--timeout 5m

if helm template "${RELEASE_NAME}" "${HELM_CHART_DIR}" -f "${HELM_CHART_DIR}/values.yaml" -f "${VALUES_GENERATED}" | grep -q "openshift-pipelines-operator-rh"; then
	wait_for_csv "openshift-operators" "openshift-pipelines-operator" 900
	wait_for_crd "pipelines.tekton.dev" 300
	wait_for_crd "tasks.tekton.dev" 300
	wait_for_deployment "openshift-pipelines" "tekton-pipelines-webhook" 600
	wait_for_deployment "openshift-pipelines" "tekton-pipelines-controller" 600
fi

if helm template "${RELEASE_NAME}" "${HELM_CHART_DIR}" -f "${HELM_CHART_DIR}/values.yaml" -f "${VALUES_GENERATED}" | grep -q "ecr-secret-operator"; then
	wait_for_csv "${ECR_OPERATOR_NAMESPACE}" "ecr-secret-operator" 600
	wait_for_crd "secrets.ecr.mobb.redhat.com" 300
	ECR_ROLE_ARN="$(echo "$(load_terraform_outputs)" | jq -r '.ecr_operator_role_arn')"
	log "Annotating ECR operator service account for IRSA (${ECR_ROLE_ARN})..."
	oc annotate serviceaccount ecr-secret-operator-controller-manager \
		-n "${ECR_OPERATOR_NAMESPACE}" \
		"eks.amazonaws.com/role-arn=${ECR_ROLE_ARN}" \
		--overwrite
	oc rollout restart deployment/ecr-secret-operator-controller-manager -n "${ECR_OPERATOR_NAMESPACE}"
	wait_for_deployment "${ECR_OPERATOR_NAMESPACE}" "ecr-secret-operator-controller-manager" 300
fi

log "Phase 2: Installing supply chain resources..."
helm upgrade --install "${RELEASE_NAME}" "${HELM_CHART_DIR}" \
	"${HELM_ARGS[@]}" \
	--wait \
	--timeout 10m

log "Install complete."
