#!/usr/bin/env bash
# Smoke test: Fedora VM disk on efs-sc (RWX) + live migration between metal workers.
# Requires cluster-efs >= 0.5.1 (efs-sc uid/gid 107) and CNV Available.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-virt}"
MANIFEST="${REPO_ROOT}/clusters/${CLUSTER_NAME}/test-efs-live-migrate.yaml"
NS=virt-e2e-test
VM=efs-testvm
LOG="${REPO_ROOT}/clusters/${CLUSTER_NAME}/logs/$(date -u +%Y%m%dT%H%M%SZ)-efs-live-migrate.log"

mkdir -p "$(dirname "${LOG}")"
exec > >(tee -a "${LOG}") 2>&1

echo "=== EFS live migration test $(date -u +%Y-%m-%dT%H:%M:%SZ) cluster=${CLUSTER_NAME} ==="

cd "${REPO_ROOT}"
make "cluster.${CLUSTER_NAME}.login"

echo "--- Validating efs-sc (cluster-efs >= 0.5.1) ---"
efs_uid="$(oc get storageclass efs-sc -o jsonpath='{.parameters.uid}' 2>/dev/null || true)"
efs_gid="$(oc get storageclass efs-sc -o jsonpath='{.parameters.gid}' 2>/dev/null || true)"
if [[ "${efs_uid}" != "107" || "${efs_gid}" != "107" ]]; then
	echo "ERROR: efs-sc must set parameters.uid/gid=107 for KubeVirt (got uid=${efs_uid:-<unset>} gid=${efs_gid:-<unset>})" >&2
	echo "Sync cluster-efs chart >= 0.5.1 or re-run bootstrap + Argo sync." >&2
	exit 1
fi

echo "--- Applying manifests ---"
oc apply -f "${MANIFEST}"

echo "--- Waiting for DataVolume ---"
oc wait --for=condition=Ready datavolume/efs-testvm-root -n "${NS}" --timeout=20m

echo "--- DataVolume status ---"
oc get datavolume efs-testvm-root -n "${NS}" -o wide
oc get pvc efs-testvm-root -n "${NS}" -o custom-columns='NAME:.metadata.name,SC:.spec.storageClassName,AM:.status.accessModes[0],PHASE:.status.phase'

echo "--- Waiting for VMI Running ---"
for i in $(seq 1 60); do
	phase="$(oc get vmi "${VM}" -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
	if [[ "${phase}" == "Running" ]]; then
		break
	fi
	echo "  VMI phase=${phase:-missing} (${i}/60)"
	sleep 15
done
phase="$(oc get vmi "${VM}" -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
if [[ "${phase}" != "Running" ]]; then
	echo "ERROR: VMI not Running (phase=${phase})"
	oc describe vmi "${VM}" -n "${NS}" | tail -40
	exit 1
fi

src_node="$(oc get vmi "${VM}" -n "${NS}" -o jsonpath='{.status.nodeName}')"
echo "VMI Running on node: ${src_node}"

echo "--- Triggering live migration ---"
oc delete virtualmachineinstancemigration "${VM}-migrate" -n "${NS}" --ignore-not-found
cat <<EOF | oc apply -f -
apiVersion: kubevirt.io/v1
kind: VirtualMachineInstanceMigration
metadata:
  name: ${VM}-migrate
  namespace: ${NS}
spec:
  vmiName: ${VM}
EOF

echo "--- Waiting for migration to complete ---"
for i in $(seq 1 40); do
	mphase="$(oc get virtualmachineinstancemigration "${VM}-migrate" -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
	echo "  migration phase=${mphase:-pending} (${i}/40)"
	if [[ "${mphase}" == "Succeeded" ]]; then
		break
	fi
	if [[ "${mphase}" == "Failed" ]]; then
		oc describe virtualmachineinstancemigration "${VM}-migrate" -n "${NS}"
		exit 1
	fi
	sleep 15
done

mphase="$(oc get virtualmachineinstancemigration "${VM}-migrate" -n "${NS}" -o jsonpath='{.status.phase}')"
dst_node="$(oc get vmi "${VM}" -n "${NS}" -o jsonpath='{.status.nodeName}')"
vmi_phase="$(oc get vmi "${VM}" -n "${NS}" -o jsonpath='{.status.phase}')"

echo "--- Results ---"
echo "Migration phase: ${mphase}"
echo "Source node:     ${src_node}"
echo "Target node:     ${dst_node}"
echo "VMI phase:       ${vmi_phase}"

if [[ "${mphase}" != "Succeeded" ]]; then
	echo "EFS_LIVE_MIGRATE_EXIT:1 migration did not succeed"
	exit 1
fi
if [[ "${vmi_phase}" != "Running" ]]; then
	echo "EFS_LIVE_MIGRATE_EXIT:1 VMI not running after migration"
	exit 1
fi
if [[ "${src_node}" == "${dst_node}" ]]; then
	echo "WARNING: node unchanged — migration succeeded but VM stayed on same node"
fi

echo "EFS_LIVE_MIGRATE_EXIT:0"
echo "Cleanup: oc delete namespace ${NS}"
