#!/bin/bash
# clusters/rhhi/scripts/run-pipeline.sh — populate source PVC and start Tekton PipelineRun

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

RHHI_JSON="$(load_terraform_outputs)"
ECR_REGISTRY="$(echo "${RHHI_JSON}" | jq -r '.ecr_registry_url')"
ECR_PREFIX="$(echo "${RHHI_JSON}" | jq -r '.ecr_repository_prefix')"
REGISTRY_PREFIX="${ECR_REGISTRY}/${ECR_PREFIX}"

DESTINATION_IMAGE="${DESTINATION_IMAGE:-quay-cache/internal/hardened-app:1.0.0}"
PVC_NAME="rhhi-demo-source"
LOADER_POD="rhhi-demo-source-loader"
PIPELINERUN_PREFIX="rhhi-demo-build"
DEMO_BUILD_DIR="$(mktemp -d)"

cleanup() {
	rm -rf "${DEMO_BUILD_DIR}"
	oc delete pod "${LOADER_POD}" -n "${TEKTON_NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

require_cmd oc
require_cmd tkn

log "Preparing demo source with ECR registry prefix ${REGISTRY_PREFIX}..."
cp -a "${RHHI_DIR}/demo-app/." "${DEMO_BUILD_DIR}/"
sed "s|\${REGISTRY_PREFIX}|${REGISTRY_PREFIX}|g" "${DEMO_BUILD_DIR}/Dockerfile" >"${DEMO_BUILD_DIR}/Dockerfile.resolved"
mv "${DEMO_BUILD_DIR}/Dockerfile.resolved" "${DEMO_BUILD_DIR}/Dockerfile"

cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
  namespace: ${TEKTON_NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

oc delete pod "${LOADER_POD}" -n "${TEKTON_NAMESPACE}" --ignore-not-found
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${LOADER_POD}
  namespace: ${TEKTON_NAMESPACE}
spec:
  restartPolicy: Never
  containers:
    - name: loader
      image: registry.access.redhat.com/ubi9/ubi:latest
      command: ["sleep", "600"]
      volumeMounts:
        - name: src
          mountPath: /workspace
  volumes:
    - name: src
      persistentVolumeClaim:
        claimName: ${PVC_NAME}
EOF

oc wait --for=condition=Ready "pod/${LOADER_POD}" -n "${TEKTON_NAMESPACE}" --timeout=120s
oc cp "${DEMO_BUILD_DIR}/." "${TEKTON_NAMESPACE}/${LOADER_POD}:/workspace/"
oc delete pod "${LOADER_POD}" -n "${TEKTON_NAMESPACE}" --wait=true

FULL_DEST="${ECR_REGISTRY}/${DESTINATION_IMAGE}"
BASE_IMAGE="${ECR_REGISTRY}/${ECR_PREFIX}/${RHHI_BASE_IMAGE:-hummingbird/python:3.14.5}"

log "Starting PipelineRun with prefix ${PIPELINERUN_PREFIX}..."
tkn pipeline start rhhi-secure-build \
	-n "${TEKTON_NAMESPACE}" \
	--prefix-name="${PIPELINERUN_PREFIX}" \
	-p "base-image-url=${BASE_IMAGE}" \
	-p "destination-image=${FULL_DEST}" \
	-w "name=source,claimName=${PVC_NAME}" \
	-w "name=dockerconfig,secret=aws-ecr-creds" \
	--serviceaccount="ecr-pipeline-sa" \
	--showlog

log "PipelineRun finished."
