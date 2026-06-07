#!/bin/bash
# clusters/rhhi/scripts/render-values.sh — render Helm values from Terraform outputs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

OUT="${VALUES_GENERATED}"
RHHI_JSON="$(load_terraform_outputs)"

AWS_ACCOUNT_ID="$(echo "${RHHI_JSON}" | jq -r '.aws_account_id')"
AWS_REGION="$(echo "${RHHI_JSON}" | jq -r '.aws_region')"
ECR_REGISTRY_URL="$(echo "${RHHI_JSON}" | jq -r '.ecr_registry_url')"
ECR_PREFIX="$(echo "${RHHI_JSON}" | jq -r '.ecr_repository_prefix')"
TEKTON_ROLE="$(echo "${RHHI_JSON}" | jq -r '.tekton_ecr_role_arn')"
OPERATOR_ROLE="$(echo "${RHHI_JSON}" | jq -r '.ecr_operator_role_arn')"
TEKTON_NS="$(echo "${RHHI_JSON}" | jq -r '.tekton_namespace')"
TEKTON_SA="$(echo "${RHHI_JSON}" | jq -r '.tekton_service_account')"
OPERATOR_NS="$(echo "${RHHI_JSON}" | jq -r '.ecr_operator_namespace')"

cat >"${OUT}" <<EOF
global:
  awsAccountId: "${AWS_ACCOUNT_ID}"
  awsRegion: "${AWS_REGION}"
  ecrRegistryUrl: "${ECR_REGISTRY_URL}"
  ecrRepositoryPrefix: "${ECR_PREFIX}"

tekton:
  namespace: "${TEKTON_NS}"
  serviceAccount: "${TEKTON_SA}"
  tektonEcrRoleArn: "${TEKTON_ROLE}"

ecrOperator:
  namespace: "${OPERATOR_NS}"
  roleArn: "${OPERATOR_ROLE}"
EOF

log "Wrote ${OUT}"
