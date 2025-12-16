# Network Private Module

This module creates a VPC with private subnets only, VPC endpoints for AWS services, and Regional NAT Gateway for internet egress (enabled by default). Designed for ROSA HCP clusters using PrivateLink API.

## Features

- VPC with DNS hostnames and DNS support enabled
- Private subnets for worker nodes (conditional on `multi_az`)
- **NO public subnets** - PrivateLink API only
- **Optional Regional NAT Gateway** - Enable internet egress without public subnets (requires Internet Gateway)
- VPC endpoints for all required AWS services:
  - S3 (Gateway endpoint - no cost)
  - ECR Docker API (Interface endpoint)
  - ECR API (Interface endpoint)
  - CloudWatch Logs (Interface endpoint)
  - CloudWatch Monitoring (Interface endpoint)
  - STS (Interface endpoint - required for IAM roles)
- ROSA-required subnet tags
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
- Suitable for production environments requiring enhanced security

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
