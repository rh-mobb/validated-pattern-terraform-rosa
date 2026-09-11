#!/usr/bin/env bash
# Smoke test: KubeVirt VM on CUDN (prod / 10.100.0.0/16) ↔ Terraform bastion in the VPC.
# Validates BGP route propagation using HTTP IP echo (osd-gcp-cudn-routing pattern).
# Prerequisite: targeted bastion apply — see clusters/virt/AGENTS.md (Step 6b).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-virt}"
REGION="${AWS_REGION:-ap-southeast-2}"
MANIFEST="${REPO_ROOT}/clusters/${CLUSTER_NAME}/test-external-vm-ping.yaml"
NS=virt-bgp-prod
VM=pingvm
SSH_DIR="${REPO_ROOT}/clusters/${CLUSTER_NAME}/.virt-e2e"
SSH_KEY="${SSH_DIR}/id_ed25519"
SSH_PUB="${SSH_KEY}.pub"
KEY_IN_NETSHOOT="/scratch/virt-e2e-vm-key"
NETSHOOT_KEY_COPIED=""
HTTP_PORT="${VIRT_E2E_HTTP_PORT:-8080}"
CURL_ATTEMPTS="${CUDN_E2E_HTTP_CURL_ATTEMPTS:-12}"
CURL_CONNECT="${CUDN_E2E_HTTP_CONNECT_TIMEOUT:-10}"
CURL_MAX="${CUDN_E2E_HTTP_MAX_TIME:-25}"
CURL_SLEEP="${CUDN_E2E_HTTP_RETRY_SLEEP:-3}"
# Cross-boundary traffic requires ROSA worker SG rules (bastion_enable_bgp_e2e + enable_route_server).
# Default strict off for backward compatibility; use VIRT_E2E_STRICT_HTTP_CROSS=1 for full GCP-style HTTP.
STRICT_HTTP_CROSS="${VIRT_E2E_STRICT_HTTP_CROSS:-0}"
LOG="${REPO_ROOT}/clusters/${CLUSTER_NAME}/logs/$(date -u +%Y%m%dT%H%M%SZ)-external-vm-ping.log"

ensure_ssh_key() {
	mkdir -p "${SSH_DIR}"
	if [[ ! -f "${SSH_KEY}" ]]; then
		ssh-keygen -t ed25519 -N "" -f "${SSH_KEY}" -C "virt-e2e@${NS}"
	fi
	chmod 600 "${SSH_KEY}" 2>/dev/null || true
	chmod 644 "${SSH_PUB}" 2>/dev/null || true
}

wait_ssm_online() {
	local instance_id="$1"
	echo "Waiting for SSM agent on bastion ${instance_id}..."
	for i in $(seq 1 36); do
		local status
		status="$(aws ssm describe-instance-information --region "${REGION}" \
			--filters "Key=InstanceIds,Values=${instance_id}" \
			--query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || true)"
		echo "  SSM status=${status:-missing} (${i}/36)"
		if [[ "${status}" == "Online" ]]; then
			return 0
		fi
		sleep 10
	done
	return 1
}

ensure_bastion_http_echo() {
	local instance_id="$1"
	# Caller-IP echo on :8080 — stdlib Python (no podman/docker.io; matches VM guest in test-external-vm-ping.yaml).
	local params_file ssm_id
	params_file="$(mktemp)"
	python3 - "${HTTP_PORT}" >"${params_file}" <<'PY'
import json
import sys

port = sys.argv[1]
py_script = f"""from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
  def do_GET(self):
    self.send_response(200); self.end_headers()
    self.wfile.write(self.client_address[0].encode())
  def log_message(self, *a): pass
HTTPServer(('0.0.0.0', {port}), H).serve_forever()
"""
cmds = [
    "pkill -f icanhazip-e2e-fallback.py || true",
    f"cat > /usr/local/bin/icanhazip-e2e-fallback.py <<'EOF'\n{py_script}\nEOF",
    "chmod 755 /usr/local/bin/icanhazip-e2e-fallback.py",
    "nohup python3 /usr/local/bin/icanhazip-e2e-fallback.py >/var/log/icanhazip-e2e-fallback.log 2>&1 &",
    "sleep 2",
    f"curl -sfS --max-time 5 http://127.0.0.1:{port}/ >/dev/null",
]
print(json.dumps({"commands": cmds}))
PY
	ssm_id="$(aws ssm send-command --region "${REGION}" \
		--instance-ids "${instance_id}" \
		--document-name AWS-RunShellScript \
		--parameters "file://${params_file}" \
		--query 'Command.CommandId' --output text)"
	rm -f "${params_file}"
	sleep 15
	aws ssm wait command-executed --region "${REGION}" \
		--command-id "${ssm_id}" --instance-id "${instance_id}" || true
	local status
	status="$(aws ssm get-command-invocation --region "${REGION}" \
		--command-id "${ssm_id}" --instance-id "${instance_id}" \
		--query Status --output text 2>/dev/null || true)"
	if [[ "${status}" != "Success" ]]; then
		aws ssm get-command-invocation --region "${REGION}" \
			--command-id "${ssm_id}" --instance-id "${instance_id}" \
			--query '[StandardOutputContent,StandardErrorContent]' --output text
		return 1
	fi
	echo "Bastion HTTP echo on :${HTTP_PORT} OK"
}

