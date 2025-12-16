# ROSA HCP Infrastructure

Production-grade Terraform repository for deploying Red Hat OpenShift Service on AWS (ROSA) with Hosted Control Planes (HCP).

## Overview

This repository provides reusable Terraform modules and example configurations for deploying ROSA HCP clusters with different network topologies and security postures. The architecture follows a **Directory-Per-Cluster** pattern with **Infrastructure/Configuration separation** to ensure state isolation and proper lifecycle management.

### Repository Structure

The repository is organized into two main categories:

- **Infrastructure**: Foundational AWS and ROSA resources (VPC, IAM roles, cluster)
- **Configuration**: Cluster configuration and Day 2 operations (GitOps, identity providers, bastion)

Each cluster example has separate `infrastructure/` and `configuration/` directories with independent Terraform state files. Configuration reads infrastructure outputs via `terraform_remote_state` data sources.

> **⚠️ Known Issue**: The egress-zero cluster example (`clusters/examples/egress-zero/`) is currently non-functional. Worker nodes are not starting successfully. Investigation is ongoing. See [CHANGELOG.md](CHANGELOG.md) for details.

## Quick Start

### Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured with appropriate credentials
- Red Hat Cloud Services (RHCS) token (set via `TF_VAR_token` environment variable)
- `oc` CLI installed (for cluster access)
- `sshuttle` installed (for private cluster access via bastion) - `brew install sshuttle` on macOS

### Deploy a Public Cluster

**1. Set required environment variables:**
```bash
export TF_VAR_token="your-rhcs-token"
export TF_VAR_admin_password="your-secure-password"  # Optional, for admin user
```

**2. Initialize, plan, and apply:**
```bash
# Initialize Terraform
make init.public

# Review the plan
make plan.public

# Apply the configuration
make apply.public
```

**3. Access the cluster:**
```bash
# Show cluster endpoints
make show-endpoints.public

# Login to the cluster
make login.public

# Show admin credentials
make show-credentials.public
```

**4. Destroy the cluster:**
```bash
make destroy.public
```

### Deploy a Private Cluster

Private clusters require a bastion host and SSH tunnel for access. The Makefile automates this process.

**1. Set required environment variables:**
```bash
export TF_VAR_token="your-rhcs-token"
export TF_VAR_admin_password="your-secure-password"  # Optional, for admin user
```

**2. Initialize, plan, and apply:**
```bash
# Initialize Terraform
make init.private

# Review the plan
make plan.private

# Apply the configuration (creates cluster + bastion)
make apply.private
```

**3. Access the cluster via bastion tunnel:**
```bash
# Start sshuttle VPN tunnel (routes all VPC traffic through bastion)
# Note: Requires sudo privileges - you'll be prompted for your local sudo password
make tunnel-start.private

# In another terminal, show cluster endpoints
make show-endpoints.private

# Login to the cluster (sshuttle routes traffic transparently)
make login.private

# Show admin credentials
make show-credentials.private
```

**4. Stop the tunnel when done:**
```bash
make tunnel-stop.private
```

**5. Connect to bastion directly (optional):**
```bash
# Connect via SSM Session Manager
make bastion-connect.private
```

**6. Destroy the cluster:**
```bash
# Stop tunnel first if running
make tunnel-stop.private

# Destroy cluster and bastion
make destroy.private
```

## Repository Structure

The repository is organized to separate **infrastructure** (foundational AWS/ROSA resources) from **configuration** (cluster configuration, GitOps, identity providers) with independent state files:

```
rosa-hcp-infrastructure/
├── modules/                    # Reusable Terraform modules
│   ├── infrastructure/         # Infrastructure modules
│   │   ├── network-public/     # Public VPC with NAT Gateways
│   │   ├── network-private/    # Private VPC (PrivateLink API)
│   │   ├── network-egress-zero/# Egress Zero VPC (⚠️ WIP)
│   │   ├── iam/                # IAM roles and OIDC configuration
│   │   ├── cluster/            # ROSA HCP Cluster module
│   │   └── bastion/            # Bastion host for private cluster access
│   └── configuration/          # Configuration modules
│       ├── gitops/             # OpenShift GitOps operator
│       └── identity-admin/     # Admin user creation (temporary bootstrap)
└── clusters/                   # Cluster configurations
    └── examples/               # Example cluster configurations
        ├── public/             # Development example (public API)
        │   ├── infrastructure/ # Infrastructure state (network, iam, cluster)
        │   └── configuration/  # Configuration state (gitops, identity-admin)
        ├── private/            # Development example (private API)
        │   ├── infrastructure/
        │   └── configuration/
        └── egress-zero/        # Production-ready example (⚠️ WIP)
            ├── infrastructure/
            └── configuration/
```

