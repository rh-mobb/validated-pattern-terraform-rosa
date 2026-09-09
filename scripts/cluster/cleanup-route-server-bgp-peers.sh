#!/usr/bin/env bash
# Remove AWS VPC Route Server BGP peers (and endpoints) left by the CUDN BGP operator.
# Invoked automatically on terraform destroy via null_resource.cleanup_route_server_bgp_peers
# (route-server module). Also safe to run manually before destroy.
#
# The operator registers route-server-peers when metal routers peer. After the ROSA
# cluster is gone, peers can block endpoint deletion and cause Terraform to fail on
# aws_vpc_route_server_vpc_association destroy.
#
# Usage: cleanup-route-server-bgp-peers.sh <cluster-name> [--dry-run]
# Env: ROUTE_SERVER_ID, AWS_REGION (optional overrides)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../common.sh"

CLUSTER_NAME="${1:-}"
DRY_RUN=false
if [[ "${2:-}" == "--dry-run" ]]; then
	DRY_RUN=true
fi

if [[ -z "$CLUSTER_NAME" ]]; then
	error "Usage: $0 <cluster-name> [--dry-run]"
	exit 1
fi

check_required_tools aws python3

CLUSTER_DIR=$(get_cluster_dir "$CLUSTER_NAME")
TERRAFORM_INFRA_DIR=$(get_terraform_dir infrastructure)
CLUSTER_TFVARS="$CLUSTER_DIR/terraform.tfvars"
WAIT_SECONDS="${ROUTE_SERVER_CLEANUP_WAIT_SECONDS:-300}"
POLL_SECONDS="${ROUTE_SERVER_CLEANUP_POLL_SECONDS:-5}"

resolve_region() {
	if [[ -n "${AWS_REGION:-}" ]]; then
		echo "$AWS_REGION"
		return
	fi
	if [[ -n "${REGION:-}" ]]; then
		echo "$REGION"
		return
	fi

	use_cluster_tf_data_dir "$CLUSTER_NAME"
	if cluster_tf_initialized; then
		local from_output
		from_output="$(
			cd "$TERRAFORM_INFRA_DIR" &&
				terraform output -no-color -raw region 2>/dev/null | tr -d '\n\r' || true
		)"
		if [[ -n "$from_output" ]]; then
			echo "$from_output"
			return
		fi
	fi

	get_tfvar "$CLUSTER_DIR" region ""
}

resolve_route_server_id() {
	if [[ -n "${ROUTE_SERVER_ID:-}" ]]; then
		echo "$ROUTE_SERVER_ID"
		return
	fi

	use_cluster_tf_data_dir "$CLUSTER_NAME"
	if cluster_tf_initialized; then
		local from_output
		from_output="$(
			cd "$TERRAFORM_INFRA_DIR" &&
				terraform output -no-color -raw route_server_id 2>/dev/null | tr -d '\n\r' || true
		)"
		if [[ -n "$from_output" && "$from_output" != "null" ]]; then
			echo "$from_output"
			return
		fi
	fi

	local region="$1"
	local tag_name="${CLUSTER_NAME}-route-server"
	aws ec2 describe-route-servers \
		--region "$region" \
		--filters "Name=tag:Name,Values=${tag_name}" \
		--output json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
servers = data.get('RouteServers', [])
if servers:
    print(servers[0].get('RouteServerId', ''))
" || true
}

list_peer_ids() {
	local region="$1"
	local route_server_id="$2"
	aws ec2 describe-route-server-peers --region "$region" --output json |
		python3 -c "
import json, sys
route_server_id = sys.argv[1]
active = {'available', 'pending', 'deleting'}
for peer in json.load(sys.stdin).get('RouteServerPeers', []):
    if peer.get('RouteServerId') != route_server_id:
        continue
    if peer.get('State') in active:
        print(peer['RouteServerPeerId'])
" "$route_server_id"
}

list_endpoint_ids() {
	local region="$1"
	local route_server_id="$2"
	aws ec2 describe-route-server-endpoints --region "$region" --output json |
		python3 -c "
import json, sys
route_server_id = sys.argv[1]
active = {'available', 'pending', 'deleting'}
for ep in json.load(sys.stdin).get('RouteServerEndpoints', []):
    if ep.get('RouteServerId') != route_server_id:
        continue
    if ep.get('State') in active:
        print(ep['RouteServerEndpointId'])
" "$route_server_id"
}

