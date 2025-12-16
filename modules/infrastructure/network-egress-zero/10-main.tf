locals {
  # Determine number of AZs based on multi_az
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/modules/terraform-rosa-networking/data.tf
  az_count = var.multi_az ? 3 : 1
  azs      = slice(data.aws_availability_zones.available.names, 0, local.az_count)

  # Extract VPC CIDR components
  vpc_cidr_parts = split("/", var.vpc_cidr)
  vpc_network    = local.vpc_cidr_parts[0]
  vpc_cidr_size  = tonumber(local.vpc_cidr_parts[1])

  # Calculate subnet CIDR size automatically based on VPC CIDR and number of subnets needed
  # For network-egress-zero: we only need private subnets (az_count)
  total_subnet_count = local.az_count
  # Calculate the minimum subnet size needed: find smallest power of 2 >= total_subnet_count
  subnet_size_bits            = local.total_subnet_count <= 2 ? 1 : local.total_subnet_count <= 4 ? 2 : local.total_subnet_count <= 8 ? 3 : local.total_subnet_count <= 16 ? 4 : 5
  calculated_subnet_cidr_size = var.subnet_cidr_size != null ? var.subnet_cidr_size : (local.vpc_cidr_size + local.subnet_size_bits)
  subnet_cidr_size_to_use     = local.calculated_subnet_cidr_size

  # Calculate subnet CIDRs automatically
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/modules/terraform-rosa-networking/locals.tf
  # For egress-zero networks, we only need private subnets
  private_subnet_cidrs = [
    for index in range(local.az_count) :
    cidrsubnet(var.vpc_cidr, (local.subnet_cidr_size_to_use - local.vpc_cidr_size), index)
  ]

  # Common tags for all resources
  common_tags = merge(var.tags, {
    ManagedBy = "Terraform"
  })

  # ROSA-required tags for private subnets
  private_subnet_tags = merge(local.common_tags, {
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

# Private Subnets (for Worker Nodes)
resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.private_subnet_tags, {
    Name = "${var.name_prefix}-private-${local.azs[count.index]}"
    Type = "private"
  })

  lifecycle {
    # ROSA automatically adds tags like "kubernetes.io/cluster/{cluster_id}" to subnets
    # Ignore tag changes to prevent Terraform from removing these service-managed tags
    ignore_changes = [tags]
  }
}

# Route table for private subnets
resource "aws_route_table" "private" {
  count = local.az_count

  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-private-rt-${local.azs[count.index]}"
  })
}

# Route table associations for private subnets
resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# VPC Endpoints for AWS services (same as private module)
# S3 Gateway Endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.id}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-s3-endpoint"
  })
}

# ECR Docker API Endpoint
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ecr-dkr-endpoint"
  })
}

# ECR API Endpoint
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ecr-api-endpoint"
  })
}

# CloudWatch Logs Endpoint
resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-cloudwatch-logs-endpoint"
  })
}

# CloudWatch Monitoring Endpoint
resource "aws_vpc_endpoint" "cloudwatch_monitoring" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.monitoring"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-cloudwatch-monitoring-endpoint"
  })
}

# STS Endpoint
resource "aws_vpc_endpoint" "sts" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-sts-endpoint"
  })
}

# Security group for VPC endpoints with strict egress control
resource "aws_security_group" "vpc_endpoint" {
  name        = "${var.name_prefix}-vpc-endpoint-sg"
  description = "Security group for VPC endpoints with strict egress control"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # No egress rules - strict egress control
  # All egress must go through VPC endpoints

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vpc-endpoint-sg"
  })
}

# Security group for worker nodes with strict egress control
resource "aws_security_group" "worker_nodes" {
  name        = "${var.name_prefix}-worker-nodes-sg"
  description = "Security group for ROSA HCP worker nodes with strict egress control"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "All traffic from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # Egress rules for VPC endpoints only (strict egress control)
  # Worker nodes need HTTPS to reach VPC endpoints for ECR, STS, CloudWatch, etc.
  egress {
    description = "HTTPS to VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # DNS egress for VPC endpoint DNS resolution (UDP)
  egress {
    description = "DNS to VPC (UDP)"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  # DNS egress for VPC endpoint DNS resolution (TCP for large responses)
  egress {
    description = "DNS to VPC (TCP)"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-worker-nodes-sg"
  })
}

# Network ACLs removed - using security groups only for access control
# TODO: Investigate and implement Network ACLs for additional layer of security
# NACLs provide stateless filtering at the subnet level, which can add defense-in-depth
# Considerations:
# - NACLs are stateless (require explicit allow rules for both directions)
# - Must allow ephemeral ports for return traffic
# - Must allow DNS (UDP and TCP port 53) to VPC CIDR
# - Must allow HTTPS (443 TCP) to VPC CIDR for VPC endpoints
# - Must account for ROSA-created VPC endpoint for API server access
# - Need to handle dynamic VPC endpoint IP addresses (all within VPC CIDR)

# VPC Flow Logs (if S3 bucket provided)
resource "aws_flow_log" "vpc" {
  count = var.flow_log_s3_bucket != null ? 1 : 0

  iam_role_arn    = aws_iam_role.vpc_flow_log[0].arn
  log_destination = "arn:aws:s3:::${var.flow_log_s3_bucket}"
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vpc-flow-log"
  })
}

# IAM role for VPC Flow Logs
resource "aws_iam_role" "vpc_flow_log" {
  count = var.flow_log_s3_bucket != null ? 1 : 0

  name = "${var.name_prefix}-vpc-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vpc-flow-log-role"
  })
}

# IAM policy for VPC Flow Logs
resource "aws_iam_role_policy" "vpc_flow_log" {
  count = var.flow_log_s3_bucket != null ? 1 : 0

  name = "${var.name_prefix}-vpc-flow-log-policy"
  role = aws_iam_role.vpc_flow_log[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::${var.flow_log_s3_bucket}/*"
      }
    ]
  })
}

# Data source for current region
data "aws_region" "current" {}

# Data source for available availability zones
# Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/modules/terraform-rosa-networking/data.tf
data "aws_availability_zones" "available" {
  filter {
    name   = "region-name"
    values = [data.aws_region.current.id]
  }

  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Data source to look up ROSA-created VPC endpoint for API server access
# ROSA HCP creates a VPC endpoint for worker nodes to connect to the hosted control plane API
# This endpoint is tagged with:
# - red-hat-managed=true
# - red-hat-clustertype=rosa
# - api.openshift.com/id=<cluster_id>
# Note: VPC endpoints get IP addresses in the VPC CIDR, so the existing NACL rules
# (allowing HTTPS 443 TCP to VPC CIDR) already allow traffic to this endpoint.
data "aws_vpc_endpoint" "rosa_api" {
  count = var.cluster_id != null ? 1 : 0

  vpc_id = aws_vpc.main.id

  filter {
    name   = "tag:red-hat-managed"
    values = ["true"]
  }

  filter {
    name   = "tag:red-hat-clustertype"
    values = ["rosa"]
  }

  filter {
    name   = "tag:api.openshift.com/id"
    values = [var.cluster_id]
  }
}
