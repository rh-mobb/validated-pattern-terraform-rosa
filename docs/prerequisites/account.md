# Account Prerequisites

Layer **0** — required for every deployment path (full-stack and BYO).

## AWS account

| Requirement | Notes |
|-------------|-------|
| Blank or dedicated AWS account | SCPs must allow ROSA IAM, EC2, ELB, S3, STS permissions |
| AWS CLI credentials | Configured on the operator machine or CI runner |
| Service quotas | See [Service quotas](#service-quotas) below |

Verify permissions:

```bash
rosa verify permissions
rosa verify quota --region=<your-region>
```

Or use the validation script:

```bash
./scripts/validate/account.sh --region us-east-1
# Or via Makefile:
make cluster.public.validate-account
```

## Service quotas

Minimum quotas for ROSA HCP (check your target region):

| Quota | Service | Minimum recommended |
|-------|---------|---------------------|
| Running On-Demand Standard instances (vCPUs) | EC2 | **100 vCPUs** (production headroom) |
| EBS gp3 storage (TiB) | EBS | 1 TiB (default often sufficient) |
| Classic Load Balancers | ELB | 20 |

Check current quota:

```bash
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-1216C47A \
  --region <region>
```

Request increase if needed (can take 1–5 business days):

```bash
aws service-quotas request-service-quota-increase \
  --service-code ec2 \
  --quota-code L-1216C47A \
  --desired-value 100 \
  --region <region>
```

## Red Hat account and ROSA activation

### One-time Marketplace and account linking

All steps must complete before cluster creation. Skipping any step causes `billing account not linked to organization at the aws marketplace` errors.

1. **Enable ROSA** — [AWS Console → ROSA](https://console.aws.amazon.com/rosa/) → Get started
2. **Subscribe to ROSA HCP** — [HCP Marketplace listing](https://aws.amazon.com/marketplace/pp/prodview-juiwfhpeizxro) (not Classic ROSA)
3. **Link AWS and Red Hat accounts** — AWS ROSA console → Continue to Red Hat → Connect accounts
4. **Create OCM role** (if missing):

   ```bash
   rosa login --token="<OCM_TOKEN>"
   rosa create ocm-role --admin --mode auto --yes
   rosa list ocm-role   # Linked=Yes, Admin=Yes
   ```

5. **Create user role** (if missing):

   ```bash
   rosa create user-role --mode auto --yes
   rosa list user-role  # Linked=Yes
   ```

6. **Verify ELB service-linked role**:

   ```bash
   aws iam get-role --role-name AWSServiceRoleForElasticLoadBalancing
   # If missing:
   aws iam create-service-linked-role --aws-service-name elasticloadbalancing.amazonaws.com
   ```

### RHCS authentication for Terraform

Use a **service account** for production and CI/CD — see [Authentication](../getting-started/authentication.md).

Personal offline tokens (`RHCS_TOKEN`) are acceptable for local testing only.

## Operator tooling

| Tool | Minimum | Purpose |
|------|---------|---------|
| Terraform | >= 1.5.0 | Infrastructure |
| AWS CLI | v2 | AWS API |
| ROSA CLI | >= 1.2.48 | Account linking, admin user |
| `oc` | >= 4.17 | Cluster operations |
| `helm`, `jq` | latest | GitOps bootstrap |
| `curl` | any | Validation connectivity checks |

## Firewall allowlist

If the operator machine is behind egress filtering, allow HTTPS (443) to:

| Domain | Purpose |
|--------|---------|
| `sso.redhat.com` | ROSA CLI authentication |
| `api.openshift.com` | OCM / ROSA API |
| `console.redhat.com` | Hybrid Cloud Console |
| `*.amazonaws.com` | AWS APIs |
| `registry.terraform.io` | Provider registry |
| `releases.hashicorp.com` | Terraform downloads |
| `github.com`, `objects.githubusercontent.com` | Modules and providers |
| `mirror.openshift.com` | CLI downloads |

## SCP verification

For AWS Organizations accounts, verify SCPs do not block ROSA permissions. See [Red Hat SCP documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/prepare_your_environment/rosa-sts-aws-prereqs#rosa-minimum-scp_rosa-sts-aws-prereqs).

## Next steps

- **Full-stack:** [Full-Stack Deployment](full-stack.md)
- **BYO VPC:** [Bring Your Own — Overview](byo/index.md)
