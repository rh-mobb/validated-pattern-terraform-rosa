# BYO subnet tag lifecycle

<!--
Purpose: Route operators to one read-only check and one explicitly approved cleanup path.
What this is not: This guide is not a VPC-wide scanner or an automatic destroy hook.
Prerequisites: Explicit BYO subnet ids, AWS read credentials, and a chosen manual or Jenkins path.
Authoritative references: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Using_Tags.html
-->

ROSA HCP adds `kubernetes.io/cluster/<cluster-id>=shared` to BYO subnets.
Those keys consume EC2's 50 user-tag limit. In observed ROSA HCP 4.20.30
destroy runs, the service did not reliably remove its ownership keys. This is
observed behavior, not vendor-documented behavior.

`scripts/operations/byo-subnet-tags.py` has two verbs:

| Verb | Purpose | Mutation boundary |
|---|---|---|
| `check` | Report user-tag count, remaining slots, and cluster keys for each explicitly named subnet. | Read-only under every option. |
| `clean` | Classify exact cluster keys and report deletion candidates. | Dry-run unless `--apply` is supplied; automation must also supply `--yes`. |

Neither verb discovers subnets. Enumerate the intended subnet ids before
calling the tool. There is no VPC-wide or account-wide mode.

## Enable the pre-create check

Set `check_subnet_tag_capacity = true` in the cluster's `terraform.tfvars` to
include the read-only capacity check in both `make cluster.<name>.validate`
and `make cluster.<name>.validate-network`. It defaults to off; removing the
key or setting it to `false` disables it. The check runs when the network
validator has a VPC to inspect and uses its selected private subnets.

An unreadable or inconsistent EC2 tag read fails the opted-in validation, even
when the failure is transient. It is never reported as free tag capacity.
The delegated `check` call uses only `--region` and repeated `--subnet-id`
arguments with the existing AWS read credentials. `--ocm-token-file` is a
`clean` option only; do not add an OCM token to this validation path. Full
`validate` still runs its existing account checks.