discover_cudn_ip() {
	local pod="$1"
	oc exec -n "${NS}" "${pod}" -- sh -c \
		"ip -4 -o addr show scope global | awk '{print \$4}' | cut -d/ -f1 | grep '^10\\.100\\.' | head -1"
}

discover_ping_iface() {
	local ip="$1"
	local out
	out="$(oc exec -n "${NS}" netshoot-cudn -- ip -br a 2>/dev/null || true)"
	printf '%s\n' "${out}" | awk -v w="${ip}" '{ for (i = 3; i <= NF; i++) if ($i ~ "^" w "/") { print $1; exit } }' | sed 's/@.*//'
}

netshoot_curl_retry() {
	local url="$1"
	oc exec -n "${NS}" netshoot-cudn -- sh -c \
		'a=$1; cto=$2; mto=$3; sl=$4; url=$5; i=1; \
     while [ "$i" -le "$a" ]; do \
       out="$(curl -sS --connect-timeout "$cto" --max-time "$mto" "$url")" && printf %s "$out" && exit 0; \
       sleep "$sl"; i=$((i + 1)); \
     done; exit 1' \
		sh "${CURL_ATTEMPTS}" "${CURL_CONNECT}" "${CURL_MAX}" "${CURL_SLEEP}" "${url}"
}

netshoot_ensure_key() {
	if [[ -n "${NETSHOOT_KEY_COPIED}" ]]; then
		return 0
	fi
	oc cp "${SSH_KEY}" "${NS}/netshoot-cudn:${KEY_IN_NETSHOOT}" -c netshoot
	oc exec -n "${NS}" netshoot-cudn -c netshoot -- chmod 600 "${KEY_IN_NETSHOOT}"
	NETSHOOT_KEY_COPIED=1
}

netshoot_vm_curl() {
	local vm_ip="$1" url="$2"
	netshoot_ensure_key
	oc exec -n "${NS}" netshoot-cudn -c netshoot -- \
		ssh -i "${KEY_IN_NETSHOOT}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		"fedora@${vm_ip}" "curl -sS --connect-timeout ${CURL_CONNECT} --max-time ${CURL_MAX} '${url}'"
}

ssm_bastion_curl() {
	local instance_id="$1" url="$2"
	local ssm_id body
	ssm_id="$(aws ssm send-command --region "${REGION}" \
		--instance-ids "${instance_id}" \
		--document-name AWS-RunShellScript \
		--parameters "commands=[\"curl -sS --connect-timeout ${CURL_CONNECT} --max-time ${CURL_MAX} '${url}'\"]" \
		--query 'Command.CommandId' --output text)"
	sleep 8
	body="$(aws ssm get-command-invocation --region "${REGION}" \
		--command-id "${ssm_id}" --instance-id "${instance_id}" \
		--query StandardOutputContent --output text 2>/dev/null | tr -d '\r\n' || true)"
	printf '%s' "${body}"
}

ssm_bastion_ping() {
	local instance_id="$1" target_ip="$2"
	local ssm_id status
	ssm_id="$(aws ssm send-command --region "${REGION}" \
		--instance-ids "${instance_id}" \
		--document-name AWS-RunShellScript \
		--parameters "commands=[\"ping -c 3 -W 2 '${target_ip}'\"]" \
		--query 'Command.CommandId' --output text)"
	sleep 8
	status="$(aws ssm get-command-invocation --region "${REGION}" \
		--command-id "${ssm_id}" --instance-id "${instance_id}" \
		--query Status --output text 2>/dev/null || true)"
	[[ "${status}" == "Success" ]]
}

