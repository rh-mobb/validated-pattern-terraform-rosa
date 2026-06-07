#!/bin/bash
# clusters/rhhi/scripts/seed-cache.sh — warm ECR pull-through cache with RHHI base images

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

RHHI_JSON="$(load_terraform_outputs)"
AWS_REGION="$(echo "${RHHI_JSON}" | jq -r '.aws_region')"
ECR_REGISTRY="$(echo "${RHHI_JSON}" | jq -r '.ecr_registry_url')"
ECR_PREFIX="$(echo "${RHHI_JSON}" | jq -r '.ecr_repository_prefix')"

RHHI_BASE_IMAGE="${RHHI_BASE_IMAGE:-hummingbird/python:3.11-runtime}"
RHHI_BUILDER_IMAGE="${RHHI_BUILDER_IMAGE:-hummingbird/python:3.11-builder}"

if command -v docker >/dev/null 2>&1; then
	CONTAINER_CLI=docker
elif command -v podman >/dev/null 2>&1; then
	CONTAINER_CLI=podman
else
	die "docker or podman required for seed-cache"
fi

require_cmd aws

log "Authenticating to ECR ${ECR_REGISTRY}..."
aws ecr get-login-password --region "${AWS_REGION}" |
	"${CONTAINER_CLI}" login --username AWS --password-stdin "${ECR_REGISTRY}"

for image in "${RHHI_BASE_IMAGE}" "${RHHI_BUILDER_IMAGE}"; do
	full="${ECR_REGISTRY}/${ECR_PREFIX}/${image}"
	log "Pulling ${full} (triggers pull-through cache)..."
	"${CONTAINER_CLI}" pull "${full}"
done

log "Seed cache complete."
