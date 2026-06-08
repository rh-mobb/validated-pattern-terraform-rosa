#!/bin/bash
# clusters/rhhi/scripts/status.sh — show RHHI supply chain component status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

log "Helm release:"
helm status rhhi-supply-chain -n "${TEKTON_NAMESPACE}" 2>/dev/null || log "  (not installed)"

if oc whoami >/dev/null 2>&1; then
	log "OpenShift Pipelines CSV:"
	oc get csv -n openshift-operators 2>/dev/null | grep -i pipelines || true

	log "ECR Secret Operator CSV:"
	oc get csv -n "${ECR_OPERATOR_NAMESPACE}" 2>/dev/null | grep -i ecr || true

	log "ECR credentials secret:"
	oc get secret aws-ecr-creds -n "${TEKTON_NAMESPACE}" 2>/dev/null || log "  aws-ecr-creds not found"

	log "Tekton PipelineRuns:"
	if command -v tkn >/dev/null 2>&1; then
		tkn pipelinerun list -n "${TEKTON_NAMESPACE}" 2>/dev/null || true
	else
		oc get pipelinerun -n "${TEKTON_NAMESPACE}" 2>/dev/null || true
	fi
else
	log "oc not logged in — skipping cluster checks"
fi

if command -v aws >/dev/null 2>&1; then
	if RHHI_JSON="$(load_terraform_outputs 2>/dev/null)"; then
		AWS_REGION="$(echo "${RHHI_JSON}" | jq -r '.aws_region')"
		ECR_PREFIX="$(echo "${RHHI_JSON}" | jq -r '.ecr_repository_prefix')"
		log "ECR pull-through validation:"
		aws ecr validate-pull-through-cache-rule \
			--ecr-repository-prefix "${ECR_PREFIX}" \
			--region "${AWS_REGION}" 2>/dev/null || log "  validation failed or rule missing"
	fi
fi

log "Status complete."