### Infrastructure vs Configuration

**Infrastructure** (`infrastructure/` directory):
- Creates foundational AWS and ROSA resources
- Network (VPC, subnets, NAT gateways, VPC endpoints)
- IAM roles and OIDC configuration
- ROSA HCP cluster
- Bastion host (optional, for access)

**Configuration** (`configuration/` directory):
- Configures cluster after it's created
- OpenShift GitOps operator deployment
- Identity providers (admin user, external IDP)
- Reads infrastructure outputs via `terraform_remote_state` data source

**Benefits of Separation**:
- **Different Lifecycles**: Infrastructure changes infrequently; configuration changes more often
- **Reduced Blast Radius**: Configuration changes don't risk infrastructure resources
- **Independent Updates**: Update GitOps/identity without touching infrastructure
- **State Isolation**: Each has its own state file for better management

### Module Architecture

Each module is **self-contained** and **reusable**:

- **Inputs**: Well-defined variables with descriptions and types
- **Outputs**: Clear outputs for integration with other modules
- **Documentation**: Complete README.md with usage examples
- **State Isolation**: Modules can be used independently or composed together

## Using Modules to Compose Custom Infrastructure

The modules are designed to be **composable** and **reusable**. You can mix and match modules to create custom infrastructure configurations.

### Basic Module Composition

Here's how the example clusters compose modules:

```hcl
# clusters/examples/public/infrastructure/10-main.tf
module "network" {
  source = "../../../../modules/infrastructure/network-public"

  name_prefix = var.cluster_name
  vpc_cidr    = var.vpc_cidr
  multi_az    = var.multi_az
  tags        = var.tags
}

module "iam" {
  source = "../../../../modules/infrastructure/iam"

  cluster_name         = var.cluster_name
  account_role_prefix  = var.cluster_name
  operator_role_prefix = var.cluster_name
  tags                 = var.tags
}

module "cluster" {
  source = "../../../../modules/infrastructure/cluster"

  cluster_name       = var.cluster_name
  region             = var.region
  vpc_id             = module.network.vpc_id
  subnet_ids         = concat(module.network.private_subnet_ids, module.network.public_subnet_ids)
  installer_role_arn = module.iam.installer_role_arn
  support_role_arn   = module.iam.support_role_arn
  worker_role_arn    = module.iam.worker_role_arn
  oidc_config_id     = module.iam.oidc_config_id
  oidc_endpoint_url  = module.iam.oidc_endpoint_url
  # ... other cluster configuration
}
```

```hcl
# clusters/examples/public/configuration/10-main.tf
# Read infrastructure outputs via remote state
data "terraform_remote_state" "infrastructure" {
  backend = "local"
  config = {
    path = "../infrastructure/terraform.tfstate"
  }
}

# Deploy GitOps operator
module "gitops" {
  source = "../../../../modules/configuration/gitops"

  cluster_id   = data.terraform_remote_state.infrastructure.outputs.cluster_id
  cluster_name = data.terraform_remote_state.infrastructure.outputs.cluster_name
  api_url      = data.terraform_remote_state.infrastructure.outputs.api_url

  admin_username = var.admin_username
  admin_password = var.admin_password
}

# Create admin user
module "identity_admin" {
  source = "../../../../modules/configuration/identity-admin"

  cluster_id     = data.terraform_remote_state.infrastructure.outputs.cluster_id
  admin_password = var.admin_password
}
```

### Multi-Team Scenarios

The modules support **separation of concerns** where different teams own different aspects of the infrastructure:

#### Scenario 1: Network Team Owns VPC

**Network Team** (`clusters/production/network/`):
```hcl
# Network team creates and manages VPC
module "network" {
  source = "../../../modules/network-private"

  name_prefix = "prod-network"
  vpc_cidr    = "10.0.0.0/16"
  multi_az    = true
  tags = {
    Team = "Network"
    Environment = "Production"
  }
}

# Outputs VPC details for other teams
output "vpc_id" {
  value = module.network.vpc_id
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}
```

