# Agent E2E — OpenShift Virtualization (`clusters/virt`)

Recipe-specific steps for agent-guided validation. **Generic flow:** [AGENTS.md](../../AGENTS.md#agent-guided-end-to-end-e2e-cluster-validation). **Human runbook:** [enablement.md — OpenShift Virtualization](../../docs/deployment/enablement.md#openshift-virtualization).

## Recipe summary

| Item | Value |
|------|--------|
| Cluster name | `virt` (`cluster_name` in `terraform.tfvars`) |
| GitOps path | `dev/virt` on [rosa-cluster-config](https://github.com/rh-mobb/rosa-cluster-config) |
| Network | Public multi-AZ; Route Server + 3× Intel metal (`c5.metal`) BGP router pools |
| Storage | EFS RWX (`enable_efs`); platform metadata → `cluster-efs` chart |
| Cost | ~$16/hr (metal + workers) — **teardown promptly** |

## When to run this E2E

- Changes to `clusters/virt/terraform.tfvars`, route-server module, EFS/BGP IAM, bootstrap pins, or `dev/virt` GitOps.
- After merging `cluster-bootstrap` / `cluster-efs` chart changes that affect `efs-sc` or bootstrap StorageClass.
- Before merging Terraform PRs that touch Virt enablement or teardown (BGP peer cleanup).

## Step 5 — GitOps / Day-2 gates (after generic bootstrap)

Run after `make cluster.virt.login`. Poll until all pass (typically 15–45 min after bootstrap).

```bash
# Platform metadata (IRSA / EFS / BGP secret name)
oc -n openshift-gitops get configmap rosa-platform-metadata -o yaml

# EFS StorageClass — uid/gid 107 required for KubeVirt (cluster-efs >= 0.5.1, bootstrap >= 0.5.20)
oc get storageclass efs-sc -o jsonpath='uid={.parameters.uid} gid={.parameters.gid}{"\n"}'

# CNV / KubeVirt
oc get csv -n openshift-cnv | grep -i kubevirt

# Argo apps (representative)
oc get applications.argoproj.io -n openshift-gitops | grep -E 'cluster-config|cluster-efs|external-secrets|virtualization|cudn'

# BGP operator
oc get pods -n openshift-cudn-bgp-routing
oc get deployment -n openshift-cudn-bgp-routing -o jsonpath='{.items[0].status.readyReplicas}{"\n"}'

# Metal workers (KVM)
oc get nodes -l bgp_router=true
```

**Done when:**

| Check | Expected |
|-------|----------|
| `efs-sc` | `uid=107`, `gid=107` |
| KubeVirt CSV | `Succeeded` |
| `cluster-efs`, ESO, `rosa-virtualization` Argo apps | Synced / Healthy |
| BGP operator deployment | `readyReplicas >= 1` |
| Metal nodes | 3 nodes `Ready` with `bgp_router=true` |

### CDI clone memory (GitOps + verification)

`dev/virt` sets `rosa-virtualization` **≥ 1.0.3** `hyperConverged.resourceRequirements.storageWorkloads` (4Gi limits) so CDI clone/upload pods do not OOM on large disks (default **600M** fails cloning ~30Gi Fedora → `efs-sc`).

After Argo syncs `cluster-config-rosa-virtualization`, verify:

```bash
oc get cdiconfig config -o jsonpath='{.status.defaultPodResourceRequirements.limits.memory}{"\n"}'
# Expected: 4Gi
```

**Break-glass** (cluster deployed before GitOps pin, or chart not yet published):

```bash
oc patch hyperconverged kubevirt-hyperconverged -n openshift-cnv --type=merge -p \
  '{"spec":{"resourceRequirements":{"storageWorkloads":{"limits":{"memory":"4Gi","cpu":"2"},"requests":{"memory":"1Gi","cpu":"500m"}}}}}'
```

### Known failure modes

| Symptom | Likely cause | Action |
|---------|----------------|--------|
| `efs-sc` missing uid/gid 107 | Bootstrap chart < 0.5.20 or cluster-efs conflict | Confirm `helm_chart_version` default; inspect bootstrap vs cluster-efs Job logs; avoid deleting `efs-sc` on greenfield if pins are correct |
| DV clone stuck ~65%, upload OOMKilled | CDI 600M limit | Confirm GitOps `rosa-virtualization` ≥ 1.0.3 synced; `cdiconfig` shows 4Gi; break-glass patch if needed; delete stuck DV/tmp PVCs and retry |
| Upload server `disk.img: file exists` after OOM | Partial clone on tmp EFS PVC | Delete `virt-e2e-test` namespace and tmp resources in `openshift-virtualization-os-images`; retry |
| Target PVC Pending on `efs-sc` during clone | Normal until clone completes | Do not treat as EFS CSI failure while DV phase is `CloneInProgress` |
| Destroy fails on Route Server peers | Stale BGP peers | Use `destroy_force` (runs `cleanup-route-server-bgp-peers.sh`); see destroy log |

## Step 6 — Smoke tests

### EFS live migration (primary Virt E2E)

```bash
./scripts/cluster/test-virt-efs-live-migrate.sh
# Or: CLUSTER_NAME=virt ./scripts/cluster/test-virt-efs-live-migrate.sh
```

Manifest: [`test-efs-live-migrate.yaml`](test-efs-live-migrate.yaml) — Fedora DV from os-images PVC → `efs-sc`, VM on metal, live migration between `bgp_router` nodes.

**Done when:** script prints `EFS_LIVE_MIGRATE_EXIT:0` (DV Succeeded, VMI Running, migration Succeeded).

Optional manual checks after test:

```bash
oc get dv,vmi,pvc -n virt-e2e-test
```

Cleanup test namespace before teardown (optional; destroy does not require it):

```bash
oc delete namespace virt-e2e-test --wait=false
```

## Step 7 — Teardown

```bash
make cluster.virt.destroy_force   # tmux; ~45–60 min; validates BGP endpoint/peer cleanup
```

Confirm in AWS: VPC gone, no `virt-*` metal instances, Route Server removed.

If destroy is interrupted: clear `clusters/virt/.infrastructure.tfstate.lock.info`, reconcile orphans vs state, then re-plan.

## Terraform outputs (debug)

```bash
cd terraform
export TF_DATA_DIR="../clusters/virt/.terraform"
terraform output -raw bgp_config_secret_name
terraform output -raw efs_file_system_id
terraform output -raw efs_csi_role_arn
terraform output -raw secrets_manager_role_arn
```

## Maintaining this file

When changing Virt recipe behavior, update **this file** in the same PR as code/docs:

- New GitOps apps or gate commands
- New smoke tests or manifests under `clusters/virt/`
- New failure modes from live E2E
- Chart version pins that affect bootstrap or `efs-sc`

Also update [enablement.md](../../docs/deployment/enablement.md#openshift-virtualization) for human operators.
