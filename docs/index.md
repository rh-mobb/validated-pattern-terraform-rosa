# ROSA HCP Terraform

Production-grade Terraform for deploying **Red Hat OpenShift Service on AWS (ROSA)** with **Hosted Control Planes (HCP)**.

This repository provides reusable Terraform modules and per-cluster configurations using a **directory-per-cluster** pattern for state isolation and lifecycle management.

## Documentation map

| I want to… | Start here |
|------------|------------|
| Deploy my first cluster quickly | [Quick Start](getting-started/quick-start.md) |
| Verify AWS account and ROSA prerequisites | [Account Prerequisites](prerequisites/account.md) |
| Choose full-stack vs bring-your-own (BYO) | [Prerequisites — Choose Your Path](prerequisites/index.md) |
| Follow the full enablement guide | [Enablement Guide](deployment/enablement.md) |
| Configure a specific cluster profile | [Cluster Configurations](deployment/cluster-configurations.md) |
| Deploy zero-egress with GitOps | [Egress-Zero GitOps](guides/egress-zero-gitops.md) |
| Look up module inputs/outputs | [Modules](modules/cluster.md) |

## Architecture at a glance

```mermaid
flowchart TB
  subgraph repo [This repository]
    Tfvars[clusters/name/terraform.tfvars]
    Terraform[terraform/ root module]
    Modules[modules/infrastructure/*]
  end

  subgraph aws [AWS Account]
    VPC[VPC and subnets]
    IAM[IAM OIDC KMS]
    Cluster[ROSA HCP cluster]
  end

  Tfvars --> Terraform --> Modules
  Modules --> VPC
  Modules --> IAM
  Modules --> Cluster
```

## Example cluster profiles

| Profile | Example directory | Typical use |
|---------|-------------------|-------------|
| Public (dev) | `clusters/public/` | Development, public API |
| Egress-zero (prod) | `clusters/egress-zero/` | Zero internet egress, private API |
| BYO VPC | `clusters/byo-vpc/` | Network team owns VPC |
| BYO VPC + zero egress | `clusters/byo-vpc-egress-zero/` | Pre-provisioned VPC, zero egress |

## Local preview

```bash
pip install -r requirements-docs.txt
make docs-preview
```

Open [http://127.0.0.1:8000](http://127.0.0.1:8000).

## Related repositories

This infrastructure repo is one part of a three-repository pattern:

1. **Infrastructure** (this repo) — Terraform Day 0
2. **cluster-config** — GitOps configuration for Argo CD
3. **validated-pattern-helm-charts** — Bootstrap and app-of-apps Helm charts

See the [Enablement Guide](deployment/enablement.md) for the full adoption path.