**Platform Team** (`clusters/production/cluster/`):
```hcl
# Platform team uses network team's outputs via data sources or remote state
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "my-org-terraform-state"
    key    = "production/network/terraform.tfstate"
    region = "us-east-1"
  }
}

module "iam" {
  source = "../../../modules/iam"
  # ... IAM configuration
}

module "cluster" {
  source = "../../../modules/cluster"

  vpc_id     = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  # ... cluster configuration
}
```

#### Scenario 2: IAM Team Owns Roles

**IAM Team** (`clusters/production/iam/`):
```hcl
# IAM team creates and manages all ROSA IAM resources
module "iam" {
  source = "../../../modules/iam"

  cluster_name         = "production"
  account_role_prefix  = "prod"
  operator_role_prefix = "prod"
  tags = {
    Team = "IAM"
    Environment = "Production"
  }
}

# Outputs role ARNs for platform team
output "installer_role_arn" {
  value = module.iam.installer_role_arn
}

output "worker_role_arn" {
  value = module.iam.worker_role_arn
}

output "oidc_config_id" {
  value = module.iam.oidc_config_id
}
```

**Platform Team** (`clusters/production/cluster/`):
```hcl
# Platform team uses IAM team's outputs
data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket = "my-org-terraform-state"
    key    = "production/iam/terraform.tfstate"
    region = "us-east-1"
  }
}

module "cluster" {
  source = "../../../modules/cluster"

  installer_role_arn = data.terraform_remote_state.iam.outputs.installer_role_arn
  worker_role_arn    = data.terraform_remote_state.iam.outputs.worker_role_arn
  oidc_config_id     = data.terraform_remote_state.iam.outputs.oidc_config_id
  # ... cluster configuration
}
```

#### Scenario 3: Complete Separation (Network, IAM, Cluster)

**Network Team** (`clusters/production/network/terraform.tfstate`):
- Manages VPC, subnets, VPC endpoints
- Outputs: `vpc_id`, `subnet_ids`, `vpc_cidr`

**IAM Team** (`clusters/production/iam/terraform.tfstate`):
- Manages OIDC, account roles, operator roles
- Outputs: `installer_role_arn`, `worker_role_arn`, `oidc_config_id`, `oidc_endpoint_url`

**Platform Team** (`clusters/production/cluster/terraform.tfstate`):
- Manages cluster deployment
- Reads from both network and IAM remote states
- Composes modules using outputs from other teams

### Creating Your Own Cluster Configuration

**1. Create a new cluster directory:**
```bash
mkdir -p clusters/my-cluster
cd clusters/my-cluster
```

**2. Create `00-providers.tf`:**
```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = "~> 1.7"
    }
  }

  # Optional: Configure remote state backend
  # backend "s3" {
  #   bucket         = "my-org-terraform-state"
  #   key            = "my-cluster/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.region
}

provider "rhcs" {
  token = var.token
}
```

**3. Create `01-variables.tf`:**
```hcl
variable "cluster_name" {
  description = "Name of the ROSA HCP cluster"
  type        = string
  nullable    = false
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
  nullable    = false
}

variable "token" {
  description = "RHCS API token"
  type        = string
  sensitive   = true
  nullable    = false
}

# Add other variables as needed
```

**4. Create `10-main.tf` with module composition:**
```hcl
# Compose modules to create your infrastructure
module "network" {
  source = "../../modules/network-public"  # or network-private

  name_prefix = var.cluster_name
  vpc_cidr    = "10.0.0.0/16"
  multi_az    = true
  tags = {
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}

module "iam" {
  source = "../../modules/iam"

  cluster_name         = var.cluster_name
  account_role_prefix  = var.cluster_name
  operator_role_prefix = var.cluster_name
  tags = {
    Environment = "production"
  }
}

module "cluster" {
  source = "../../modules/cluster"

  cluster_name       = var.cluster_name
  region             = var.region
  vpc_id             = module.network.vpc_id
  subnet_ids         = module.network.private_subnet_ids
  installer_role_arn = module.iam.installer_role_arn
  support_role_arn   = module.iam.support_role_arn
  worker_role_arn    = module.iam.worker_role_arn
  oidc_config_id     = module.iam.oidc_config_id
  oidc_endpoint_url  = module.iam.oidc_endpoint_url
  vpc_cidr           = module.network.vpc_cidr_block
  availability_zones = module.network.private_subnet_azs

  # Cluster configuration
  private    = true
  multi_az   = true
  # ... other cluster settings
}
```

