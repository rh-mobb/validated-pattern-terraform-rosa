# Network Private Module

This module creates a VPC with private subnets only, VPC endpoints for AWS services, and optional Regional NAT Gateway for internet egress. Designed for ROSA HCP clusters using PrivateLink API. Supports both standard private networks and zero-egress (strict egress control) configurations.

## Features

- VPC with DNS hostnames and DNS support enabled
- Private subnets for worker nodes (conditional on `multi_az`)
- **NO public subnets** - PrivateLink API only
- **Optional Regional NAT Gateway** - Enable internet egress without public subnets (requires Internet Gateway)
- **Strict egress control** (zero-egress mode) - Optional worker node security group with limited egress rules
- **VPC Flow Logs** - Optional audit logging to S3 for compliance
- VPC endpoints for all required AWS services:
  - S3 (Gateway endpoint - no cost)
  - ECR Docker API (Interface endpoint)
  - ECR API (Interface endpoint)
  - CloudWatch Logs (Interface endpoint)
  - CloudWatch Monitoring (Interface endpoint)
  - STS (Interface endpoint - required for IAM roles)
- ROSA-required subnet tags
- **ROSA VPC endpoint lookup** - Optional lookup of ROSA-created VPC endpoint for API server access
- **Note**: SSM endpoints are created by the bastion module when a bastion is deployed

## Usage

```hcl
# With internet egress via Regional NAT Gateway (default)
module "network" {
  source = "../../modules/network-private"

  name_prefix = "my-cluster"
  vpc_cidr    = "10.0.0.0/16"
  multi_az    = true  # Automatically uses first 3 available AZs
  # subnet_cidr_size is automatically calculated (will be /18 for multi-AZ with /16 VPC)
  # enable_nat_gateway = true  # Default: Regional NAT Gateway enabled

  tags = {
    Environment = "production"
    Project     = "rosa-hcp"
  }
}

# Without internet egress (VPC endpoints only)
module "network" {
  source = "../../modules/network-private"

  name_prefix = "my-cluster"
  vpc_cidr    = "10.0.0.0/16"
  multi_az    = true
  enable_nat_gateway = false  # Disable Regional NAT Gateway, only VPC endpoints

  tags = {
    Environment = "production"
    Project     = "rosa-hcp"
  }
}

# Zero-egress mode (strict egress control with flow logs)
module "network" {
  source = "../../modules/network-private"

  name_prefix       = "my-cluster"
  vpc_cidr          = "10.0.0.0/16"
  multi_az          = true
  enable_nat_gateway = false      # No NAT Gateway for zero egress
  enable_strict_egress = true      # Enable strict egress control
  flow_log_s3_bucket = "my-org-vpc-flow-logs"  # Optional: VPC Flow Logs for audit
  cluster_id         = null        # Optional: Can be set after cluster creation

  tags = {
    Environment = "production"
    Project     = "rosa-hcp"
    Security    = "high"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | ~> 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name_prefix | Prefix for all resource names (typically cluster name). Ensures unique resource names across clusters | `string` | n/a | yes |
| vpc_cidr | CIDR block for the VPC | `string` | n/a | yes |
| multi_az | Create resources across multiple availability zones for high availability. Availability zones are automatically determined from AWS | `bool` | `true` | no |
| subnet_cidr_size | CIDR size for each subnet (e.g., 20 for /20). If not provided, automatically calculated based on VPC CIDR and number of subnets. Must be larger than VPC CIDR size | `number` | `null` (auto-calculated) | no |
| enable_nat_gateway | Enable Regional NAT Gateway for internet egress from private subnets. Requires an Internet Gateway but does not require public subnets | `bool` | `true` | no |
| enable_strict_egress | Enable strict egress control (zero-egress mode). When true, creates worker node security group with limited egress rules and removes egress from VPC endpoint security group | `bool` | `false` | no |
| flow_log_s3_bucket | S3 bucket name for VPC Flow Logs (optional, typically used with zero-egress mode for audit logging) | `string` | `null` | no |
| cluster_id | Optional ROSA HCP cluster ID. If provided, will look up the ROSA-created VPC endpoint for API server access (used with zero-egress mode for validation) | `string` | `null` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | ID of the VPC |
| vpc_cidr_block | CIDR block of the VPC |
| private_subnet_ids | List of private subnet IDs |
| vpc_endpoint_ids | Map of VPC endpoint service names to endpoint IDs |
| nat_gateway_id | ID of the Regional NAT Gateway (if enabled) |
| internet_gateway_id | ID of the Internet Gateway (if NAT Gateway is enabled) |
| security_group_id | ID of the security group for worker nodes with strict egress control (null if enable_strict_egress is false) |
| rosa_api_vpc_endpoint_id | ID of the ROSA-created VPC endpoint for API server access (null if cluster_id not provided) |
| private_subnet_azs | List of availability zones used for private subnets |

## ROSA Requirements

This module automatically applies ROSA-required tags to private subnets:

- **Private Subnets**: `kubernetes.io/role/internal-elb = "1"`

## Architecture Notes

- This topology requires **PrivateLink** for API access
- **Regional NAT Gateway enabled by default**: Provides internet egress from private subnets
  - Does NOT require public subnets (Regional NAT Gateway operates independently)
  - Requires an Internet Gateway (automatically created)
  - Automatically expands across AZs based on workload presence
  - Suitable for environments needing internet access while keeping workloads in private subnets only
- **Optional**: Set `enable_nat_gateway = false` to disable internet egress and use only VPC endpoints
- **Zero-egress mode**: Set `enable_nat_gateway = false` and `enable_strict_egress = true` for maximum security
  - Creates worker node security group with strict egress rules (HTTPS 443, DNS 53 UDP/TCP to VPC CIDR only)
  - Removes egress rules from VPC endpoint security group
  - All external access must go through VPC endpoints
  - Suitable for high-security production environments requiring zero internet egress
- Suitable for production environments requiring enhanced security

## Zero-Egress Mode (Strict Egress Control)

When `enable_strict_egress = true`, the module creates:

- **Worker Node Security Group**: Limited egress rules allowing only:
  - HTTPS (443 TCP) to VPC CIDR (for VPC endpoints)
  - DNS (53 UDP/TCP) to VPC CIDR (for VPC endpoint DNS resolution)
- **VPC Endpoint Security Group**: No egress rules (strict control)
- **VPC Flow Logs**: Optional audit logging to S3 (if `flow_log_s3_bucket` provided)

This is the most restrictive topology - no internet egress allowed. All external access must go through VPC endpoints or approved proxies.

## VPC Endpoints

The module creates the following VPC endpoints:

- **S3** (Gateway): No cost, no data transfer charges
- **ECR Docker API** (Interface): Required for pulling container images
- **ECR API** (Interface): Required for ECR API operations
- **CloudWatch Logs** (Interface): Required for log shipping
- **CloudWatch Monitoring** (Interface): Required for metrics
- **STS** (Interface): Required for IAM role assumption

All interface endpoints have private DNS enabled and are placed in private subnets.

**Note**: SSM endpoints (ssm, ec2messages, ssmmessages) are created by the bastion module when a bastion host is deployed, as they are only needed for SSM Session Manager access.
