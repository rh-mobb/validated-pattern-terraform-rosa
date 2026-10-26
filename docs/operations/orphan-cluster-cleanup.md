# Orphan cluster cleanup runbook

**Audience:** AI agents and operators cleaning up a ROSA HCP cluster that was created with this repository’s Terraform modules but **no longer has a tracked `clusters/<name>/` directory or `infrastructure.tfstate`**.

**Canonical example:** `public-gpu` — deployed from this repo (apply/bootstrap logs under `clusters/*/logs/`), `ManagedBy: Terraform` tags, but `clusters/public-gpu/` and state file were removed from the checkout.

**Preferred path when state exists:** `make cluster.<name>.destroy` or `make cluster.<name>.destroy_force` — see [Scripts](scripts.md). **Do not use this runbook** if `clusters/<name>/infrastructure.tfstate` is present and accurate.

---

## When to use this runbook

| Situation | Use this runbook? |
|-----------|-------------------|
| `clusters/<name>/` missing or never committed | Yes |
| `infrastructure.tfstate` missing, empty, or from a different cluster | Yes |
| State exists and `terraform state list` shows resources | **No** — use `make cluster.<name>.destroy_force` |
| Cluster was created outside this repo (no `ManagedBy: Terraform`, different naming) | Partially — adapt inventory; ROSA delete still applies |

---

## Agent rules