See [validation usage](validation.md#optional-subnet-tag-capacity-check) for
the tfvars example and VPC prerequisites. Cleanup remains a separate manual
or explicitly enabled housekeeping action.

## Choose a run path

- [Manual workstation](byo-subnet-tags-manual.md): ambient AWS credentials,
  an owner-only OCM token file or explicit per-id assertions, and an interactive
  deletion confirmation.
- [Jenkins on Kubernetes](byo-subnet-tags-jenkins.md): AWS credentials through
  IRSA, an OCM token mounted as a file, explicit non-interactive approval, and
  an archived JSON report.

Both paths execute the same Python file. They differ only in credential source,
approval mechanism, and report destination; those are configuration choices,
not different security postures.

## Safety contract

The tool requires `DescribeTags` and `DescribeSubnets` to return identical tag
maps before it reports or mutates. This guards against the observed lag of the
EC2 tag index. A disagreement is a refusal, not an empty result.

For `clean`, every cluster id is one of four report states:

| State | Meaning | Deletable |
|---|---|---|
| `absent` | OCM answered and returned no exact cluster id. | Yes, marked `PROVED`. |
| `present` | OCM returned the exact cluster id. | No, under every option. |
| `unobserved` | OCM could not be read, including authentication, rate-limit, and timeout failures. | No. |
| `asserted-absent` | OCM was unobserved and the caller named that exact id with `--assume-absent`. | Yes, marked `ASSERTED`. |

An assertion fills an evidence gap; it cannot override a `present` result.
There is no `--force` or global skip.

An `absent` result is authoritative only within the OCM token's complete
visibility. A credential narrower than every ROSA organization or account that
can use the supplied subnets cannot prove absence; treat that result as an
evidence gap and establish each id independently before asserting it.

Before deletion, the tool writes every complete subnet tag map to an owner-only
snapshot. It then re-reads the maps, deletes only exact approved keys, and
requires the final maps to equal the snapshots byte-for-byte except for those
keys. Any change to another key or value is a failure and the snapshot path is
reported. The tool never restores a tag automatically.

## How cluster validation resolves its inputs

Set `check_subnet_tag_capacity = true` in `clusters/<name>/terraform.tfvars`,
then run either command from the repository root:

```bash
make cluster.<name>.validate          # account and network prerequisites
make cluster.<name>.validate-network  # network only
```

The switch defaults to `false`. Both commands use `get_tfvar` from
`scripts/common.sh`, which reads the first matching key at the start of a line
in that single file. It accepts bare `true` or quoted `"true"`; use the bare
boolean for Terraform. A missing file, absent or misspelled key, or any parsed
value other than `true` leaves the check off. This helper is not a full HCL
parser: indented keys and nested blocks are not searched. There is no separate
environment override or `-var` option for this validation switch.

| Key | Default | `validate` | `validate-network` |
| --- | --- | --- | --- |
| `region` | `us-east-1` | `--region` | `--region` |
| `existing_vpc_id` | empty | Used only when `network_type = "existing"` | Used whenever set |
| `network_type` | `public` | Selects supplied or Terraform-managed VPC | Ignored |
| `multi_az` | `true` | Selects `--multi-az` or `--single-az` | Same |
| `zero_egress` | `false` | Enables endpoint checks | Same |
| `control_plane_log_cloudwatch_enabled` | `false` | Adds `--require-cloudwatch` | Ignored |
| `check_subnet_tag_capacity` | `false` | Adds `--check-subnet-tag-capacity` when true | Same |

`validate` calls `prereqs.sh`. For `network_type = "existing"`, it requires
`existing_vpc_id`; an empty value is an error. Otherwise it ignores that input
and, only when the cluster's Terraform initialization metadata exists, reads
`terraform output -raw vpc_id`. No initialization metadata, an empty output,
or `null` means network validation is skipped.

`validate-network` does not read `network_type`. It uses `existing_vpc_id`
first, then tries the same Terraform output only if initialization metadata
exists. It skips network validation if neither produces a VPC id. For a BYO
VPC, set both `network_type = "existing"` and your `existing_vpc_id` so the two
commands choose the same network. Neither command creates a VPC for this check.

When capacity checking was requested but no VPC was resolved, both commands
also print:

```text
Subnet tag capacity: requested, but network validation was skipped (no VPC id resolved) — check did not run
```

This is informational, not a validation failure: validation before init remains
supported. A skipped check is not evidence of capacity. Look for the `SUBNET`
lines, not just a successful exit. With the switch off, no extra notice or
capacity read is added.

The network validator discovers all subnets in the resolved VPC for which
`MapPublicIpOnLaunch` is `false`, and passes their ids to `check`. That is its
definition of private; it does not infer privacy from names, tags, or routes.
It does not use `existing_private_subnet_ids` to narrow the check. In a shared
VPC, its selection may therefore include subnets this cluster will not use.
For an explicit subset, use the standalone tool's repeated `--subnet-id` option.

The validator exports the resolved `region` as `AWS_DEFAULT_REGION`; the
capacity tool also passes `--region` on its two AWS CLI calls. Use the region
that owns the VPC. No profile, access key, or secret key is passed by these
scripts: AWS CLI resolves credentials through its normal credential chain.
The added capacity block requires `ec2:DescribeTags` and
`ec2:DescribeSubnets`, with no write or cluster access and no OCM token.
`--ocm-token-file` is for `clean` alone. The surrounding network and account
checks retain their own permissions.

See [validation output and exit behavior](validation.md#read-the-per-subnet-output):
1–5 remaining slots produce `WARNING` but still pass; zero slots fail.
Unreadable or inconsistent tag reads fail validation, never report free
capacity; after resolving a transient AWS error, re-run the target.
Ownership keys are reported without classifying whether their clusters exist.

## Evidence boundary

Live tests on ROSA HCP 4.20.30 established exact-key deletion, complete-map
snapshot and byte-equality verification, user-tag arithmetic excluding `aws:`
keys, and recovered-slot counts of 43, 45, and 45. They also observed ownership
keys surviving ROSA destroy.

Batch candidate discovery, three-state inventory classification,
`--assume-absent`, and the Jenkins runner are unit-tested only. They have not
been exercised as a live batch workflow.

The tool is intentionally not wired into destroy. Destroy has the strongest
cluster-to-tag identity join, but safe unattended execution required credential
refresh, retry, independent checks, and restoration machinery. A human-run or
explicitly enabled housekeeping job can expose each evidence decision directly
and remain substantially smaller.

AWS documents the [EC2 tag limit and reserved `aws:` prefix](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Using_Tags.html#tag-restrictions).
