#!/bin/bash
# clusters/rhhi/scripts/preflight.sh — validate prerequisites for RHHI demo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

log "Checking required CLI tools..."
for cmd in aws oc helm jq terraform; do
	require_cmd "${cmd}"
	log "  ok: ${cmd}"
done

if command -v tkn >/dev/null 2>&1; then
	log "  ok: tkn"
else
	log "  warn: tkn not found (optional until run-demo)"
fi

if command -v docker >/dev/null 2>&1 || command -v podman >/dev/null 2>&1; then
	log "  ok: container CLI (docker or podman)"
else
	log "  warn: docker/podman not found (required for seed-cache)"
fi

if oc whoami >/dev/null 2>&1; then
	log "  ok: oc logged in as $(oc whoami)"
else
	log "  warn: oc not logged in — run 'make cluster.${CLUSTER_DIR}.login'"
fi

log "Preflight complete."
