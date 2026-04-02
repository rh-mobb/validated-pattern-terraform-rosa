#!/bin/bash
# scripts/cluster/link-skupper-sites.sh
# Links two Skupper sites by exchanging AccessGrant tokens between spoke clusters.
#
# Usage:
#   ./link-skupper-sites.sh <spoke-1-cluster> <spoke-2-cluster>
#
# Example:
#   ./link-skupper-sites.sh dev-spoke-1 dev-spoke-2
#
# Prerequisites:
#   - Both clusters must have Skupper sites deployed with AccessGrants in the target namespace
#   - Terraform state must be available for both clusters (for login credentials)
#   - oc must be installed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../common.sh"

PROJECT_ROOT=$(get_project_root)
NAMESPACE="${SKUPPER_NAMESPACE:-istio-demo}"
GRANT_NAME="${SKUPPER_GRANT_NAME:-skupper-grant}"

usage() {
	echo "Usage: $0 <spoke-1-cluster> <spoke-2-cluster>"
	echo ""
	echo "Links Skupper sites between two spoke clusters by exchanging AccessGrant tokens."
	echo ""
	echo "Arguments:"
	echo "  spoke-1-cluster   Name of the first cluster (e.g., dev-spoke-1)"
	echo "  spoke-2-cluster   Name of the second cluster (e.g., dev-spoke-2)"
	echo ""
	echo "Environment variables:"
	echo "  SKUPPER_NAMESPACE    Namespace where Skupper is deployed (default: istio-demo)"
	echo "  SKUPPER_GRANT_NAME   Name of the AccessGrant resource (default: skupper-grant)"
	exit 1
}

CLUSTER_1="${1:-}"
CLUSTER_2="${2:-}"

if [[ -z "$CLUSTER_1" || -z "$CLUSTER_2" ]]; then
	usage
fi

get_cluster_dir "$CLUSTER_1" >/dev/null
get_cluster_dir "$CLUSTER_2" >/dev/null
check_required_tools oc

login_to_cluster() {
	local cluster_name="$1"

	info "Logging into cluster ${cluster_name}..."

	if ! "$PROJECT_ROOT/scripts/cluster/init-infrastructure.sh" "$cluster_name"; then
		error "Failed to initialize terraform for ${cluster_name}"
		exit 1
	fi

	if ! "$PROJECT_ROOT/scripts/info/login.sh" "$cluster_name"; then
		error "Failed to log into ${cluster_name}"
		exit 1
	fi
}

cleanup_stale_links() {
	local namespace="$1"
	local grant_name="$2"

	info "Cleaning up stale tokens and grants in ${namespace}..."

	oc delete accesstokens --all -n "$namespace" 2>/dev/null || true
	oc delete links --all -n "$namespace" 2>/dev/null || true
	oc delete accessgrant "$grant_name" -n "$namespace" 2>/dev/null || true

	info "Waiting for ArgoCD to recreate AccessGrant..."
	sleep 10
}

wait_for_grant() {
	local grant_name="$1"
	local namespace="$2"
	local max_attempts=30
	local attempt=1

	info "Waiting for AccessGrant ${grant_name} to be ready..."

	while [[ $attempt -le $max_attempts ]]; do
		local url code ca
		url=$(oc get accessgrant "$grant_name" -n "$namespace" -o jsonpath='{.status.url}' 2>/dev/null || echo "")
		code=$(oc get accessgrant "$grant_name" -n "$namespace" -o jsonpath='{.status.code}' 2>/dev/null || echo "")
		ca=$(oc get accessgrant "$grant_name" -n "$namespace" -o jsonpath='{.status.ca}' 2>/dev/null || echo "")

		if [[ -n "$url" && -n "$code" && -n "$ca" ]]; then
			success "AccessGrant is ready (attempt ${attempt}/${max_attempts})"
			return 0
		fi

		echo "  Waiting... (attempt ${attempt}/${max_attempts})"
		sleep 10
		((attempt++))
	done

	error "AccessGrant ${grant_name} did not become ready in time"
	exit 1
}

extract_grant() {
	local grant_name="$1"
	local namespace="$2"
	local field="$3"

	oc get accessgrant "$grant_name" -n "$namespace" -o jsonpath="{.status.${field}}" 2>/dev/null
}

apply_access_token() {
	local token_name="$1"
	local namespace="$2"
	local url="$3"
	local code="$4"
	local ca="$5"

	info "Applying AccessToken ${token_name} in namespace ${namespace}..."

	local tmpfile
	tmpfile=$(mktemp /tmp/skupper-token-XXXXXX.yaml)
	trap "rm -f '$tmpfile'" RETURN

	cat > "$tmpfile" <<EOF
apiVersion: skupper.io/v2alpha1
kind: AccessToken
metadata:
  name: ${token_name}
  namespace: ${namespace}
spec:
  url: "${url}"
  code: "${code}"
  ca: |
EOF
	echo "$ca" | sed 's/^/    /' >> "$tmpfile"

	oc apply -f "$tmpfile"
}

# ============================================================
# Main
# ============================================================

info "=== Skupper Site Linking ==="
info "Cluster 1: ${CLUSTER_1}"
info "Cluster 2: ${CLUSTER_2}"
info "Namespace: ${NAMESPACE}"
info "Grant name: ${GRANT_NAME}"
echo ""

# --- Step 1: Log into cluster 1, clean up, and extract grant ---
login_to_cluster "$CLUSTER_1"
cleanup_stale_links "$NAMESPACE" "$GRANT_NAME"
wait_for_grant "$GRANT_NAME" "$NAMESPACE"

C1_URL=$(extract_grant "$GRANT_NAME" "$NAMESPACE" "url")
C1_CODE=$(extract_grant "$GRANT_NAME" "$NAMESPACE" "code")
C1_CA=$(extract_grant "$GRANT_NAME" "$NAMESPACE" "ca")

success "Extracted AccessGrant from ${CLUSTER_1}"

# --- Step 2: Log into cluster 2, clean up, apply token from cluster 1, extract grant ---
login_to_cluster "$CLUSTER_2"
cleanup_stale_links "$NAMESPACE" "$GRANT_NAME"
wait_for_grant "$GRANT_NAME" "$NAMESPACE"

apply_access_token "${CLUSTER_1}-link" "$NAMESPACE" "$C1_URL" "$C1_CODE" "$C1_CA"
success "Applied ${CLUSTER_1} token to ${CLUSTER_2}"

C2_URL=$(extract_grant "$GRANT_NAME" "$NAMESPACE" "url")
C2_CODE=$(extract_grant "$GRANT_NAME" "$NAMESPACE" "code")
C2_CA=$(extract_grant "$GRANT_NAME" "$NAMESPACE" "ca")

success "Extracted AccessGrant from ${CLUSTER_2}"

# --- Step 3: Log back into cluster 1 and apply token from cluster 2 ---
login_to_cluster "$CLUSTER_1"

apply_access_token "${CLUSTER_2}-link" "$NAMESPACE" "$C2_URL" "$C2_CODE" "$C2_CA"
success "Applied ${CLUSTER_2} token to ${CLUSTER_1}"

# --- Step 4: Verify ---
echo ""
info "=== Verifying link on ${CLUSTER_1} ==="
sleep 5
oc get links -n "$NAMESPACE" 2>/dev/null || warn "No links found yet"
oc get sites -n "$NAMESPACE" 2>/dev/null || true

echo ""
info "=== Skupper sites linked successfully ==="
info "Run 'oc get links -n ${NAMESPACE}' on either cluster to verify."
info "Services exposed via Connectors are now reachable across both clusters."
