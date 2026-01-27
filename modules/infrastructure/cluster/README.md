# Cluster Module

This module creates and manages ROSA HCP clusters, machine pools, identity providers, and EFS storage resources.

## Features

- ROSA HCP cluster creation and management
- Flexible machine pool configuration
- Support for custom machine pools or default pool
- Multi-AZ support
- HTPasswd identity provider for admin user
- **EFS file system** (storage infrastructure that depends on cluster security groups)
- CloudWatch audit logging configuration (IAM resources are in IAM module)
- Cluster termination protection
- GitOps bootstrap support

**Note**: KMS keys and IAM resources (CloudWatch logging, Cert Manager, Secrets Manager) are created in the IAM module. This module focuses on cluster-specific resources.

## Usage

```hcl
module "cluster" {
  source = "../../modules/cluster"

  # Required variables
  cluster_name        = "my-rosa-cluster"
  region              = "us-east-1"
  vpc_id              = module.network.vpc_id
  subnet_ids          = module.network.private_subnet_ids
  installer_role_arn = module.iam.installer_role_arn
  support_role_arn   = module.iam.support_role_arn
  worker_role_arn    = module.iam.worker_role_arn
  oidc_config_id     = module.iam.oidc_config_id
  oidc_endpoint_url  = module.iam.oidc_endpoint_url
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

  # KMS keys from IAM module
  kms_key_arn      = module.iam.ebs_kms_key_arn
  etcd_kms_key_arn = module.iam.etcd_kms_key_arn
  efs_kms_key_arn  = module.iam.efs_kms_key_arn

  # CloudWatch audit logging (IAM role ARN from IAM module)
  enable_audit_logging              = true
  cloudwatch_audit_logging_role_arn = module.iam.cloudwatch_audit_logging_role_arn

  # EFS storage configuration
  enable_efs           = true
  private_subnet_cidrs = module.network.private_subnet_cidrs

  # Organizational defaults (can override)
  private         = true   # Organizational default
  etcd_encryption = false  # Organizational default (requires etcd_kms_key_arn from IAM module)

  # Optional: Custom machine pools
  machine_pools = [
    {
      name                = "worker"
      instance_type       = "m5.xlarge"
      min_replicas        = 3
      max_replicas        = 6
      multi_az            = true
      autoscaling_enabled = true
    }
  ]

  # Optional: Allow API endpoint access from additional CIDR blocks
  # By default, only VPC CIDR can access the API endpoint
  api_endpoint_allowed_cidrs = [
    "10.0.0.0/32",      # Example: Specific IP
    "192.168.1.0/24"   # Example: VPN range
  ]

  # Optional: DNS domain registration
  # When enabled, creates rhcs_dns_domain resource that persists between cluster creations (not gated by persists_through_sleep)
  # When disabled, ROSA uses default DNS domain
  enable_persistent_dns_domain = false  # Default: false

  tags = {
    Environment = "production"
  }
}

```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| rhcs | ~> 1.7 |

## Inputs

### Required

| Name | Description | Type |
|------|-------------|------|
| cluster_name | Name of the ROSA HCP cluster | `string` |
| region | AWS region for the cluster | `string` |
| vpc_id | VPC ID from network module | `string` |
| subnet_ids | List of private subnet IDs from network module | `list(string)` |
| installer_role_arn | ARN of the Installer role from IAM module | `string` |
| support_role_arn | ARN of the Support role from IAM module | `string` |
| worker_role_arn | ARN of the Worker role from IAM module | `string` |
| oidc_config_id | OIDC configuration ID from IAM module | `string` |
| oidc_endpoint_url | OIDC endpoint URL from IAM module | `string` |
| availability_zones | List of availability zones | `list(string)` |

### Optional (with defaults)