1. **Operator confirmation required** before any destructive step (ROSA delete, AWS deletes). State the cluster name, region, and estimated cost (metal, NAT, GPU).
2. **Validate-first** — run inventory (Step 1) and share results before deleting anything.
3. **Step-by-step** — complete each step’s **done-when** gate before the next. On failure, diagnose and adapt; do not blindly re-run the whole pipeline.
4. **Long-running deletes** — use [tmux](../../AGENTS.md#long-running-cluster-operations-ai-operators); tee logs to `clusters/<name>/logs/<timestamp>-orphan-*.log` (create the directory if the recipe folder is gone).
5. **Do not import** into Terraform for cleanup unless the operator explicitly chooses that path — manual/AWS CLI cleanup is usually faster for sandboxes.
6. **Update this runbook** when you discover gaps during a live cleanup (note the cluster name and fix in the same PR).

---

## Variables

Set these at the start of the session:

```bash
CLUSTER_NAME="<name>"          # e.g. public-gpu
REGION="<aws-region>"          # e.g. ap-southeast-2
export AWS_REGION="${REGION}"
LOG_DIR="clusters/${CLUSTER_NAME}/logs"
mkdir -p "${LOG_DIR}"
```

---

## Step 0 — Preflight

| Check | Command | Done when |
|-------|---------|-----------|
| RHCS auth | `ocm whoami` or `rosa whoami` | Succeeds |
| AWS auth | `aws sts get-caller-identity` | Correct account |
| Cluster exists | `rosa list clusters \| grep -w "${CLUSTER_NAME}"` | Row found (or confirm already deleted → skip to Step 3) |
| Not managed by Terraform state here | `test ! -s "clusters/${CLUSTER_NAME}/infrastructure.tfstate" && echo no-state` | No usable state file |
| Operator approval | Ask explicitly | Operator confirms full teardown |

**Optional — recover state instead of orphan cleanup:** search backups, other machines, or `clusters/*/logs/*-apply.log` for `TF_DATA_DIR=.../clusters/${CLUSTER_NAME}/.terraform`. If you find a complete `infrastructure.tfstate`, restore it under `clusters/<name>/`, recreate `terraform.tfvars`, and use `make cluster.<name>.destroy_force` instead.

---

## Step 1 — Inventory (read-only)

Run and capture output before deleting anything.

### 1a. ROSA cluster

```bash
rosa describe cluster -c "${CLUSTER_NAME}" -o json | tee "${LOG_DIR}/$(date -u +%Y%m%dT%H%M%SZ)-describe.json"
rosa list machinepools -c "${CLUSTER_NAME}"
```

Record: region, `machine_cidr`, subnet IDs, OIDC endpoint URL, OpenShift version, machine pool names (note metal/GPU pools — expensive).

### 1b. VPC

```bash
# By Name tag (public network module: <cluster>-vpc)
aws ec2 describe-vpcs --region "${REGION}" \
  --filters "Name=tag:Name,Values=${CLUSTER_NAME}-vpc" \
  --query 'Vpcs[].{VpcId:VpcId,Cidr:CidrBlock}' --output table

# Fallback: CIDR from rosa describe (machine_cidr)
MACHINE_CIDR="$(rosa describe cluster -c "${CLUSTER_NAME}" -o json | jq -r '.network.machine_cidr')"
aws ec2 describe-vpcs --region "${REGION}" \
  --filters "Name=cidr,Values=${MACHINE_CIDR}" \
  --query 'Vpcs[].{VpcId:VpcId,Cidr:CidrBlock,Tags:Tags}' --output json
```

Set `VPC_ID` from the result.

### 1c. High-cost / optional feature resources

```bash
VPC_ID="<vpc-id-from-above>"

echo "=== NAT gateways (cost) ==="
aws ec2 describe-nat-gateways --region "${REGION}" \
  --filter "Name=vpc-id,Values=${VPC_ID}" \
  --query 'NatGateways[?State!=`deleted`].{Id:NatGatewayId,Subnet:SubnetId,State:State}' --output table

echo "=== VPC endpoints ==="
aws ec2 describe-vpc-endpoints --region "${REGION}" \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query 'VpcEndpoints[].{Id:VpcEndpointId,Service:ServiceName,Type:VpcEndpointType}' --output table

echo "=== EFS ==="
aws efs describe-file-systems --region "${REGION}" \
  --query "FileSystems[?contains(Name, '${CLUSTER_NAME}')].{Id:FileSystemId,Name:Name}" --output table

echo "=== S3 (control plane logs) ==="
aws s3api list-buckets --query "Buckets[?contains(Name, '${CLUSTER_NAME}')].Name" --output text

echo "=== Secrets Manager ==="
aws secretsmanager list-secrets --region "${REGION}" \
  --filters Key=name,Values="${CLUSTER_NAME}" \
  --query 'SecretList[].Name' --output text

echo "=== IAM roles (${CLUSTER_NAME}-*) ==="
aws iam list-roles --query "Roles[?starts_with(RoleName, \`${CLUSTER_NAME}\`)].RoleName" --output text | tr '\t' '\n'

echo "=== Route Server (virt / enable_route_server) ==="
aws ec2 describe-route-servers --region "${REGION}" \
  --filters "Name=vpc-id,Values=${VPC_ID}" --output table 2>/dev/null || true

echo "=== Client VPN (egress-zero / private) ==="
aws ec2 describe-client-vpn-endpoints --region "${REGION}" \
  --query "ClientVpnEndpoints[?contains(Description, '${CLUSTER_NAME}') || contains(Tags[?Key=='ClusterName'].Value | [0], '${CLUSTER_NAME}')]" --output table 2>/dev/null || true
```

### 1d. Confirm Terraform provenance (optional)

```bash
aws ec2 describe-vpcs --region "${REGION}" --vpc-ids "${VPC_ID}" \
  --query 'Vpcs[0].Tags' --output table
```

Look for `ManagedBy = Terraform` and naming like `${CLUSTER_NAME}-vpc`.

**Done when:** You have `VPC_ID`, machine pool list, and a short summary for the operator (NAT count, EFS yes/no, S3 bucket names, IAM role count).

---

## Step 2 — Day-2 / in-cluster prep (if cluster API is up)

Skip if the cluster is already deleted or unreachable.

| Recipe | Action before ROSA delete |
|--------|---------------------------|
| **Hub/spoke (ACM)** | Unregister spoke: `make cluster.<spoke>.teardown-spoke HUB_CREDENTIALS_SECRET=...` |
| **Virt / metal** | Confirm operator accepts long delete time; no extra in-cluster steps required for orphan path |
| **PCA / GPU workloads** | From PCA clone: `make undeploy-existing-openshift` (reduces stuck PVC/LB noise; cluster delete still works without it) |
| **GitOps** | No manual Argo teardown required — cluster delete removes the data plane |

**Done when:** Operator confirms prep is sufficient or skipped.

---

## Step 3 — Delete ROSA cluster

Use tmux for the wait (~20–45 min; longer with metal).

```bash
LOG="${LOG_DIR}/$(date -u +%Y%m%dT%H%M%SZ)-rosa-delete.log"
bash -lc "set +e; rosa delete cluster -c '${CLUSTER_NAME}' -y --watch 2>&1 | tee -a '${LOG}'; EC=\$?; echo \"ROSA_DELETE_EXIT:\${EC}\" | tee -a '${LOG}'; exit \${EC}"
```

If delete fails or stalls:

1. Read the tail of the log for the blocking resource.
2. Retry once without flags.
3. Only if the operator approves: `rosa delete cluster -c "${CLUSTER_NAME}" -y --best-effort --watch` (may leave more AWS orphans — document what was skipped).

**Done when:**

- `rosa list clusters` no longer lists `${CLUSTER_NAME}` (or state is `uninstalling` → wait).
- `ROSA_DELETE_EXIT:0` in the log.

ROSA removes the HCP control plane, worker nodes, and **most** operator IAM roles. It does **not** remove Terraform-managed VPC, NAT, EFS, S3, cert-manager/EFS/cloudwatch roles, OIDC provider, or Secrets Manager secrets from this repo’s modules.

At delete start, ROSA prints leftover IAM/OIDC cleanup commands — **save them** (also in `${LOG_DIR}/*-rosa-delete.log`). Typical pattern after uninstall completes:

```bash
# Non-interactive: --mode auto is required ( -y alone prompts for auto/manual and fails in scripts)
rosa delete operator-roles --prefix "${CLUSTER_NAME}" --mode auto -y
rosa delete oidc-provider --oidc-config-id <id-from-delete-output> --mode auto -y
```

The OIDC config id is the path segment after `oidc.op1.openshiftapps.com/` (save from Step 1 `describe.json` if the cluster is already gone).

**Tmux note:** If the tmux MCP server uses a different socket than your shell, `find-session` may return “not found” while `tmux list-sessions` works. Prefer shell tmux for orphan cleanup coordinators, or pass the MCP `socket` override consistently.

---

## Step 4 — Delete EFS (if present)

Only if Step 1 found an EFS filesystem for this cluster.

```bash
FS_ID="<fs-id>"
for MT in $(aws efs describe-mount-targets --region "${REGION}" --file-system-id "${FS_ID}" \
  --query 'MountTargets[].MountTargetId' --output text); do
  aws efs delete-mount-target --region "${REGION}" --mount-target-id "${MT}"
done
# Wait until describe-mount-targets returns empty
aws efs delete-file-system --region "${REGION}" --file-system-id "${FS_ID}"
```

**Done when:** `aws efs describe-file-systems --file-system-id "${FS_ID}"` returns not found.

---

## Step 5 — Delete S3 control-plane log buckets

Control-plane log buckets use **versioning** (`aws_s3_bucket_versioning` in the cluster module). `aws s3 rb --force` can run for hours and appear stuck — use batched `delete_objects` including **all object versions and delete markers**:

```bash
for BUCKET in $(aws s3api list-buckets --query "Buckets[?contains(Name, '${CLUSTER_NAME}')].Name" --output text); do
  export BUCKET
  python3 <<'PY'
import boto3, os
bucket = os.environ["BUCKET"]
region = os.environ.get("AWS_REGION", "ap-southeast-2")
s3 = boto3.client("s3", region_name=region)
paginator = s3.get_paginator("list_object_versions")
deleted = 0
for page in paginator.paginate(Bucket=bucket):
    objs = [
        {"Key": v["Key"], "VersionId": v["VersionId"]}
        for v in page.get("Versions", []) + page.get("DeleteMarkers", [])
    ]
    for i in range(0, len(objs), 1000):
        batch = objs[i:i+1000]
        if batch:
            s3.delete_objects(Bucket=bucket, Delete={"Objects": batch, "Quiet": True})
            deleted += len(batch)
print(f"deleted {deleted} versions from {bucket}")
s3.delete_bucket(Bucket=bucket)
print("bucket deleted")
PY
done
```

Run in tmux; a 3-week control-plane log bucket may have **2M+ versions** (~60–90 min). Do not rely on verbose `aws s3 rm --recursive` or a single `aws s3 rb --force` in automation.

**Done when:** No buckets matching `${CLUSTER_NAME}` remain.

---

## Step 6 — Route Server (only if `enable_route_server`)

If Step 1 found route server resources in the VPC:

1. Delete route server endpoints (all subnets).
2. Disassociate / delete route server VPC association.
3. Delete the route server.
4. Delete Secrets Manager secret `{CLUSTER_NAME}-bgp-config` if present.
5. Delete IAM role/policy `${CLUSTER_NAME}` BGP operator resources (see IAM step).

Reference: [Route Server module](../modules/route-server.md), `scripts/cluster/cleanup-route-server-bgp-peers.sh` (requires live cluster — not usable post-delete; manual AWS API/console only).

**Done when:** `aws ec2 describe-route-servers --filters Name=vpc-id,Values=${VPC_ID}` returns empty.

---

## Step 7 — Client VPN (only if `enable_client_vpn`)

If Step 1 found a Client VPN endpoint:

1. Disassociate target networks.
2. Delete authorization rules.
3. Delete the Client VPN endpoint.
4. Delete associated ACM certs / CloudWatch log group if tagged for this cluster.

Reference: [Client VPN module](../modules/client-vpn.md).

**Done when:** No Client VPN endpoint remains for this cluster.

---

## Step 8 — Tear down VPC networking

Delete in **dependency order**. `VPC_ID` must be set.

```bash
# 8a. NAT gateways (largest cost leak if forgotten)
for NAT in $(aws ec2 describe-nat-gateways --region "${REGION}" \
  --filter "Name=vpc-id,Values=${VPC_ID}" \
  --query 'NatGateways[?State!=`deleted`].NatGatewayId' --output text); do
  aws ec2 delete-nat-gateway --region "${REGION}" --nat-gateway-id "${NAT}"
done
# Wait until all show State=deleted (poll every 30s)
```

```bash
# 8b. Release Elastic IPs tied to the VPC
for ALLOC in $(aws ec2 describe-addresses --region "${REGION}" \
  --filters "Name=domain,Values=vpc" \
  --query "Addresses[?NetworkInterfaceOwnerId!=\`amazon-elb\`].AllocationId" --output text); do
  # Optional: filter by tag or association to VPC subnets — verify before release
  aws ec2 release-address --region "${REGION}" --allocation-id "${ALLOC}" 2>/dev/null || true
done
```

Safer EIP release (only EIPs on this VPC’s NAT tags):

```bash
aws ec2 describe-nat-gateways --region "${REGION}" \
  --filter "Name=vpc-id,Values=${VPC_ID}" \
  --query 'NatGateways[].NatGatewayAddresses[].AllocationId' --output text | while read -r ALLOC; do
  [ -n "${ALLOC}" ] && aws ec2 release-address --region "${REGION}" --allocation-id "${ALLOC}" 2>/dev/null || true
done
```

```bash
# 8c. VPC interface endpoints (delete, then wait — ENIs linger in "deleting" state)
for VPCE in $(aws ec2 describe-vpc-endpoints --region "${REGION}" \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query 'VpcEndpoints[].VpcEndpointId' --output text); do
  aws ec2 delete-vpc-endpoints --region "${REGION}" --vpc-endpoint-ids "${VPCE}"
done
for i in $(seq 1 24); do
  COUNT=$(aws ec2 describe-vpc-endpoints --region "${REGION}" \
    --filters "Name=vpc-id,Values=${VPC_ID}" --query 'length(VpcEndpoints)' --output text)
  [ "${COUNT}" = "0" ] && break
  sleep 15
done
```

Do **not** delete VPC until `describe-vpc-endpoints` returns zero endpoints — otherwise `delete-vpc` fails with `DependencyViolation` (interface ENIs still attached).

```bash
# 8d. Detach and delete internet gateway
IGW=$(aws ec2 describe-internet-gateways --region "${REGION}" \
  --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
  --query 'InternetGateways[0].InternetGatewayId' --output text)
if [ "${IGW}" != "None" ] && [ -n "${IGW}" ]; then
  aws ec2 detach-internet-gateway --region "${REGION}" --internet-gateway-id "${IGW}" --vpc-id "${VPC_ID}"
  aws ec2 delete-internet-gateway --region "${REGION}" --internet-gateway-id "${IGW}"
fi
```

```bash
# 8e. Delete non-default security groups (retry after ENIs gone)
for SG in $(aws ec2 describe-security-groups --region "${REGION}" \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text); do
  aws ec2 delete-security-group --region "${REGION}" --group-id "${SG}" 2>/dev/null || true
done
```

```bash
# 8f. Delete subnets, then VPC
for SUB in $(aws ec2 describe-subnets --region "${REGION}" \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query 'Subnets[].SubnetId' --output text); do
  aws ec2 delete-subnet --region "${REGION}" --subnet-id "${SUB}" 2>/dev/null || true
done
aws ec2 delete-vpc --region "${REGION}" --vpc-id "${VPC_ID}"
```

If `delete-vpc` fails:

- Run `aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=${VPC_ID}` — delete lingering ENIs.
- Re-run security group and subnet deletion.
- Check for leftover load balancers: `aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='${VPC_ID}']"`.

**Done when:** `aws ec2 describe-vpcs --vpc-ids "${VPC_ID}"` returns invalid VPC ID.

ROSA uninstall may leave a cluster security group (e.g. `sg-08c4de99c4b172725`) with `DependencyViolation` during guest teardown — delete it in Step 8f after ENIs are gone.

---

## Step 9 — IAM and OIDC cleanup

### 9a. OIDC provider and operator roles (prefer ROSA CLI)

After cluster delete, use the commands ROSA prints in the delete log (Step 3). **Always pass `--mode auto`** in scripts:

```bash
rosa delete operator-roles --prefix "${CLUSTER_NAME}" --mode auto -y
rosa delete oidc-provider --oidc-config-id <id> --mode auto -y
```

Manual fallback if ROSA CLI is unavailable:

```bash
OIDC_URL="$(jq -r '.aws.sts.oidc_endpoint_url // empty' "${LOG_DIR}"/*-describe.json)"
# OIDC_HOST="${OIDC_URL#https://}" → delete via aws iam delete-open-id-connect-provider
```

### 9b. IAM roles (`${CLUSTER_NAME}-*` and `${CLUSTER_NAME}-HCP-ROSA-*`)

```bash
for ROLE in $(aws iam list-roles --query "Roles[?starts_with(RoleName, \`${CLUSTER_NAME}\`)].RoleName" --output text); do
  echo "Deleting role: ${ROLE}"
  for POLICY_ARN in $(aws iam list-attached-role-policies --role-name "${ROLE}" \
    --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name "${ROLE}" --policy-arn "${POLICY_ARN}"
  done
  for INLINE in $(aws iam list-role-policies --role-name "${ROLE}" --query 'PolicyNames[]' --output text); do
    aws iam delete-role-policy --role-name "${ROLE}" --policy-name "${INLINE}"
  done
  aws iam delete-role --role-name "${ROLE}" 2>/dev/null || echo "WARN: could not delete ${ROLE} — check console"
done
```

### 9c. Customer-managed IAM policies (optional sweep)

```bash
for POLICY_ARN in $(aws iam list-policies --scope Local \
  --query "Policies[?starts_with(PolicyName, \`${CLUSTER_NAME}\`)].Arn" --output text); do
  aws iam delete-policy --policy-arn "${POLICY_ARN}" 2>/dev/null || true
done
```

### 9d. KMS keys (only if recipe used internal keys)

Search aliases: `alias/${CLUSTER_NAME}-*` or tags. Schedule deletion (minimum 7-day waiting period):

```bash
aws kms list-aliases --query "Aliases[?contains(AliasName, '${CLUSTER_NAME}')].{Alias:AliasName,KeyId:TargetKeyId}" --output table
# aws kms schedule-key-deletion --key-id <id> --pending-window-in-days 7
```

**Done when:** `aws iam list-roles --query "Roles[?starts_with(RoleName, \`${CLUSTER_NAME}\`)]"` returns empty (except roles AWS recreates for other clusters).

---

## Step 10 — Secrets Manager

```bash
for SECRET in $(aws secretsmanager list-secrets --region "${REGION}" \
  --filters Key=name,Values="${CLUSTER_NAME}" \
  --query 'SecretList[].Name' --output text); do
  aws secretsmanager delete-secret --region "${REGION}" --secret-id "${SECRET}" --force-delete-without-recovery
done
```

Include `{CLUSTER_NAME}-bgp-config` and `{CLUSTER_NAME}-credentials`.

**Done when:** No secrets whose names start with `${CLUSTER_NAME}` remain.

---

## Step 11 — Final verification

```bash
echo "ROSA:"; rosa list clusters 2>/dev/null | grep -w "${CLUSTER_NAME}" || echo "  (not listed — OK)"

echo "VPC:"; aws ec2 describe-vpcs --region "${REGION}" \
  --filters "Name=tag:Name,Values=${CLUSTER_NAME}-vpc" --query 'Vpcs[].VpcId' --output text || true

echo "EFS:"; aws efs describe-file-systems --region "${REGION}" \
  --query "FileSystems[?contains(Name, '${CLUSTER_NAME}')].FileSystemId" --output text

echo "S3:"; aws s3api list-buckets --query "Buckets[?contains(Name, '${CLUSTER_NAME}')].Name" --output text

echo "IAM roles:"; aws iam list-roles --query "Roles[?starts_with(RoleName, \`${CLUSTER_NAME}\`)].RoleName" --output text

echo "Secrets:"; aws secretsmanager list-secrets --region "${REGION}" \
  --filters Key=name,Values="${CLUSTER_NAME}" --query 'SecretList[].Name' --output text
```

**Done when:** All checks empty. Log `ORPHAN_CLEANUP_EXIT:0` to the session log.

Spot-check the AWS console: **VPC → NAT gateways**, **EFS**, **EC2 → Instances** (metal/GPU), **IAM → Roles**.

---

## Resource checklist (this repo’s Terraform modules)

Use during Step 1 to ensure nothing is missed. Not every row applies to every recipe.

| Module / feature | Typical AWS resources | Naming pattern |
|------------------|----------------------|----------------|
| `network-public` | VPC, subnets, IGW, NAT, EIPs, route tables, VPC endpoints, endpoint SG | `${CLUSTER_NAME}-vpc`, `${CLUSTER_NAME}-*` |
| `network-private` | Same without public subnets; may add more endpoints | Same |
| `iam` | Account roles, operator roles, OIDC provider | `${CLUSTER_NAME}-HCP-ROSA-*`, `${CLUSTER_NAME}-openshift-*` |
| `cluster` | Secrets Manager credentials, optional API endpoint SG rules | `${CLUSTER_NAME}-credentials` |
| `enable_efs` | EFS + mount targets + SG rules | `${CLUSTER_NAME}-rosa-efs` |
| Control plane logs | S3 bucket, optional CloudWatch log group | `${CLUSTER_NAME}-control-plane-logs-*` |
| `enable_cert_manager_iam` | IAM role/policy | `${CLUSTER_NAME}-rosa-cert-manager` |
| `enable_cloudwatch_logging` | IAM role/policy | `${CLUSTER_NAME}-rosa-cloudwatch-*` |
| `enable_secrets_manager_iam` | IAM role/policy | `${CLUSTER_NAME}-rosa-secretsmanager-*` |
| `enable_route_server` | Route server, endpoints, propagation, BGP secret, BGP IAM | `{CLUSTER_NAME}-bgp-config` |
| `enable_client_vpn` | Client VPN endpoint, ACM certs, log group | Tags / description |
| `enable_bastion` | EC2 instance, SG, key pair | `${CLUSTER_NAME}-bastion` |
| Internal KMS | KMS keys + aliases | `alias/${CLUSTER_NAME}-*` |
| `enable_autonode` | Karpenter-related IAM, subnet tags | `${CLUSTER_NAME}-autonode-*` |

---

## After cleanup

1. If recreating the cluster in-repo: copy a recipe `terraform.tfvars` → `clusters/<name>/`, set `cluster_name`, run `make cluster.<name>.init` (fresh state).
2. If this runbook was wrong or incomplete: update this file and link from [AGENTS.md](../../AGENTS.md).
3. Do **not** commit logs under `clusters/*/logs/`.

---

## See also

- [Scripts](scripts.md) — normal `destroy` / `destroy_force` path
- [Enablement — teardown](../deployment/enablement.md)
- [Agent E2E validation](../../AGENTS.md#agent-guided-end-to-end-e2e-cluster-validation)
- [Long-running operations (tmux)](../../AGENTS.md#long-running-cluster-operations-ai-operators)
