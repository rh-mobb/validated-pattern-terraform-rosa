#!/usr/bin/env bash
# Purpose: Turn a ServiceAccount bearer supplied by the CI credential store into a job-local kubeconfig.
# What this is not: This does not mint a token. This example keeps TokenRequest authority with a separate authenticated rotator.
# Prerequisites: PIPELINE_TOKEN, PIPELINE_API_SERVER, PIPELINE_NAMESPACE and PIPELINE_SERVICE_ACCOUNT in the environment; oc and Python 3 on PATH; KUBECONFIG_PATH inside a new private job directory.
# Authoritative references:
# - https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/#tokenrequest-api
# - https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/
# - https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/
#
# The same script backs both the Jenkins and the GitLab example, so custody
# behaviour is written and reviewed once instead of twice.
set -euo pipefail

# Covers: set +x, umask 077
# Does: Stops shell tracing echoing the bearer and makes every file this job creates owner-only before it exists.
# Why: A traced pipeline prints its own credentials into build logs that are retained and often world-readable.
# Change: Removing either line leaks the bearer into logs or leaves the kubeconfig group-readable.
# Trap: umask must be set BEFORE the first write; chmod afterwards leaves a window where the file is readable.
# Evidence: Syntax-only: shell file-creation semantics.
set +x
umask 077

# Covers: env:PIPELINE_TOKEN, env:PIPELINE_API_SERVER, env:PIPELINE_NAMESPACE, env:PIPELINE_SERVICE_ACCOUNT, env:PIPELINE_TOKEN_EXPIRY, env:PIPELINE_EXPIRY_MARGIN_SECONDS, env:KUBECONFIG_PATH
# Does: Requires every mandatory input up front and fails with the missing name rather than part way through.
# Why: A protected CI variable is silently absent on an unprotected ref, and :? turns that into one clear error.
# Change: Supplying a default for PIPELINE_TOKEN would let the job continue unauthenticated.
# Trap: An unset variable under `set -u` aborts with a shell message that does not say which CI setting is wrong; :? names it.
# Evidence: https://docs.gitlab.com/ee/ci/variables/#protect-a-cicd-variable
: "${PIPELINE_TOKEN:?PIPELINE_TOKEN is required}"
: "${PIPELINE_API_SERVER:?PIPELINE_API_SERVER is required}"
: "${PIPELINE_NAMESPACE:?PIPELINE_NAMESPACE is required}"
: "${PIPELINE_SERVICE_ACCOUNT:?PIPELINE_SERVICE_ACCOUNT is required}"
PIPELINE_TOKEN_EXPIRY="${PIPELINE_TOKEN_EXPIRY:-}"
PIPELINE_EXPIRY_MARGIN_SECONDS="${PIPELINE_EXPIRY_MARGIN_SECONDS:-600}"
: "${KUBECONFIG_PATH:?KUBECONFIG_PATH must name a new file in a private job directory}"
export KUBECONFIG_PATH
if ! [[ "$PIPELINE_EXPIRY_MARGIN_SECONDS" =~ ^[0-9]+$ ]]; then
  echo 'PIPELINE_EXPIRY_MARGIN_SECONDS must be a nonnegative integer' >&2
  exit 1
fi

# Covers: env:PIPELINE_TOKEN_EXPIRY, env:PIPELINE_EXPIRY_MARGIN_SECONDS, date -d, date +%s
# Does: Refuses to start when the credential expires within the margin, and says so explicitly when it cannot tell.
# Why: This advisory preflight catches imminent expiry; it is not derived from all remaining steps and cannot guarantee mid-run validity.
# Change: Raising the margin refuses more runs early; lowering it accepts runs more likely to expire mid-flight.
# Trap: There are THREE outcomes here, not two. An absent expiry is "unobserved", not "fine" -- the script says which one it took rather than silently continuing.
# Evidence: https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/#tokenrequest-api
if [ -z "${PIPELINE_TOKEN_EXPIRY}" ]; then
  echo "expiry unobserved: PIPELINE_TOKEN_EXPIRY not supplied; this run cannot" >&2
  echo "  tell how long the credential is valid for. Record the mint's" >&2
  echo "  .status.expirationTimestamp beside the token to enable this check." >&2
