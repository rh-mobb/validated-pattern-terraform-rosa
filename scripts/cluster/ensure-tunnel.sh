#!/bin/bash
# scripts/cluster/ensure-tunnel.sh
# Start Client VPN if terraform reports it deployed (no-op otherwise).
# Usage: ensure-tunnel.sh <cluster-name>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../common.sh"

CLUSTER_NAME="${1:-}"
if [ -z "$CLUSTER_NAME" ]; then
	error "Usage: $0 <cluster-name>"
	exit 1
fi

get_cluster_dir "$CLUSTER_NAME" >/dev/null
TERRAFORM_DIR=$(get_terraform_dir infrastructure)

cd "$TERRAFORM_DIR"
VPN_DEPLOYED=$(terraform output -no-color -raw client_vpn_deployed 2>/dev/null | tr -d '\n\r' | sed 's/[[:space:]]*$//' || true)
if [ "$VPN_DEPLOYED" = "true" ]; then
	info "Client VPN deployed — starting VPN tunnel..."
	"$SCRIPT_DIR/../vpn/start.sh" "$CLUSTER_NAME"
else
	info "Client VPN not deployed — skipping tunnel"
fi