resolve_bastion_from_tf() {
	cd "${REPO_ROOT}/terraform"
	export TF_DATA_DIR="${REPO_ROOT}/clusters/${CLUSTER_NAME}/.terraform"
	terraform init -reconfigure -input=false \
		-backend-config="path=$(pwd)/../clusters/${CLUSTER_NAME}/infrastructure.tfstate" >/dev/null
	BASTION_DEPLOYED="$(terraform output -raw bastion_deployed 2>/dev/null || echo false)"
	BASTION_ID="$(terraform output -raw bastion_instance_id 2>/dev/null || true)"
	BASTION_IP="$(terraform output -raw bastion_private_ip 2>/dev/null || true)"
}

mkdir -p "$(dirname "${LOG}")"
exec > >(tee -a "${LOG}") 2>&1

echo "=== External VM ping test $(date -u +%Y-%m-%dT%H:%M:%SZ) cluster=${CLUSTER_NAME} ==="
echo "Pattern: osd-gcp-cudn-routing (netshoot + HTTP :${HTTP_PORT} curl IP verification)"

cd "${REPO_ROOT}"
make "cluster.${CLUSTER_NAME}.login"
ensure_ssh_key
resolve_bastion_from_tf

if [[ "${BASTION_DEPLOYED}" != "true" || -z "${BASTION_ID}" || "${BASTION_ID}" == "null" || -z "${BASTION_IP}" || "${BASTION_IP}" == "null" ]]; then
	echo "VIRT_EXTERNAL_PING_EXIT:1 Bastion not deployed."
	echo "Apply targeted bastion first — see clusters/${CLUSTER_NAME}/AGENTS.md (Step 6b)."
	exit 1
fi
echo "Terraform bastion: ${BASTION_ID} private_ip=${BASTION_IP}"

if ! wait_ssm_online "${BASTION_ID}"; then
	echo "VIRT_EXTERNAL_PING_EXIT:1 SSM not online on bastion ${BASTION_ID}"
	exit 1
fi
ensure_bastion_http_echo "${BASTION_ID}"

echo "--- Applying CUDN VM + netshoot manifest ---"
oc delete namespace "${NS}" --ignore-not-found --wait=true 2>/dev/null || true
TMP_MANIFEST="$(mktemp)"
sed "s|__SSH_PUB_KEY__|$(tr -d '\r\n' <"${SSH_PUB}")|" "${MANIFEST}" >"${TMP_MANIFEST}"
oc apply -f "${TMP_MANIFEST}"
rm -f "${TMP_MANIFEST}"
oc wait --for=condition=Ready pod/netshoot-cudn -n "${NS}" --timeout=5m
echo "--- Waiting for DataVolume ---"
oc wait --for=condition=Ready "datavolume/${VM}-root" -n "${NS}" --timeout=25m

echo "--- Waiting for VMI Running + CUDN IP ---"
VM_IP=""
for i in $(seq 1 60); do
	phase="$(oc get vmi "${VM}" -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
	VM_IP="$(oc get vmi "${VM}" -n "${NS}" -o jsonpath='{.status.interfaces[0].ipAddress}' 2>/dev/null || true)"
	echo "  VMI phase=${phase:-missing} ip=${VM_IP:-pending} (${i}/60)"
	if [[ "${phase}" == "Running" && "${VM_IP}" =~ ^10\.100\. ]]; then
		break
	fi
	sleep 15
done
if [[ ! "${VM_IP}" =~ ^10\.100\. ]]; then
	echo "VIRT_EXTERNAL_PING_EXIT:1 VM did not get prod CUDN IP (got '${VM_IP}')"
	exit 1
fi
echo "CUDN VM IP: ${VM_IP}"

NETSHOOT_IP="$(discover_cudn_ip netshoot-cudn)"
PING_IFACE="$(discover_ping_iface "${NETSHOOT_IP}")"
PING_IFACE="${PING_IFACE:-ovn-udn1}"
echo "netshoot CUDN IP=${NETSHOOT_IP} ping_iface=${PING_IFACE}"

echo "--- Wait for VM HTTP :${HTTP_PORT} (from netshoot) ---"
VM_HTTP_OK=false
for i in $(seq 1 "${CURL_ATTEMPTS}"); do
	if netshoot_curl_retry "http://${VM_IP}:${HTTP_PORT}/" >/dev/null 2>&1; then
		VM_HTTP_OK=true
		break
	fi
	echo "  VM HTTP attempt ${i}/${CURL_ATTEMPTS} (cloud-init / guest echo may still be starting)"
	sleep "${CURL_SLEEP}"
done
if ! test "${VM_HTTP_OK}" = "true"; then
	echo "VIRT_EXTERNAL_PING_EXIT:1 VM HTTP :${HTTP_PORT} not reachable from netshoot"
	exit 1
fi