**5. Create `terraform.tfvars`:**
```hcl
cluster_name = "my-cluster"
region       = "us-east-1"
# token should be set via TF_VAR_token environment variable
```

**6. Use Makefile pattern rules:**
```bash
# The Makefile automatically detects cluster directories
# Just use the cluster name as the suffix
make init.my-cluster
make plan.my-cluster
make apply.my-cluster
```

## Available Modules

### Network Modules

- **network-public**: Public VPC with NAT Gateways
  - Public and private subnets
  - Zonal NAT Gateways (one per AZ)
  - VPC endpoints (S3, ECR, STS)
  - ROSA-required subnet tags

- **network-private**: Private VPC with PrivateLink API
  - Private subnets only
  - VPC endpoints for all AWS services
  - Optional Regional NAT Gateway for internet egress
  - ROSA-required subnet tags

- **network-egress-zero**: Egress-zero VPC ⚠️ **Work in Progress**
  - Strict egress controls
  - Network ACLs for additional restrictions
  - VPC Flow Logs support
  - **Currently non-functional**

### Core Modules

- **iam**: IAM roles and OIDC configuration
  - Account roles (Installer, Support, Worker)
  - Operator roles (Ingress, Control Plane, CSI, etc.)
  - OIDC configuration and provider
  - Uses upstream `terraform-redhat/rosa-hcp/rhcs` modules

- **cluster**: ROSA HCP cluster deployment
  - Thin wrapper with organizational defaults
  - Machine pool management
  - Automatic version detection
  - Machine type validation

- **identity-admin**: Admin user creation
  - Temporary bootstrap user
  - HTPasswd identity provider
  - Can be removed when external IDP is configured

- **bastion**: Bastion host for private cluster access
  - SSM Session Manager support
  - Pre-installed tools (`oc`, `kubectl`)
  - **Development/demo use only** - not for production

## Makefile Usage

The Makefile provides convenient targets for managing clusters. Use **pattern syntax** for flexibility:

### Pattern Syntax (Recommended)

```bash
# Pattern: make <action>.<cluster>
make init.public
make plan.private
make apply.egress-zero
make destroy.public
make login.private
make tunnel-start.private
```

### Available Actions

**Cluster Management (Infrastructure + Configuration):**
- `init.<cluster>` - Initialize both infrastructure and configuration
- `plan.<cluster>` - Plan both (infrastructure first, then configuration)
- `apply.<cluster>` - Apply both (infrastructure first, then configuration)
- `destroy.<cluster>` - Destroy both (configuration first, then infrastructure)

**Infrastructure Management:**
- `init-infrastructure.<cluster>` - Initialize infrastructure only
- `plan-infrastructure.<cluster>` - Plan infrastructure changes
- `apply-infrastructure.<cluster>` - Apply infrastructure
- `destroy-infrastructure.<cluster>` - Destroy infrastructure

**Configuration Management:**
- `init-configuration.<cluster>` - Initialize configuration only
- `plan-configuration.<cluster>` - Plan configuration changes
- `apply-configuration.<cluster>` - Apply configuration
- `destroy-configuration.<cluster>` - Destroy configuration

**Cluster Access:**
- `login.<cluster>` - Login to cluster using `oc`
- `show-endpoints.<cluster>` - Show API and console URLs
- `show-credentials.<cluster>` - Show admin credentials and endpoints

**Bastion & Tunnel (Private/Egress-Zero clusters):**
- `tunnel-start.<cluster>` - Start sshuttle VPN tunnel
- `tunnel-stop.<cluster>` - Stop sshuttle tunnel
- `tunnel-status.<cluster>` - Check tunnel status
- `bastion-connect.<cluster>` - Connect to bastion via SSM

**Code Quality:**
- `make fmt` - Format all Terraform files
- `make validate` - Validate all Terraform configurations
- `make validate-modules` - Validate all modules
- `make validate-examples` - Validate all example clusters

