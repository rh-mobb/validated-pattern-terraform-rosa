# Network Egress-Zero Module

> **⚠️ Work in Progress**: This module is currently non-functional. Worker nodes are not starting successfully. Investigation is ongoing. Do not use for production deployments until issues are resolved.

This module creates a VPC with private subnets only, VPC endpoints, strict egress controls via security groups and NACLs, and VPC Flow Logs. Designed for ROSA HCP clusters requiring maximum security with zero internet egress.

## Features

- VPC with DNS hostnames and DNS support enabled
- Private subnets for worker nodes (conditional on `multi_az`)
- **NO public subnets** - PrivateLink API only
- **NO Internet Gateway** - No public internet access
- **NO NAT Gateways** - All traffic via VPC endpoints
- VPC endpoints for all required AWS services
- **Strict egress control** via security groups (no egress rules)
- **Network ACLs** for additional egress restrictions
- **VPC Flow Logs** to S3 for audit (optional)
- ROSA-required subnet tags

## Usage

```hcl
module "network" {
  source = "../../modules/network-egress-zero"

  name_prefix       = "my-cluster"
  vpc_cidr          = "10.0.0.0/16"
  multi_az          = true  # Automatically uses first 3 available AZs
  # subnet_cidr_size is automatically calculated (will be /18 for multi-AZ with /16 VPC)
  flow_log_s3_bucket = "my-org-vpc-flow-logs"  # Optional

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
| flow_log_s3_bucket | S3 bucket name for VPC Flow Logs (optional) | `string` | `null` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | ID of the VPC |
| vpc_cidr_block | CIDR block of the VPC |
| private_subnet_ids | List of private subnet IDs |
| vpc_endpoint_ids | Map of VPC endpoint service names to endpoint IDs |
| security_group_id | ID of the security group for worker nodes with strict egress control |

## ROSA Requirements

This module automatically applies ROSA-required tags to private subnets:

- **Private Subnets**: `kubernetes.io/role/internal-elb = "1"`

## Security Features

### Strict Egress Control

- **Security Groups**: Limited egress rules (HTTPS 443 and DNS 53 to VPC CIDR) - all egress must go through VPC endpoints
- **Network ACLs**: Only allow HTTPS (443) and DNS (53) outbound to VPC CIDR, deny all other egress
- **VPC Flow Logs**: Optional audit logging to S3 for compliance

**Note**: Worker node security group includes HTTPS and DNS egress to VPC CIDR to allow communication with VPC endpoints. This is required for nodes to pull container images from ECR via VPC endpoints.

### Network ACL Rules

**Inbound**:
- Allow all traffic from VPC CIDR
- Allow ephemeral ports (1024-65535) for return traffic

**Outbound**:
- Allow HTTPS (443) to VPC CIDR (for VPC endpoints)
- Allow DNS (53) to VPC CIDR
- Deny all other egress

## Architecture Notes

- This is the **most restrictive topology** - no internet egress allowed
- All external access must go through VPC endpoints or approved proxies
- Suitable for high-security production environments
- Requires PrivateLink for API access
- VPC Flow Logs provide audit trail for compliance

## VPC Endpoints

The module creates the same VPC endpoints as the private module:

- **S3** (Gateway): No cost, no data transfer charges
- **ECR Docker API** (Interface): Required for pulling container images
- **ECR API** (Interface): Required for ECR API operations
- **CloudWatch Logs** (Interface): Required for log shipping
- **CloudWatch Monitoring** (Interface): Required for metrics
- **STS** (Interface): Required for IAM role assumption

## VPC Flow Logs

If `flow_log_s3_bucket` is provided, the module creates:

- IAM role for VPC Flow Logs
- IAM policy with permissions to write to S3
- VPC Flow Log resource pointing to the S3 bucket

Flow logs capture all IP traffic for audit and security analysis.