count_active_peers() {
	local region="$1"
	local route_server_id="$2"
	list_peer_ids "$region" "$route_server_id" | wc -l | tr -d ' '
}

count_active_endpoints() {
	local region="$1"
	local route_server_id="$2"
	list_endpoint_ids "$region" "$route_server_id" | wc -l | tr -d ' '
}

wait_for_count_zero() {
	local label="$1"
	local region="$2"
	local route_server_id="$3"
	local count_fn="$4"
	local elapsed=0
	local count

	while true; do
		count="$("$count_fn" "$region" "$route_server_id")"
		if [[ "$count" == "0" ]]; then
			return 0
		fi
		if ((elapsed >= WAIT_SECONDS)); then
			error "Timed out after ${WAIT_SECONDS}s waiting for ${label} to finish deleting (${count} remaining)"
			return 1
		fi
		info "  ${label}: ${count} remaining (${elapsed}s elapsed)"
		sleep "$POLL_SECONDS"
		elapsed=$((elapsed + POLL_SECONDS))
	done
}

delete_peers() {
	local region="$1"
	local route_server_id="$2"
	local peer_id
	local peer_ids=()

	while IFS= read -r peer_id; do
		[[ -n "$peer_id" ]] && peer_ids+=("$peer_id")
	done < <(list_peer_ids "$region" "$route_server_id")
	if [[ ${#peer_ids[@]} -eq 0 ]]; then
		info "No active route server peers for ${route_server_id}"
		return 0
	fi

	info "Deleting ${#peer_ids[@]} route server peer(s) for ${route_server_id}..."
	for peer_id in "${peer_ids[@]}"; do
		if [[ "$DRY_RUN" == true ]]; then
			info "[dry-run] would delete route server peer ${peer_id}"
			continue
		fi
		info "Deleting route server peer ${peer_id}"
		aws ec2 delete-route-server-peer \
			--region "$region" \
			--route-server-peer-id "$peer_id" >/dev/null
	done

	if [[ "$DRY_RUN" == true ]]; then
		return 0
	fi

	wait_for_count_zero "peers" "$region" "$route_server_id" count_active_peers
}

delete_endpoints() {
	local region="$1"
	local route_server_id="$2"
	local endpoint_id
	local endpoint_ids=()

	while IFS= read -r endpoint_id; do
		[[ -n "$endpoint_id" ]] && endpoint_ids+=("$endpoint_id")
	done < <(list_endpoint_ids "$region" "$route_server_id")
	if [[ ${#endpoint_ids[@]} -eq 0 ]]; then
		info "No active route server endpoints for ${route_server_id}"
		return 0
	fi

	info "Deleting ${#endpoint_ids[@]} route server endpoint(s) for ${route_server_id}..."
	for endpoint_id in "${endpoint_ids[@]}"; do
		if [[ "$DRY_RUN" == true ]]; then
			info "[dry-run] would delete route server endpoint ${endpoint_id}"
			continue
		fi
		info "Deleting route server endpoint ${endpoint_id}"
		aws ec2 delete-route-server-endpoint \
			--region "$region" \
			--route-server-endpoint-id "$endpoint_id" >/dev/null
	done

	if [[ "$DRY_RUN" == true ]]; then
		return 0
	fi

	wait_for_count_zero "endpoints" "$region" "$route_server_id" count_active_endpoints
}

enable_route_server="$(get_tfvar "$CLUSTER_DIR" enable_route_server false)"
if [[ "$enable_route_server" != "true" ]]; then
	info "enable_route_server is not true in ${CLUSTER_TFVARS}; nothing to clean up"
	exit 0
fi

region="$(resolve_region)"
if [[ -z "$region" ]]; then
	error "Could not determine AWS region (set AWS_REGION or region in terraform.tfvars)"
	exit 1
fi

route_server_id="$(resolve_route_server_id "$region")"
if [[ -z "$route_server_id" ]]; then
	info "No route server found for cluster ${CLUSTER_NAME}; nothing to clean up"
	exit 0
fi

info "Route server BGP cleanup for cluster=${CLUSTER_NAME} region=${region} route_server_id=${route_server_id}"
delete_peers "$region" "$route_server_id"
delete_endpoints "$region" "$route_server_id"
success "Route server peers and endpoints cleaned up for ${route_server_id}"
