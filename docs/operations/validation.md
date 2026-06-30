# Validation Scripts

Pre-deployment validation for ROSA HCP clusters. These scripts check account readiness and VPC configuration before `terraform apply`.

## Scripts

| Script | Purpose |
|--------|---------|
| [`account.sh`](https://github.com/rh-mobb/vp-terraform-rosa/blob/main/scripts/validate/account.sh) | Operator tools, AWS creds, ROSA linking, quotas, URL connectivity |
| [`byo-network.sh`](https://github.com/rh-mobb/vp-terraform-rosa/blob/main/scripts/validate/byo-network.sh) | VPC DNS, subnets, tags, endpoints, route tables |
| [`prereqs.sh`](https://github.com/rh-mobb/vp-terraform-rosa/blob/main/scripts/validate/prereqs.sh) | Combined validation driven by cluster `terraform.tfvars` |

## Makefile usage

```bash
# Account only (before init)
make cluster.public.validate-account

# VPC only (BYO or after terraform output exists)
make cluster.my-byo.validate-network

# Account + network (reads tfvars)
make cluster.egress-zero.validate-prereqs
```

## Direct usage

```bash
# Account validation
./scripts/validate/account.sh --region ap-southeast-2

# Skip URL checks (restricted CI networks)
./scripts/validate/account.sh --region us-east-1 --skip-connectivity

# BYO VPC validation
./scripts/validate/byo-network.sh \
  --vpc-id vpc-0abc123 \
  --region ap-southeast-2 \
  --zero-egress \
  --multi-az

# Full cluster prereqs
./scripts/validate/prereqs.sh egress-zero
```

## When to run

| Phase | Command |
|-------|---------|
| Before first `init` | `validate-account` |
| BYO VPC handoff | `validate-network` with `--vpc-id` |
| Before `apply` | `validate-prereqs` |

## Exit codes

- `0` — all checks passed
- `1` — one or more FAIL items; fix before proceeding

WARN items are informational and do not fail the script.

## Dependencies

- `aws`, `jq`, `curl` (required)
- `rosa` (required for account linking checks)
- AWS credentials and (for ROSA checks) `rosa login` or equivalent

## Related

- [Account Prerequisites](../prerequisites/account.md)
- [BYO Network Requirements](../prerequisites/byo/network.md)
- [Choose Your Path](../prerequisites/index.md)

## Reference

Scripts adapted from [`reference/ROSAHcpZeroEgressPrerequisites/scripts/`](../../reference/ROSAHcpZeroEgressPrerequisites/scripts/).