| Name | Description | Type | Default |
|------|-------------|------|---------|
| private | Use PrivateLink API endpoint | `bool` | `true` |
| etcd_encryption | Enable etcd encryption | `bool` | `false` |
| fips | Enable FIPS 140-2 compliance | `bool` | `false` |
| zero_egress | Enable zero egress mode. Sets zero_egress property to 'true' in cluster properties | `bool` | `false` |
| kms_key_arn | KMS key ARN for EBS volume encryption (from IAM module output) | `string` | `null` |
| etcd_kms_key_arn | KMS key ARN for etcd encryption (from IAM module output, required when etcd_encryption is true) | `string` | `null` |
| efs_kms_key_arn | KMS key ARN for EFS encryption (from IAM module output, required when enable_efs is true) | `string` | `null` |
| enable_efs | Enable EFS file system creation | `bool` | `true` |
| private_subnet_cidrs | List of private subnet CIDR blocks (required for EFS security group rules) | `list(string)` | `[]` |
| private_subnet_ids | List of private subnet IDs (required for EFS mount targets and cluster creation) | `list(string)` | `[]` |
| public_subnet_ids | List of public subnet IDs (for public clusters, will be concatenated with private_subnet_ids) | `list(string)` | `[]` |
| cloudwatch_audit_logging_role_arn | ARN of CloudWatch audit logging IAM role (from IAM module output, required when enable_audit_logging is true) | `string` | `null` |
| aws_private_ca_arn | AWS Private CA ARN for certificate management (for GitOps bootstrap, from IAM module) | `string` | `null` |
| cert_manager_role_arn | ARN of cert-manager IAM role (from IAM module output, for GitOps bootstrap) | `string` | `null` |
| service_cidr | CIDR block for services | `string` | `"172.30.0.0/16"` |
| pod_cidr | CIDR block for pods | `string` | `"10.128.0.0/14"` |
| host_prefix | Host prefix for subnet allocation | `number` | `23` |
| channel_group | Channel group for OpenShift version | `string` | `"stable"` |
| openshift_version | OpenShift version to pin. If not provided, automatically uses latest installable version | `string` | `null` |
| wait_for_std_compute_nodes_complete | Wait for standard compute nodes to complete before considering cluster creation successful. Set to false if nodes may take longer (e.g., egress-zero clusters) | `bool` | `true` |
| enable_audit_logging | Enable CloudWatch audit log forwarding. When enabled, configures cluster to forward audit logs to CloudWatch using IAM role ARN from IAM module | `bool` | `true` |
| enable_termination_protection | Enable cluster termination protection. When enabled, prevents accidental cluster deletion via ROSA CLI. Note: Disabling protection requires manual action via OCM console | `bool` | `false` |
| api_endpoint_allowed_cidrs | Optional list of IPv4 CIDR blocks allowed to access the ROSA HCP API endpoint. By default, the VPC endpoint security group only allows access from within the VPC. Useful for VPN ranges, bastion hosts, or other VPCs | `list(string)` | `[]` |
| enable_persistent_dns_domain | Enable persistent DNS domain registration. When true, creates rhcs_dns_domain resource that persists between cluster creations (not gated by persists_through_sleep). When false, ROSA uses default DNS domain | `bool` | `false` |
| tags | Tags to apply to the cluster | `map(string)` | `{}` |
| machine_pools | List of machine pool configurations for default pools | `list(object)` | `[]` |
| additional_machine_pools | Map of additional custom machine pools beyond default pools. Supports advanced features: taints, labels, kubelet configs, tuning configs, version pinning, capacity reservations | `map(object)` | `{}` |

### Machine Pool Defaults (if machine_pools not provided)

| Name | Description | Type | Default |
|------|-------------|------|---------|
| default_instance_type | Default instance type | `string` | `"m5.xlarge"` |
| default_min_replicas | Default minimum replicas | `number` | `3` |
| default_max_replicas | Default maximum replicas | `number` | `6` |
| default_multi_az | Default multi-AZ setting | `bool` | `true` |

### Identity Provider

The module creates an HTPasswd identity provider and admin user when `enable_identity_provider = true`. The admin password is stored in AWS Secrets Manager and persists through sleep operations.

## Outputs

| Name | Description |
|------|-------------|
| cluster_id | ID of the ROSA HCP cluster |
| cluster_name | Name of the ROSA HCP cluster |
| api_url | API URL of the cluster |
| console_url | Console URL of the cluster |
| kubeconfig | Kubernetes configuration file (sensitive) |
| cluster_admin_password | Cluster admin password (sensitive) |
| state | State of the cluster |
| identity_provider_id | ID of the HTPasswd identity provider (null if enable_identity_provider is false) |
| identity_provider_name | Name of the identity provider (null if enable_identity_provider is false) |
| admin_username | Username of the admin user |
| admin_group | Group the admin user belongs to |
| cluster_credentials_secret_name | Name of AWS Secrets Manager secret containing cluster credentials |
| cluster_credentials_secret_arn | ARN of AWS Secrets Manager secret containing cluster credentials |
| efs_file_system_id | ID of the EFS file system (null if enable_efs is false) |
| efs_file_system_arn | ARN of the EFS file system (null if enable_efs is false) |
| aws_account_id | AWS account ID where the cluster is deployed |
| default_machine_pools | Map of default machine pool IDs keyed by pool name |
| additional_machine_pools | Map of additional machine pool IDs keyed by pool name |
| all_machine_pools | Map of all machine pool IDs (default + additional) keyed by pool name |
| gitops_bootstrap_enabled | Whether GitOps bootstrap is enabled |
| gitops_bootstrap_env_vars | Environment variables for running the GitOps bootstrap script |
| gitops_bootstrap_command | Shell commands to export environment variables for GitOps bootstrap |
| gitops_bootstrap_script_path | Path to the GitOps bootstrap script |

**Note**: KMS key outputs (EBS, EFS, ETCD) and IAM role outputs (CloudWatch logging, Cert Manager, Secrets Manager) are now in the IAM module. See `modules/infrastructure/iam/README.md` for details.

## Organizational Defaults

This module enforces organizational defaults:

- **private = true**: PrivateLink API endpoint (can be overridden)
- **etcd_encryption = false**: No etcd encryption by default (can be overridden)

