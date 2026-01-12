# Cluster Module

This module is a thin wrapper around the `rhcs_cluster_rosa_hcp` resource that provides organizational defaults while passing through all provider variables.

## Features

- Thin wrapper - passes through ALL provider variables
- Organizational defaults for security hardening
- Flexible machine pool configuration
- Support for custom machine pools or default pool
- Multi-AZ support
- Optional HTPasswd identity provider for admin user

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

  # Organizational defaults (can override)
  private         = true   # Organizational default
  etcd_encryption = false  # Organizational default

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
  # When enabled, creates rhcs_dns_domain resource that persists between cluster creations (not gated by enable_destroy)
  # When disabled, ROSA uses default DNS domain
  enable_persistent_dns_domain = false  # Default: false

  tags = {
    Environment = "production"
  }
}

# Admin user creation is handled by a separate identity-admin module
# See modules/infrastructure/identity-admin/ for details
module "identity_admin" {
  source = "../identity-admin"

  cluster_id     = module.cluster.cluster_id
  admin_password = "YourSecurePassword123!"
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
| kms_key_arn | KMS key ARN for encryption | `string` | `null` |
| service_cidr | CIDR block for services | `string` | `"172.30.0.0/16"` |
| pod_cidr | CIDR block for pods | `string` | `"10.128.0.0/14"` |
| host_prefix | Host prefix for subnet allocation | `number` | `23` |
| channel_group | Channel group for OpenShift version | `string` | `"stable"` |
| openshift_version | OpenShift version to pin. If not provided, automatically uses latest installable version | `string` | `null` |
| wait_for_std_compute_nodes_complete | Wait for standard compute nodes to complete before considering cluster creation successful. Set to false if nodes may take longer (e.g., egress-zero clusters) | `bool` | `true` |
| enable_audit_logging | Enable CloudWatch audit log forwarding. When enabled, creates IAM role and policy for CloudWatch logging | `bool` | `true` |
| api_endpoint_allowed_cidrs | Optional list of IPv4 CIDR blocks allowed to access the ROSA HCP API endpoint. By default, the VPC endpoint security group only allows access from within the VPC. Useful for VPN ranges, bastion hosts, or other VPCs | `list(string)` | `[]` |
| enable_persistent_dns_domain | Enable persistent DNS domain registration. When true, creates rhcs_dns_domain resource that persists between cluster creations (not gated by enable_destroy). When false, ROSA uses default DNS domain | `bool` | `false` |
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

**Note**: Admin user creation has been moved to a separate `identity-admin` module for independent lifecycle management. See `modules/infrastructure/identity-admin/README.md` for details.

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
| cloudwatch_audit_logging_role_arn | ARN of the IAM role for CloudWatch audit log forwarding (null if disabled or enable_destroy is true) |
| default_machine_pools | Map of default machine pool IDs keyed by pool name |
| additional_machine_pools | Map of additional machine pool IDs keyed by pool name |
| all_machine_pools | Map of all machine pool IDs (default + additional) keyed by pool name |

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

## Architecture Decision

This module is a **thin wrapper** that:

- Provides organizational defaults for consistency
- Passes through ALL provider variables for flexibility
- Allows overrides of any default
- Documents organizational standards

This approach balances consistency with flexibility, ensuring all clusters follow organizational patterns while allowing customization when needed.