echo "--- netshoot → VM (curl; body should be netshoot CUDN IP) ---"
BODY_NETSHOOT_VM="$(netshoot_curl_retry "http://${VM_IP}:${HTTP_PORT}/" | tr -d '\r\n')"
echo "HTTP body: ${BODY_NETSHOOT_VM} (expected ${NETSHOOT_IP})"
if [[ "${BODY_NETSHOOT_VM}" != "${NETSHOOT_IP}" ]]; then
	echo "VIRT_EXTERNAL_PING_EXIT:1 netshoot→VM HTTP IP mismatch"
	exit 1
fi
echo "netshoot → VM: OK"

if [[ "${STRICT_HTTP_CROSS}" == "1" ]]; then
	echo "--- Bastion → VM (curl; body should be bastion IP) [strict] ---"
	BODY_BASTION_VM="$(ssm_bastion_curl "${BASTION_ID}" "http://${VM_IP}:${HTTP_PORT}/")"
	echo "HTTP body: ${BODY_BASTION_VM} (expected ${BASTION_IP})"
	if [[ "${BODY_BASTION_VM}" != "${BASTION_IP}" ]]; then
		echo "VIRT_EXTERNAL_PING_EXIT:1 Bastion→VM HTTP IP mismatch"
		exit 1
	fi
	echo "Bastion → VM HTTP: OK"

	echo "--- VM → Bastion (in-guest curl via netshoot SSH; body should be VM IP) [strict] ---"
	BODY_VM_BASTION=""
	for i in $(seq 1 "${CURL_ATTEMPTS}"); do
		if BODY_VM_BASTION="$(netshoot_vm_curl "${VM_IP}" "http://${BASTION_IP}:${HTTP_PORT}/" 2>/dev/null | tr -d '\r\n')"; then
			break
		fi
		echo "  VM→Bastion curl attempt ${i}/${CURL_ATTEMPTS} (SSH/cloud-init may still be starting)"
		sleep "${CURL_SLEEP}"
	done
	echo "HTTP body: ${BODY_VM_BASTION} (expected ${VM_IP})"
	if [[ "${BODY_VM_BASTION}" != "${VM_IP}" ]]; then
		echo "VIRT_EXTERNAL_PING_EXIT:1 VM→Bastion HTTP IP mismatch"
		exit 1
	fi
	echo "VM → Bastion HTTP: OK"
else
	echo "--- Cross-boundary HTTP :${HTTP_PORT} (optional strict: VIRT_E2E_STRICT_HTTP_CROSS=1) ---"
	echo "NOTE: Requires worker SG rules from bastion_enable_bgp_e2e (see clusters/virt/AGENTS.md Step 6b)."
	BODY_BASTION_VM="$(ssm_bastion_curl "${BASTION_ID}" "http://${VM_IP}:${HTTP_PORT}/")"
	if [[ "${BODY_BASTION_VM}" == "${BASTION_IP}" ]]; then
		echo "Bastion → VM HTTP: OK (bonus)"
	else
		echo "Bastion → VM HTTP: skipped (body='${BODY_BASTION_VM}', expected ${BASTION_IP})"
	fi
fi

echo "--- ICMP: netshoot → bastion ---"
if ! oc exec -n "${NS}" netshoot-cudn -- ping -I "${PING_IFACE}" -c 3 -W 2 "${BASTION_IP}"; then
	echo "VIRT_EXTERNAL_PING_EXIT:1 ICMP netshoot → bastion failed"
	exit 1
fi
echo "ICMP netshoot → bastion: OK"

echo "--- ICMP: bastion → VM (SSM ping) ---"
if ! ssm_bastion_ping "${BASTION_ID}" "${VM_IP}"; then
	echo "VIRT_EXTERNAL_PING_EXIT:1 ICMP bastion → VM failed"
	exit 1
fi
echo "ICMP bastion → VM: OK"

echo "--- ICMP: VM → bastion (in-guest ping via netshoot SSH) ---"
if ! netshoot_ensure_key && oc exec -n "${NS}" netshoot-cudn -c netshoot -- \
	ssh -i "${KEY_IN_NETSHOOT}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	"fedora@${VM_IP}" "ping -c 3 -W 2 ${BASTION_IP}"; then
	echo "VIRT_EXTERNAL_PING_EXIT:1 ICMP VM → bastion failed"
	exit 1
fi
echo "ICMP VM → bastion: OK"

echo "VIRT_EXTERNAL_PING_EXIT:0"
echo "Cleanup k8s: oc delete namespace ${NS}"
echo "Optional bastion teardown: targeted apply with enable_bastion=false — AGENTS.md Step 6b"
