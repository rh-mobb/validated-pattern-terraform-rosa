# Validation Scripts

Pre-deployment validation for ROSA HCP clusters. Checks account readiness and VPC configuration (when applicable) before `terraform apply`.

## Makefile usage

```bash
# Full validation (account + network from tfvars) — primary entry point
make cluster.public.validate

# Subsets (optional)
make cluster.public.validate-account   # tools, OCM role, quotas, connectivity
make cluster.my-byo.validate-network     # VPC/subnets/endpoints only

# Terraform syntax (separate from prerequisites)
make cluster.public.validate-terraform
```

`validate-prereqs` is an alias for `validate` (backward compatible).

## Optional subnet tag capacity check

<!--
Purpose: Enable the same read-only capacity check from both validation entry points.
What this is not: No cleanup, VPC creation, or new OCM credential is introduced.
Prerequisites: A VPC that network validation can inspect and existing AWS read credentials.
Authoritative references: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Using_Tags.html#tag-restrictions
-->

Set this in the cluster's `clusters/<name>/terraform.tfvars` to enable the
read-only check. Run Make from the repository root. Both
`make cluster.<name>.validate` (including its `validate-prereqs` alias, through
`prereqs.sh`) and `make cluster.<name>.validate-network` (directly) reach it:

```hcl
# Covers: check_subnet_tag_capacity
# Does: Adds the read-only tag capacity check to both validation entry points.
# Why: Enable before cluster creation to detect exhausted user-tag capacity.
# Change: Remove the key or set false to return to the default-off behavior.
# Trap: An unreadable EC2 tag result fails validation, never reports free capacity.
# Evidence: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Using_Tags.html#tag-restrictions
check_subnet_tag_capacity = true
```

The switch is off when the file or key is absent, or the parsed value is not
`true`. The validation reader accepts both bare `true` and quoted `"true"`;
prefer the bare boolean shown above. Terraform still type-checks the input,
so arbitrary strings are not valid Terraform boolean values.

The check runs only when network validation resolves a VPC. For a supplied BYO
VPC, `validate` requires both `network_type = "existing"` and
`existing_vpc_id`; `validate-network` uses `existing_vpc_id` regardless of
`network_type`. Otherwise each can read an existing Terraform-managed VPC.
Neither creates a VPC to check. The network validator selects the private
subnets; the capacity block does not remove tags or run during destroy.

