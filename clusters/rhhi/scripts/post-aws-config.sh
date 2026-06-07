#!/bin/bash
# clusters/rhhi/scripts/post-aws-config.sh — ECR enhanced scanning configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

require_cmd aws

RHHI_JSON="$(load_terraform_outputs)"
AWS_REGION="$(echo "${RHHI_JSON}" | jq -r '.aws_region')"
ECR_PREFIX="$(echo "${RHHI_JSON}" | jq -r '.ecr_repository_prefix')"

log "Configuring ECR enhanced scanning in ${AWS_REGION}..."
aws ecr put-registry-scanning-configuration \
	--region "${AWS_REGION}" \
	--scan-type ENHANCED \
	--rules "[{\"scanFrequency\":\"CONTINUOUS_SCAN\",\"repositoryFilters\":[{\"filter\":\"*\",\"filterType\":\"WILDCARD\"}]}]"

log "Validating pull-through cache rule for prefix ${ECR_PREFIX}..."
aws ecr validate-pull-through-cache-rule \
	--ecr-repository-prefix "${ECR_PREFIX}" \
	--region "${AWS_REGION}"

log "Post-AWS configuration complete."