These defaults ensure consistency across all clusters while allowing overrides when needed.

## Machine Pools

### Machine Type Validation

The module automatically validates that specified instance types are available for ROSA in the target region using the [`rhcs_machine_types` data source](https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/data-sources/machine_types). If an invalid instance type is specified, Terraform will fail with a clear error message listing available machine types.

### Default Pool

If `machine_pools` is not provided, the module creates a default pool:

- Name: `worker`
- Instance type: `m5.xlarge` (configurable via `default_instance_type`, validated against available ROSA machine types)
- Min replicas: `3` (configurable via `default_min_replicas`)
- Max replicas: `6` (configurable via `default_max_replicas`)
- Multi-AZ: `true` (configurable via `default_multi_az`)
- Autoscaling: `true`

### Custom Pools

Provide a list of machine pool configurations:

```hcl
machine_pools = [
  {
    name                = "worker"
    instance_type       = "m5.xlarge"
    min_replicas        = 3
    max_replicas        = 6
    multi_az            = true
    autoscaling_enabled = true
  },
  {
    name                = "compute"
    instance_type       = "m5.2xlarge"
    min_replicas        = 2
    max_replicas        = 10
    multi_az            = true
    autoscaling_enabled = true
  }
]
```

### Additional Machine Pools

Create additional custom machine pools beyond the default ones. These pools support advanced features like taints, labels, kubelet configs, tuning configs, version pinning, and capacity reservations:

```hcl
additional_machine_pools = {
  "compute" = {
    subnet_id           = module.network.private_subnet_ids[0]
    instance_type       = "m5.2xlarge"
    autoscaling_enabled = true
    min_replicas        = 2
    max_replicas        = 10
    labels = {
      "node-role.kubernetes.io/compute" = ""
    }
    taints = [
      {
        key          = "workload"
        value        = "compute"
        schedule_type = "NoSchedule"
      }
    ]
  }
  "gpu" = {
    subnet_id           = module.network.private_subnet_ids[1]
    instance_type       = "g4dn.xlarge"
    autoscaling_enabled = true
    min_replicas        = 0
    max_replicas        = 5
    labels = {
      "node-role.kubernetes.io/gpu" = ""
    }
    taints = [
      {
        key          = "nvidia.com/gpu"
        value        = "true"
        schedule_type = "NoSchedule"
      }
    ]
  }
  "spot" = {
    subnet_id           = module.network.private_subnet_ids[0]
    instance_type       = "m5.large"
    autoscaling_enabled = true
    min_replicas        = 0
    max_replicas        = 10
    labels = {
      "node-role.kubernetes.io/spot" = ""
    }
    taints = [
      {
        key          = "spot"
        value        = "true"
        schedule_type = "PreferNoSchedule"
      }
    ]
  }
}
```

**Advanced Features**:

- **Taints**: Control pod scheduling with taints. Valid `schedule_type` values: `"NoSchedule"`, `"PreferNoSchedule"`, `"NoExecute"`
- **Labels**: Apply Kubernetes node labels for node selection and scheduling
- **Kubelet Configs**: Apply custom kubelet configurations (specify by name, config must already exist)
- **Tuning Configs**: Apply performance tuning configurations (list of tuning config names)
- **Version Pinning**: Pin OpenShift version per pool (e.g., `"4.15.0"`)
- **Capacity Reservations**: Use AWS Capacity Reservations (specify `capacity_reservation_id`)
- **Additional Security Groups**: Attach additional security groups to nodes (`additional_security_group_ids`)
- **Disk Size**: Customize root disk size in GiB (`disk_size`)
- **EC2 Metadata HTTP Tokens**: Control IMDS access (`"optional"` or `"required"`, default: `"required"`)

**Note**: Additional machine pool names cannot conflict with default pool names (e.g., `"workers"`, `"workers-0"`, `"workers-1"`, etc.). The module validates this automatically.

## EFS Storage

The module creates an EFS file system when `enable_efs = true`. EFS remains in the cluster module because:

- **Cluster-specific infrastructure**: EFS depends on cluster security groups for mount targets
- **Network integration**: EFS mount targets use cluster subnets and security groups
- **Lifecycle alignment**: EFS file system lifecycle aligns with cluster lifecycle (though it persists through sleep)

The EFS KMS key is created in the IAM module and passed to this module via `efs_kms_key_arn` variable.

## Dependencies

- **IAM Module**: Provides KMS key ARNs (EBS, EFS, ETCD) and IAM role ARNs (CloudWatch audit logging, etc.)
- **Network Module**: Provides VPC ID, subnet IDs, and subnet CIDRs
- **Cluster Resources**: EFS depends on cluster security groups (created by ROSA)

## Architecture Decision

This module focuses on **cluster-specific resources**:

- Cluster creation and management
- Machine pools
- Identity providers
- EFS storage (depends on cluster security groups)
- Cluster configuration (audit logging, termination protection)

**IAM and KMS resources** are in the IAM module for better separation of concerns and reuse across clusters.