If the switch is true but no VPC is resolved, the command explicitly prints
`Subnet tag capacity: requested, but network validation was skipped (no VPC id resolved) — check did not run`.
This is a notice, not a failure, so validation before initialization remains
possible. A successful exit without `SUBNET` lines does not prove capacity.
See [the input resolution rules](byo-subnet-tags.md#how-cluster-validation-resolves-its-inputs)
for the complete key table, subnet selection, region, and credential handling.

### Read the per-subnet output

For each selected subnet, the tool prints a `SUBNET` line followed by an
indented `CLUSTER_KEY` line for every cluster ownership key it finds. This
invented example shows a warning; replace the angle-bracket placeholders when
interpreting your own output:

```text
SUBNET <subnet-id> user_tags=47 remaining=3 status=WARNING
  CLUSTER_KEY kubernetes.io/cluster/<cluster-id-a>
  CLUSTER_KEY kubernetes.io/cluster/<cluster-id-b>
```

`user_tags` counts all user-defined tags, not just ownership keys. AWS-reserved
`aws:` tags do not count against the 50-user-tag limit. `remaining` is the
number of free user-tag slots.

| Remaining slots | `SUBNET` status | Capacity tool exit | Effect on validation |
| --- | --- | --- | --- |
| 6 or more | `OK` | `0` | This check passes. |
| 1–5 | `WARNING` | `0` | This check still passes; plan for tag capacity before more cluster builds. |
| 0 | `FULL` | `2` | This check fails validation. |

The tool exits `2` if any selected subnet is full; otherwise it exits `0`
when the reads succeed and agree. Other network checks can still fail the
validation target independently.

Read the `SUBNET` lines, not just the validator's summary. Its success line,
`Subnet tag capacity: all private subnets have free user-tag slots`, also
appears when a subnet has only 1–5 slots left. A `PASS` summary therefore does
not mean every subnet is above the warning threshold.

Unreadable EC2 tags (including transient AWS errors) or inconsistent tag reads
also fail validation. An unreadable result is never reported as free capacity.
Investigate the reported error and re-run the validation target after access
or service availability recovers. A transient read error can fail
`make cluster.<name>.validate` when this switch is enabled.

An ownership key's presence does not establish that its cluster still exists.
`check` reports keys, classifies none of them, and retains them all. Its output
is not permission to remove a tag.

### Permissions and scope

The capacity block needs only `ec2:DescribeTags` and `ec2:DescribeSubnets`, using
the existing AWS credential binding. It requires no write permission, cluster
access, kubeconfig, or owning-inventory token. The delegated `check` call takes
`--region` and repeated `--subnet-id` arguments. `--ocm-token-file` belongs to
the separate `clean` verb only; do not pass it into capacity validation.

Those two permissions describe the added capacity block, not the whole
validation target. `validate-network` retains its other VPC, subnet, endpoint
and routing checks; full `validate` also retains its existing account checks.
See [BYO subnet tag lifecycle](byo-subnet-tags.md) for reports and manual paths.

## Scripts

| Script | Purpose |
|--------|---------|
| [`account.sh`](https://github.com/rh-mobb/validated-pattern-terraform-rosa/blob/main/scripts/validate/account.sh) | Operator tools, AWS creds, ROSA/OCM linking, quotas, URL connectivity |
| [`byo-network.sh`](https://github.com/rh-mobb/validated-pattern-terraform-rosa/blob/main/scripts/validate/byo-network.sh) | VPC DNS, subnets, tags, endpoints, route tables |
| [`prereqs.sh`](https://github.com/rh-mobb/validated-pattern-terraform-rosa/blob/main/scripts/validate/prereqs.sh) | Combined validation driven by cluster `terraform.tfvars` |

## Direct usage

```bash
# Account validation only
./scripts/validate/account.sh --region ap-southeast-2

# Skip URL checks (restricted CI networks)
./scripts/validate/account.sh --region us-east-1 --skip-connectivity

# BYO VPC validation
./scripts/validate/byo-network.sh \
  --vpc-id vpc-0abc123 \
  --region ap-southeast-2 \
  --zero-egress \
  --multi-az

# Full cluster validation (same as make cluster.<name>.validate)
./scripts/validate/prereqs.sh public
```

## When to run

| Phase | Command |
|-------|---------|
| Before `init` / `apply` | `make cluster.<name>.validate` |
| BYO VPC handoff only | `make cluster.<name>.validate-network` |
| Account/tools check only | `make cluster.<name>.validate-account` |

Network validation runs automatically when:

- `network_type = existing` and `existing_vpc_id` is set (BYO), or
- Terraform is initialized and `vpc_id` output exists (post-init full-stack)

## What is not checked

- **Per-cluster HCP account roles** — created by `module.iam` on `terraform apply`
- **`rosa verify permissions`** — non-STS clusters only
- **User role** — OCM web console only

## Exit codes

- `0` — all checks passed
- `1` — one or more FAIL items; fix before proceeding

WARN and INFO items are informational and do not fail the script.

## Dependencies

- `aws`, `jq`, `curl` (required)
- `rosa` >= 1.2.64 (required for OCM role checks)
- AWS credentials and `rosa login` (or OCM token)

## Related

- [Account Prerequisites](../prerequisites/account.md)
- [BYO Network Requirements](../prerequisites/byo/network.md)
- [Choose Your Path](../prerequisites/index.md)

## Reference

Validation patterns adapted from Red Hat zero-egress ROSA HCP prerequisite checks.
