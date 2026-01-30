# GitOps for Egress-Zero Clusters

Egress-zero clusters have **no internet egress**, which means they cannot access external Git repositories like GitHub directly. This document outlines solutions for enabling GitOps on egress-zero clusters.

## Problem

GitOps requires access to Git repositories to:
- Sync application configurations
- Pull Helm charts
- Access cluster configuration files

Egress-zero clusters cannot reach:
- ❌ GitHub (`github.com`)
- ❌ GitHub Pages (`*.github.io`)
- ❌ Any external Git repositories
- ❌ External Helm repositories

## Solutions

### Option 1: AWS CodeCommit (Recommended) ⭐

**Best for**: Production egress-zero clusters

**Why CodeCommit**:
- ✅ Native AWS service
- ✅ Works with VPC endpoints (no internet egress required)
- ✅ IAM-based authentication (no SSH keys)
- ✅ Git-compatible (standard Git protocol)
- ✅ Can mirror GitHub repos automatically

#### Setup Steps

1. **Create CodeCommit Repository** (via Terraform):
```hcl
resource "aws_codecommit_repository" "cluster_config" {
  repository_name = "${var.cluster_name}-cluster-config"
  description     = "Cluster configuration repository for ${var.cluster_name}"
}
```

2. **Add CodeCommit VPC Endpoint** (in network module):
```hcl
resource "aws_vpc_endpoint" "codecommit" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.codecommit"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true
}
```

3. **Create IAM Role for ArgoCD**:
```hcl
resource "aws_iam_role" "argocd_codecommit" {
  name = "${var.cluster_name}-argocd-codecommit"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${oidc_endpoint_url}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${oidc_endpoint_url}:sub" = "system:serviceaccount:openshift-gitops:argocd-repo-server"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "codecommit_access" {
  role = aws_iam_role.argocd_codecommit.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "codecommit:GitPull",
        "codecommit:GitPush",
        "codecommit:GetRepository",
        "codecommit:ListRepositories"
      ]
      Resource = aws_codecommit_repository.cluster_config.arn
    }]
  })
}
```

4. **Mirror GitHub Repository to CodeCommit**:
```bash
# Clone GitHub repo
git clone https://github.com/org/cluster-config.git
cd cluster-config

# Add CodeCommit as remote
git remote add codecommit https://git-codecommit.us-east-2.amazonaws.com/v1/repos/cluster-config

# Push to CodeCommit
git push codecommit main
```

5. **Update Cluster Configuration**:
```hcl
gitops_git_repo_url = "https://git-codecommit.us-east-2.amazonaws.com/v1/repos/${cluster_name}-cluster-config"
```

#### Automatic Mirroring

Set up CI/CD (GitHub Actions, GitLab CI, etc.) to automatically mirror GitHub → CodeCommit:

```yaml
# .github/workflows/mirror-to-codecommit.yml
name: Mirror to CodeCommit
on:
  push:
    branches: [main]
jobs:
  mirror:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-2
      - name: Push to CodeCommit
        run: |
          git remote add codecommit https://git-codecommit.us-east-2.amazonaws.com/v1/repos/cluster-config
          git push codecommit main
```

### Option 2: ArgoCD HTTP Proxy via Bastion

**Best for**: Development/testing egress-zero clusters

Configure ArgoCD to use the bastion host as an HTTP proxy for Git operations.

#### Setup Steps

1. **Configure Proxy on Bastion**:
```bash
# Install Squid proxy on bastion
sudo yum install -y squid

# Configure Squid to allow Git operations
# Edit /etc/squid/squid.conf
```

2. **Configure ArgoCD to Use Proxy**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-repo-server-config
  namespace: openshift-gitops
data:
  proxy: |
    http: http://bastion-private-ip:3128
    https: http://bastion-private-ip:3128
    noProxy: localhost,127.0.0.1,.svc,.cluster.local
```

3. **Update Git Repository Configuration**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Repository
metadata:
  name: cluster-config
spec:
  repo: https://github.com/org/cluster-config.git
  # Proxy settings are inherited from ConfigMap
```

**Limitations**:
- ⚠️ Requires proxy setup and maintenance
- ⚠️ Proxy becomes single point of failure
- ⚠️ More complex configuration

### Option 3: Private Git Server

**Best for**: Organizations with existing Git infrastructure

Deploy GitLab or Bitbucket Server in a VPC accessible to the egress-zero cluster.

**Benefits**:
- ✅ Full control over Git infrastructure
- ✅ Can be hosted in same VPC
- ✅ No external dependencies

**Drawbacks**:
- ⚠️ Requires additional infrastructure
- ⚠️ More complex setup
- ⚠️ Maintenance overhead

## Recommended Approach

For **production egress-zero clusters**, use **AWS CodeCommit**:
1. Native AWS service
2. Works with VPC endpoints
3. No internet egress required
4. IAM-based authentication
5. Can mirror GitHub repos automatically

## Implementation Status

- ⏳ **Not Yet Implemented** - See `docs/TODO.md` for tracking
- **Priority**: HIGH (blocks GitOps on egress-zero clusters)

## References

- [AWS CodeCommit Documentation](https://docs.aws.amazon.com/codecommit/)
- [ArgoCD Repository Configuration](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/)
- [VPC Endpoints for CodeCommit](https://docs.aws.amazon.com/codecommit/latest/userguide/vpc-endpoints.html)
