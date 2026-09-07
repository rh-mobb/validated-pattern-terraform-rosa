# Cluster lifecycle hooks

Optional shell hooks under `clusters/<profile>/scripts/` extend the standard Make lifecycle (`apply`, `bootstrap`, `destroy`) with profile-specific steps — without baking one-off logic into shared `scripts/cluster/` or Terraform `null_resource` provisioners.

**Status:** Design / contract ([#72](https://github.com/rh-mobb/validated-pattern-terraform-rosa/issues/72)); runner not implemented yet. See [Implementation checklist](#implementation-checklist).

Related: [clusters/README.md](../../clusters/README.md), [scripts/README.md](../../scripts/README.md), [OpenShift Virtualization enablement](../deployment/enablement.md#openshift-virtualization).

---

## When to use hooks vs shared scripts vs Terraform

| Need | Use |
|------|-----|
| Logic required for **one** cluster profile (e.g. virt BGP teardown) | **Cluster hook** in `clusters/<profile>/scripts/` |
| Logic required for **any** cluster matching a tfvar (e.g. `enable_route_server`) | **Shared** script under `scripts/cluster/` called from a hook or thin wrapper |
| AWS/API cleanup that must run **inside** `terraform destroy` with no cluster API | Prefer **shared script** invoked from `pre-destroy.sh`; avoid Terraform `local-exec` unless there is no alternative |
| Resources Terraform already owns | **Terraform** only — hooks must not duplicate create/delete of TF-managed objects except as pre/post orchestration |

**Rule:** Shared scripts hold reusable implementation; hooks orchestrate (call shared scripts, `oc`, waits). Do not fork the same AWS cleanup into both a hook and a `null_resource`.

---

## Layout

```
clusters/<profile>/
├── terraform.tfvars
└── scripts/                    # optional; all hooks optional
    ├── pre-create.sh
    ├── post-create.sh
    ├── pre-bootstrap.sh
    ├── post-bootstrap.sh
    ├── pre-destroy.sh
    └── post-destroy.sh
```

- Hooks are **per cluster directory** (`clusters/virt/scripts/`, not repo-root `scripts/`).
- Only add hooks a profile needs; missing files are skipped.
- Hooks must be **executable** (`chmod +x`) to run — non-executable files are ignored with a warning (explicit opt-in).

---

## When each hook runs

Hooks are invoked by the shared runner from cluster lifecycle scripts / Make targets. Names use **`create`** for infrastructure apply (historical “create cluster” wording), not `init` or `plan`.

| Hook | Runs when | Parent operation |
|------|-----------|------------------|
| `pre-create.sh` | Immediately **before** `terraform apply` | `make cluster.<profile>.apply` |
| `post-create.sh` | Immediately **after** successful `terraform apply` | `make cluster.<profile>.apply` |
| `pre-bootstrap.sh` | Immediately **before** GitOps bootstrap body | `make cluster.<profile>.bootstrap`, `.bootstrap-gitea`, `.bootstrap-spoke`, `.bootstrap-skip-gitops` |
| `post-bootstrap.sh` | Immediately **after** successful bootstrap | Same bootstrap targets |
| `pre-destroy.sh` | Immediately **before** `terraform destroy` | `make cluster.<profile>.destroy`, `.destroy_force` |
| `post-destroy.sh` | Immediately **after** successful `terraform destroy` | Same destroy targets |

**Out of scope (no hooks today):**

| Operation | Why |
|-----------|-----|
| `make cluster.<profile>.init` / `.plan` | Init/plan should stay fast and side-effect free |
| `make cluster.<profile>.sleep` | Uses `cleanup-infrastructure.sh` (apply with `persists_through_sleep=false`), not destroy — different semantics; add `pre-sleep`/`post-sleep` only if a future need is documented |
| Direct `terraform` / script calls bypassing Make | Hooks run only through the supported entry points above |

---

## Runner contract

### Invocation

```text
clusters/<profile>/scripts/<hook-name>.sh <profile>
```

The runner sets environment variables before calling the hook:

| Variable | Description |
|----------|-------------|
| `CLUSTER_NAME` | Profile name (e.g. `virt`) |
| `CLUSTER_DIR` | Absolute path to `clusters/<profile>` |
| `PROJECT_ROOT` | Repository root |
| `AUTO_APPROVE` | `true` when destroy runs without confirmation (`destroy_force`) |

Hooks may also read tfvars via `get_tfvar` after sourcing `scripts/common.sh`.

### Exit codes

| Hook phase | Non-zero exit from hook |
|------------|------------------------|
| **pre-*** | **Abort** the parent operation (destroy/apply/bootstrap must not proceed) |
| **post-*** | **Abort** the Make target (operation already succeeded; failure is reported for CI/logs so operators fix hook or re-run post step manually) |

### Logging

Hooks should use `info` / `warn` / `error` / `success` from `scripts/common.sh` (stderr for diagnostics) so output is consistent with other cluster scripts.

---

## Requirements (humans and agents)

### 1. Idempotent

Every hook must be safe to run **more than once** with the same outcome:

- Second run after success → no-op or harmless warnings.
- Partial prior run → converge to clean state, not worse state.

**Good:** `oc delete cudnbgprouting --all --ignore-not-found`; AWS delete peer that is already gone; skip `oc` steps when `oc whoami` fails.

**Bad:** Assumes CR exists and fails; assumes peer count is non-zero; creates duplicate resources on re-run.

### 2. Graceful degradation

Hooks often run when the world is **partially** torn down. Handle missing prerequisites without spurious failures:

| Condition | Expected behavior |
|-----------|-------------------|
| Cluster API unreachable / `oc` not logged in | Skip in-cluster steps; continue with out-of-band cleanup (e.g. AWS CLI) where possible |
| CRs already deleted | Treat as success |
| Terraform state empty / cluster never applied | `pre-destroy` should still attempt external cleanup if AWS resources might exist |
| Optional tool missing | **Fail** only if that tool is required for the profile; otherwise skip with `warn` |

Use `set -euo pipefail` in hooks, but wrap **optional** branches explicitly (`if oc whoami ...; then ...; else warn ...; fi`) — do not let optional steps abort required cleanup.

### 3. Fail only when blocked

Return non-zero only when the **parent operation cannot safely proceed**:

- `pre-destroy`: peers/endpoints still block Terraform destroy after cleanup attempts and waits.
- `pre-create`: validation proves apply will fail (missing pull secret path, invalid quota check).

Do **not** fail post-hooks for cosmetic issues (e.g. deleting a temp file that is already gone).

### 4. No secrets in git

Hooks must not hardcode credentials. Use env vars, `clusters/<profile>/private-gitops.env` (gitignored), AWS/RHCS ambient auth, or `oc` login from `make cluster.<profile>.login`.

### 5. Reuse shared scripts

Call existing `scripts/cluster/*.sh` instead of inlining AWS logic. Example: virt `pre-destroy.sh` should call `scripts/cluster/cleanup-route-server-bgp-peers.sh` after operator-driven deletion, not duplicate `delete-route-server-peer` loops.

### 6. Agents: do not add Terraform `null_resource` for profile-only teardown

If cleanup is profile-specific (virt BGP), use `clusters/virt/scripts/pre-destroy.sh`. Reserve Terraform destroy provisioners for gaps that **cannot** run while the cluster API still exists and that apply to **all** clusters with a tfvar — and prefer shared scripts + hooks first.

---

## Example: `clusters/virt` pre-destroy (planned)

OpenShift Virtualization + CUDN BGP leaves **route-server-peers** in AWS. The [bgp-cloud-connector](https://github.com/openshift/bgp-cloud-connector) operator deletes managed peers only when `CUDNBgpConfig` is deleted **while the operator is still running**; cluster destroy does not run that finalizer path.

**Intended `pre-destroy.sh` flow:**

1. If `enable_route_server != true` in tfvars → exit 0.
2. If cluster API is up (`oc whoami`):
   - `oc delete cudnbgprouting --all --wait=true` (ignore-not-found).
   - `oc delete cudnbgpconfig cluster --wait=true` (ignore-not-found).
   - Poll until operator finalizer completes or timeout (peers tagged `managed-by: cudn-bgp-routing-operator/...` drain).
3. Always run `scripts/cluster/cleanup-route-server-bgp-peers.sh <profile>` to remove stragglers and orphaned endpoints (idempotent).
4. Exit non-zero only if peers/endpoints still block destroy after waits.

**Then** the runner proceeds to `terraform destroy` (no route-server `null_resource` in Terraform).

---

## Hook template

```bash
#!/usr/bin/env bash
# clusters/<profile>/scripts/pre-destroy.sh
set -euo pipefail

CLUSTER_NAME="${1:?cluster name required}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../../../scripts/common.sh"

CLUSTER_DIR="${CLUSTER_DIR:-$(get_cluster_dir "$CLUSTER_NAME")}"

# Optional: gate on tfvars
if [[ "$(get_tfvar "$CLUSTER_DIR" enable_route_server false)" != "true" ]]; then
  info "enable_route_server false; nothing to do"
  exit 0
fi

# Optional in-cluster steps (graceful skip)
if command -v oc >/dev/null 2>&1 && oc whoami >/dev/null 2>&1; then
  info "Deleting CUDN BGP CRs..."
  oc delete cudnbgprouting --all --ignore-not-found --wait=true --timeout=120s || true
  oc delete cudnbgpconfig cluster --ignore-not-found --wait=true --timeout=300s || true
else
  warn "oc unavailable; skipping operator finalizer path"
fi

# Shared AWS cleanup (idempotent)
"${PROJECT_ROOT:-$(get_project_root)}/scripts/cluster/cleanup-route-server-bgp-peers.sh" "$CLUSTER_NAME"

success "pre-destroy complete for ${CLUSTER_NAME}"
```

---

## Implementation checklist

- [ ] `run_cluster_hook()` in `scripts/common.sh` (+ executable check, env exports)
- [ ] Wire runner into `apply-infrastructure.sh`, `destroy-infrastructure.sh`
- [ ] Wire runner into `Makefile.cluster` bootstrap targets (pre/post)
- [ ] Remove route-server `null_resource` destroy hook (replaced by virt `pre-destroy.sh`)
- [ ] Remove `enable_route_server` special case from `destroy-infrastructure.sh` (virt hook calls shared script)
- [ ] Add `clusters/virt/scripts/pre-destroy.sh`
- [ ] Document in `clusters/README.md`, `scripts/README.md`, enablement virt teardown section
- [ ] ShellCheck + `make sh-lint` on new hooks

---

## References

- Operator graceful delete: [bgp-cloud-connector README](https://github.com/openshift/bgp-cloud-connector) — delete `CUDNBgpRouting` then `CUDNBgpConfig cluster` before uninstall.
- Shared peer cleanup: `scripts/cluster/cleanup-route-server-bgp-peers.sh`
- ROSA SG destroy pattern (Terraform `null_resource`): `modules/infrastructure/cluster/21-cleanup-rosa-security-groups.tf` — different constraint (runs after cluster destroy); do not copy for virt BGP without reading this doc.
