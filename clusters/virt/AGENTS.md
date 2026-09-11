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

## Known limitation — CUDN VMs on BGP peers only

Until [bgp-cloud-connector#121](https://github.com/openshift/bgp-cloud-connector/issues/121) lands, the operator sets **`SourceDestCheck=false`** (AWS anti-spoofing / IP forwarding) only on nodes matching `routerNodeSelector` (`bgp_router=true`). CUDN egress uses the **scheduling node’s ENI** with the **CUDN source IP preserved** (RouteAdvertisements; not SNAT to the worker primary IP). Replies and outbound VPC traffic from a VM on a **non-speaker** worker fail unless that node’s ENI also allows forwarding.

**Until #121:** schedule **KubeVirt VMs** (and any CUDN workload that must reach the VPC with a routable overlay IP) on **`bgp_router` metal pools only** — `nodeSelector: { bgp_router: "true" }`. Default `m7i` workers are for platform/GitOps only.

Production shape (small speaker pool + CUDN on general workers) needs #121 or an interim all-workers workaround (see ARO `azure-nic-ip-forwarding` pattern). This recipe **collapses** speakers and VM compute onto the same three metal nodes to stay within Route Server peer limits and avoid the extra-hop gap.

### EgressIP not used (ruled out)

**EgressIP** SNATs CUDN traffic to a worker-subnet IP before it hits the cloud — the opposite of this recipe, which uses **RouteAdvertisements + BGP** so the VPC routes the **real CUDN prefix** (`10.100.0.0/16`) to VM/pod IPs.

EgressIP was investigated for CUDN **internet egress** elsewhere (osd-gcp-cudn-routing) and ruled out for Layer2 primary UDN:

| Blocker | Reference |
|---------|-----------|
| Not supported for Layer2 CUDN (OCP 4.21 Advanced Networking) | Product docs; see `reference/osd-gcp-cudn-routing/KNOWLEDGE.md` |
| OVN EgressIP flows broken on non–gateway-router nodes (`/32`-per-node platforms) | [OCPBUGS-48301](https://issues.redhat.com/browse/OCPBUGS-48301) |
| Planned upstream fix (Layer2 transit router + EgressIP) | [OKEP-5094](https://ovn-kubernetes.io/okeps/okep-5094-layer2-transit-router/) — OCP 4.22+; ROSA delivery not confirmed |

Do not substitute EgressIP for BGP peer placement or `SourceDestCheck` on speakers. Even if OKEP-5094 lands, it does not replace preserved-IP VPC routing for the external VM ↔ bastion gate.

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
| VPC ↔ CUDN timeout; VM on default worker | VM not on BGP peer; #121 not landed | Move VM to `bgp_router` node; confirm `nodeSelector` — see [Known limitation](#known-limitation--cudn-vms-on-bgp-peers-only) |

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

### Step 6b — External VM ↔ bastion BGP test (optional)

Validates CUDN VM (`10.100.0.0/16`) ↔ VPC host over BGP using HTTP caller-IP echo (osd-gcp pattern). **Off by default** — bastion is not in the main `terraform.tfvars`; enable only for this gate.

**Agent flow:**

1. **Apply bastion + worker SG rules (targeted, ~2 min)** — does not change default `enable_bastion = false` in `terraform.tfvars`. Worker SG rules require `bastion_enable_bgp_e2e=true` with `enable_route_server=true` (set in `bastion-e2e.tfvars` + main tfvars):

```bash
cd terraform
export TF_DATA_DIR="../clusters/virt/.terraform"
terraform init -reconfigure -input=false \
  -backend-config="path=$(pwd)/../clusters/virt/infrastructure.tfstate"
terraform apply \
  -var="cluster_config_dir=virt" \
  -var-file="../clusters/virt/terraform.tfvars" \
  -var-file="../clusters/virt/bastion-e2e.tfvars" \
  -target='module.bastion[0]' \
  -target='module.cluster.aws_vpc_security_group_ingress_rule.bgp_e2e_vpc_all[0]'
terraform output bastion_instance_id bastion_private_ip
```

2. **Run smoke test:**

```bash
VIRT_E2E_STRICT_HTTP_CROSS=1 ./scripts/cluster/test-virt-external-vm-ping.sh
# Done when: VIRT_EXTERNAL_PING_EXIT:0 (strict HTTP both ways + ICMP)
```

3. **Cleanup test workloads:**

```bash
oc delete namespace virt-bgp-prod --wait=false
```

4. **Remove bastion (optional before full teardown)** — or rely on `make cluster.virt.destroy_force` (main tfvars has `enable_bastion = false`, so bastion is destroyed with the stack):

```bash
cd terraform
export TF_DATA_DIR="../clusters/virt/.terraform"
terraform apply \
  -var="cluster_config_dir=virt" \
  -var-file="../clusters/virt/terraform.tfvars" \
  -var='enable_bastion=false' \
  -var='bastion_enable_bgp_e2e=false' \
  -target='module.bastion[0]'
```

**Done when:** `VIRT_EXTERNAL_PING_EXIT:0` with `VIRT_E2E_STRICT_HTTP_CROSS=1` — netshoot→VM and bastion↔VM HTTP caller-IP on `:8080`, plus bidirectional ICMP. Requires worker SG rules from `bastion_enable_bgp_e2e` (ROSA default SG allows ICMP/SSH from VPC but blocks other cross-boundary traffic until then). `:8080` is the smoke-test port only; SG rules allow all traffic from the VPC/CUDN CIDRs.

Manifest: [`test-external-vm-ping.yaml`](test-external-vm-ping.yaml). Guest echo uses stdlib Python (no `podman pull` — CUDN lacks docker.io/repo egress). Bastion SG + worker SG + HTTP echo: `bastion_enable_bgp_e2e` in [`bastion-e2e.tfvars`](bastion-e2e.tfvars).

## Step 7 — Teardown (operator-approved only)

**Do not run teardown automatically** after smoke tests — ask the operator first. They may want to keep the cluster for manual checks, re-run tests, or inspect Argo/operators.

When approved:

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
