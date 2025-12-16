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
  # For network-private: we only need private subnets (az_count)
  total_subnet_count = local.az_count
  # Calculate the minimum subnet size needed: find smallest power of 2 >= total_subnet_count
  subnet_size_bits            = local.total_subnet_count <= 2 ? 1 : local.total_subnet_count <= 4 ? 2 : local.total_subnet_count <= 8 ? 3 : local.total_subnet_count <= 16 ? 4 : 5
  calculated_subnet_cidr_size = var.subnet_cidr_size != null ? var.subnet_cidr_size : (local.vpc_cidr_size + local.subnet_size_bits)
  subnet_cidr_size_to_use     = local.calculated_subnet_cidr_size

  # Calculate subnet CIDRs automatically
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/modules/terraform-rosa-networking/locals.tf
  # For private-only networks, we only need private subnets
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

# Internet Gateway (required for Regional NAT Gateway)
resource "aws_internet_gateway" "main" {
  count = var.enable_nat_gateway ? 1 : 0

  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-igw"
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

# Elastic IP for Regional NAT Gateway
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? 1 : 0

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nat-eip"
  })

  depends_on = [aws_internet_gateway.main]
}

# Regional NAT Gateway (does not require public subnet)
# Note: Regional NAT Gateway automatically expands across AZs based on workload presence
# Reference: https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateways-regional.html
resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? 1 : 0

  vpc_id            = aws_vpc.main.id
  allocation_id     = aws_eip.nat[0].id
  connectivity_type = "public"
  availability_mode = "regional" # Regional NAT Gateway - no subnet required

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nat-regional"
  })

  depends_on = [aws_internet_gateway.main]
}

# Route table for private subnets
resource "aws_route_table" "private" {
  count = local.az_count

  vpc_id = aws_vpc.main.id

  # Route to Regional NAT Gateway if enabled
  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[0].id
    }
  }

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

# VPC Endpoints for AWS services
# S3 Gateway Endpoint (no cost)
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

# STS Endpoint (required for IAM roles)
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

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoint" {
  name        = "${var.name_prefix}-vpc-endpoint-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vpc-endpoint-sg"
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