**Utilities:**
- `make clean` - Clean Terraform files
- `make init-all` - Initialize all example clusters
- `make plan-all` - Plan all example clusters

See `make help` for complete list of targets.

## Bastion Host for Private Clusters

> **⚠️ Development/Demo Use Only**: The bastion host is provided for development and demonstration purposes. For production deployments, use AWS Transit Gateway, Direct Connect, or VPN connections instead.

Private and egress-zero clusters include an optional bastion host for secure access:

- **SSM Session Manager**: No public IP, access via AWS Systems Manager (recommended)
- **Pre-installed Tools**: OpenShift CLI (`oc`), Kubernetes CLI (`kubectl`)
- **sshuttle VPN Tunnel**: Routes all VPC traffic through bastion for full cluster access

### Using sshuttle Tunnel

The `tunnel-start.<cluster>` target creates a VPN-like tunnel using `sshuttle`:

```bash
# Start tunnel (requires sudo - you'll be prompted for password)
make tunnel-start.private

# Tunnel is now active - all traffic to VPC CIDR routes through bastion
# You can now use oc login with the direct API URL
make login.private

# Stop tunnel when done
make tunnel-stop.private
```

**Why sshuttle?** Unlike SSH port forwarding, sshuttle routes **all VPC traffic** through the bastion, enabling OAuth flows required for `oc login` to work correctly.

See `modules/bastion/README.md` for detailed documentation.

## Admin User Management

The `identity-admin` module creates a temporary admin user for initial cluster access:

```hcl
module "identity_admin" {
  source = "../../modules/identity-admin"

  cluster_id     = module.cluster.cluster_id
  admin_password = var.admin_password  # Set via TF_VAR_admin_password
  admin_username = "admin"             # Optional, defaults to "admin"
  admin_group    = "cluster-admins"    # Optional, defaults to "cluster-admins"
}
```

**Best Practice**: Remove this module once you've configured an external identity provider (LDAP, OIDC, etc.).

See `modules/identity-admin/README.md` for detailed documentation.

## State Management

Each cluster directory uses its own Terraform state for isolation:

**Local State (Default):**
```hcl
# State stored locally in cluster directory
# No backend configuration needed
```

**Remote State (Recommended for Production):**
```hcl
terraform {
  backend "s3" {
    bucket         = "my-org-terraform-state"
    key            = "my-cluster/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

**Multi-Team State Sharing:**
```hcl
# Read other team's state
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "my-org-terraform-state"
    key    = "production/network/terraform.tfstate"
    region = "us-east-1"
  }
}
```

## Security Best Practices

- **Never commit secrets**: Use environment variables (`TF_VAR_token`, `TF_VAR_admin_password`) or AWS Secrets Manager
- **Least Privilege**: All IAM roles follow least-privilege principles
- **State Encryption**: Always enable encryption for S3 backends
- **State Locking**: Use DynamoDB for state locking in production
- **Separate State**: Each cluster has its own state file for isolation

## Documentation

- **[PLAN.md](PLAN.md)** - Detailed implementation plan and architecture decisions
- **[CHANGELOG.md](CHANGELOG.md)** - Version history and changes
- **Module READMEs** - See `modules/*/README.md` for module-specific documentation
- **[.cursorrules](.cursorrules)** - Development guidelines and best practices

## Module Status

- ✅ **network-public**: Production-ready
- ✅ **network-private**: Production-ready
- ⚠️ **network-egress-zero**: Work in Progress (non-functional)
- ✅ **iam**: Production-ready
- ✅ **cluster**: Production-ready
- ✅ **identity-admin**: Production-ready
- ✅ **bastion**: Production-ready (dev/demo use only)

## Contributing

1. Review [PLAN.md](PLAN.md) before making changes
2. Follow [.cursorrules](.cursorrules) guidelines
3. Update [CHANGELOG.md](CHANGELOG.md) with changes
4. Ensure all code passes `terraform fmt` and `terraform validate`
5. Run security scanning with `checkov`

## References

- [ROSA HCP Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/)
- [Terraform RHCS Provider](https://registry.terraform.io/providers/terraform-redhat/rhcs/latest)
- [Red Hat MOBB Rules](https://github.com/rh-mobb/mobb-rules)

## License

Copyright 2024 Red Hat, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
