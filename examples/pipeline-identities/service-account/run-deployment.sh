#!/usr/bin/env bash
# Purpose: Keep one deployment's credential in a newly allocated private directory.
# What this is not: Cleanup after an uncatchable signal, runner loss or a failed filesystem is not guaranteed.
# Prerequisites: Bash, Python 3, GNU timeout/date, oc, and the sibling mint helper.
# Custody boundary: trusted job code in an isolated ephemeral runner; no shared UID writers.
# Authoritative references:
# - https://www.gnu.org/software/bash/manual/html_node/Bourne-Shell-Builtins.html
set -euo pipefail
set +x
umask 077
: "${MANIFEST_DIR:?MANIFEST_DIR is required}"
: "${DEPLOYMENT_NAME:?DEPLOYMENT_NAME is required}"
# Covers: env:KUBECONFIG_PATH
# Does: Assigns the exact new credential destination owned by this invocation.
# Why: Reusing a workspace path can cross another job's custody boundary.
# Change: Keep allocation and cleanup bound to this same private directory.
# Trap: Never substitute a pre-existing directory or recursively sweep /tmp.
# Evidence: https://www.gnu.org/software/coreutils/manual/html_node/mktemp-invocation.html
# mktemp creates a new mode-0700 directory atomically; no prior job path is reused.
job_dir=$(mktemp -d /tmp/pipeline-job.XXXXXXXXXX)
export KUBECONFIG_PATH="$job_dir/kubeconfig"
cleanup() {
  status=$?
  trap - EXIT
  # Exact destination owned by this invocation; no recursive or wildcard removal.
  if ! rm -f -- "$KUBECONFIG_PATH" || ! rmdir -- "$job_dir"; then
    echo 'credential cleanup failed; runner owner must contain this job workspace' >&2
    exit 1
  fi
  # Optional non-secret completion receipt, outside the credential directory.
  # Never overwrite a prior receipt; callers use a CI job-specific name.
  if [ -n "${PIPELINE_CLEANUP_RECEIPT:-}" ]; then
    (set -C; printf '%s\n' complete > "$PIPELINE_CLEANUP_RECEIPT") || exit 1
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
"$(dirname "$0")/mint-kubeconfig.sh"
unset PIPELINE_TOKEN
# Covers: --foreground, --signal, --kill-after, --kubeconfig, --filename, --timeout, --request-timeout
# Does: Bounds each oc process and preserves the job's signal delivery group.
# Why: A per-request timeout alone does not bound a multi-request apply.
# Change: Re-budget credential lifetime and cleanup when these process bounds change.
# Trap: Uncatchable termination and storage failures still require runner-owner recovery.
# Evidence: https://www.gnu.org/software/coreutils/manual/html_node/timeout-invocation.html
# Bound each complete oc process, not merely an individual HTTP request.
# Keep it in the job process group so cancellation can reach oc and the EXIT trap.
timeout --foreground --signal=TERM --kill-after=30s 5m oc --kubeconfig="$KUBECONFIG_PATH" apply --filename="$MANIFEST_DIR" --request-timeout=30s
timeout --foreground --signal=TERM --kill-after=30s 6m oc --kubeconfig="$KUBECONFIG_PATH" rollout status "deployment/$DEPLOYMENT_NAME" --timeout=5m --request-timeout=30s
# EXIT cleanup runs on normal success/failure and catchable termination. SIGKILL,
# runner loss or a failed filesystem can prevent it; ephemeral-runner disposal
# and separately owned token expiry/revocation remain the recovery boundary.
