#!/bin/bash
# clusters/rhhi/scripts/test.sh — verify RHHI supply chain prerequisites and artifacts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

RHHI_JSON="$(load_terraform_outputs)"
AWS_REGION="$(echo "${RHHI_JSON}" | jq -r '.aws_region')"
ECR_PREFIX="$(echo "${RHHI_JSON}" | jq -r '.ecr_repository_prefix')"
WORKER_ROLE="${CLUSTER_NAME}-HCP-ROSA-Worker-Role"

require_cmd aws
require_cmd oc

log "Test: ECR pull-through cache rule..."
aws ecr validate-pull-through-cache-rule \
	--ecr-repository-prefix "${ECR_PREFIX}" \
	--region "${AWS_REGION}"

log "Test: worker role ECR read policy..."
# shellcheck disable=SC2016 # JMESPath query uses backticks inside single-quoted string
aws iam list-attached-role-policies --role-name "${WORKER_ROLE}" \
	--query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly`]' \
	--output text | grep -q AmazonEC2ContainerRegistryReadOnly ||
	die "Worker role ${WORKER_ROLE} missing AmazonEC2ContainerRegistryReadOnly policy"

log "Test: ECR Secret Operator secret in ${TEKTON_NAMESPACE}..."
oc get secret aws-ecr-creds -n "${TEKTON_NAMESPACE}" >/dev/null

log "Test: Tekton pipeline exists..."
oc get pipeline rhhi-secure-build -n "${TEKTON_NAMESPACE}" >/dev/null

log "All tests passed."
