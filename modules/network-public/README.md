# Network Public Module

This module creates a VPC with public and private subnets, Internet Gateway, and NAT Gateways for ROSA HCP clusters that require internet access.

## Features

- VPC with DNS hostnames and DNS support enabled
- Private subnets for worker nodes (conditional on `multi_az`)
- Public subnets for NAT Gateways and load balancers
- **NAT Gateways** - One gateway per availability zone for high availability
- VPC endpoints for AWS services (cost optimization and performance):
  - S3 (Gateway endpoint - no cost)
  - ECR Docker API (Interface endpoint)
  - ECR API (Interface endpoint)
  - STS (Interface endpoint - required for IAM roles, IRSA, OIDC operations)
- ROSA-required subnet tags

## Usage

```hcl
module "network" {
  source = "../../modules/network-public"

  name_prefix = "my-cluster"
  vpc_cidr    = "10.0.0.0/16"
  multi_az    = true  # Automatically uses first 3 available AZs
  # subnet_cidr_size is automatically calculated (will be /19 for multi-AZ with /16 VPC)

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
| enable_nat_gateway | Enable NAT Gateway for private subnet internet access | `bool` | `true` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | ID of the VPC |
| vpc_cidr_block | CIDR block of the VPC |
| private_subnet_ids | List of private subnet IDs |
| public_subnet_ids | List of public subnet IDs |
| nat_gateway_ids | List of NAT Gateway IDs (one per AZ) |
| nat_gateway_id | ID of the first NAT Gateway (for backwards compatibility) |
| internet_gateway_id | ID of the Internet Gateway |
| vpc_endpoint_ids | Map of VPC endpoint service names to endpoint IDs |

## ROSA Requirements

This module automatically applies ROSA-required tags to subnets:

- **Private Subnets**: `kubernetes.io/role/internal-elb = "1"`
- **Public Subnets**: `kubernetes.io/role/elb = "1"`

## Architecture Decisions

- **NAT Gateways**: One gateway per availability zone for high availability and immediate availability without expansion delays
- Public subnets are required for NAT Gateways and ROSA load balancers
- VPC endpoints for S3, ECR, and STS are created for cost optimization and performance:
  - S3 Gateway endpoint: No cost, no data transfer charges
  - ECR Interface endpoints: Avoid NAT Gateway charges for container image pulls
  - STS Interface endpoint: Required for IAM role assumption (IRSA), OIDC operations, avoids NAT Gateway charges
- The module supports both single-AZ (dev/test) and multi-AZ (production) deployments