elif ! expiry_epoch=$(date -u -d "${PIPELINE_TOKEN_EXPIRY}" +%s 2>/dev/null); then
  echo "expiry unobserved: PIPELINE_TOKEN_EXPIRY is not a timestamp this date(1) parses" >&2
else
  remaining=$(( expiry_epoch - $(date -u +%s) ))
  if [ "${remaining}" -le "${PIPELINE_EXPIRY_MARGIN_SECONDS}" ]; then
    echo "credential expires in ${remaining}s, at or below the ${PIPELINE_EXPIRY_MARGIN_SECONDS}s margin; rotate before running" >&2
    exit 1
  fi
  echo "expiry metadata reports ${remaining}s remaining; advisory margin only"
fi

# Covers: O_CREAT, O_EXCL, O_NOFOLLOW, fchmod, dir_fd, auth whoami, --kubeconfig, --request-timeout
# Does: Opens a new owner-only file without replacement, then verifies identity.
# Why: umask alone neither secures an existing file nor refuses symlinks.
# Change: Never replace the exclusive open with truncation or a prior exists check.
# Trap: The parent must be this job's private directory; shared writers are outside this custody boundary.
# Evidence: https://docs.python.org/3/library/os.html#os.open
python3 - <<'PYTHON'
import json
import os
from pathlib import Path
import stat
import subprocess
import sys

path = Path(os.environ["KUBECONFIG_PATH"])
# Pin the actual parent directory without following a symlink at any component.
parent = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
try:
    for part in path.absolute().parent.parts[1:]:
        next_parent = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        os.close(parent)
        parent = next_parent
    info = os.fstat(parent)
    if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError("kubeconfig parent must be owned by this user with mode 0700")
    # No output has been created if this call refuses an existing file or symlink.
    fd = os.open(path.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=parent)
    owned = os.fstat(fd)
    accepted = False
    try:
        os.fchmod(fd, 0o600)  # Set final permissions before the first bearer byte.
        config = {
            "apiVersion": "v1", "kind": "Config",
            "clusters": [{"name": "pipeline", "cluster": {"server": os.environ["PIPELINE_API_SERVER"]}}],
            "users": [{"name": "pipeline", "user": {"token": os.environ["PIPELINE_TOKEN"]}}],
            "contexts": [{"name": "pipeline", "context": {"cluster": "pipeline", "user": "pipeline", "namespace": os.environ["PIPELINE_NAMESPACE"]}}],
            "current-context": "pipeline",
        }
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(config, stream)
            stream.write("\n")
        expected = "system:serviceaccount:{}:{}".format(os.environ["PIPELINE_NAMESPACE"], os.environ["PIPELINE_SERVICE_ACCOUNT"])
        env = dict(os.environ)
        env.pop("PIPELINE_TOKEN", None)
        result = subprocess.run(["oc", "--kubeconfig=" + str(path), "auth", "whoami", "-o", "jsonpath={.status.userInfo.username}", "--request-timeout=30s"], capture_output=True, text=True, env=env, timeout=35)
        if result.returncode or result.stdout.strip() != expected:
            # Do not reflect arbitrary client diagnostics, which may contain secrets.
            raise ValueError("ServiceAccount identity verification failed")
        accepted = True
        print("authenticated as " + expected)
        print(path)
    finally:
        if not accepted:
            current = os.stat(path.name, dir_fd=parent, follow_symlinks=False)
            if (current.st_dev, current.st_ino) == (owned.st_dev, owned.st_ino):
                os.unlink(path.name, dir_fd=parent)
except (OSError, ValueError, subprocess.TimeoutExpired):
    print("kubeconfig creation or identity verification refused; no existing destination replaced", file=sys.stderr)
    sys.exit(1)
finally:
    os.close(parent)
PYTHON
