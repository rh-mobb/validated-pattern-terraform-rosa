locals {
  # Determine if cluster persists/is active (use override if provided, else global)
  persists_through_sleep = var.persists_through_sleep_network != null ? var.persists_through_sleep_network : var.persists_through_sleep

  # Determine number of AZs based on multi_az
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/modules/terraform-rosa-networking/data.tf
  az_count = var.multi_az ? 3 : 1
  azs      = slice(data.aws_availability_zones.available.names, 0, local.az_count)

  # Extract VPC CIDR components
  vpc_cidr_parts = split("/", var.vpc_cidr)
  vpc_network    = local.vpc_cidr_parts[0]
  vpc_cidr_size  = tonumber(local.vpc_cidr_parts[1])

  # Calculate subnet CIDR size automatically based on VPC CIDR and number of subnets needed
  # Formula: subnet_cidr_size = vpc_cidr_size + ceil(log2(total_subnets))
  # This ensures we have enough space for all subnets
  # For network-public: we need private + public subnets (2x az_count)
  total_subnet_count = local.az_count * 2 # private + public
  # Calculate the minimum subnet size needed: find smallest power of 2 >= total_subnet_count
  # Then add that to vpc_cidr_size
  # Examples:
  #   - 2 subnets: need /17 (2^1 = 2)
  #   - 3 subnets: need /18 (2^2 = 4 >= 3)
  #   - 6 subnets: need /19 (2^3 = 8 >= 6)
  subnet_size_bits            = local.total_subnet_count <= 2 ? 1 : local.total_subnet_count <= 4 ? 2 : local.total_subnet_count <= 8 ? 3 : local.total_subnet_count <= 16 ? 4 : 5
  calculated_subnet_cidr_size = var.subnet_cidr_size != null ? var.subnet_cidr_size : (local.vpc_cidr_size + local.subnet_size_bits)
  subnet_cidr_size_to_use     = local.calculated_subnet_cidr_size

  # Calculate subnet CIDRs automatically
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/modules/terraform-rosa-networking/locals.tf
  # Calculate all subnet CIDRs in sequence: private subnets first, then public subnets
  all_subnet_cidrs = [
    for index in range(local.total_subnet_count) :
    cidrsubnet(var.vpc_cidr, (local.subnet_cidr_size_to_use - local.vpc_cidr_size), index)
  ]

  # Split into private and public subnets
  private_subnet_cidrs = slice(local.all_subnet_cidrs, 0, local.az_count)
  public_subnet_cidrs  = slice(local.all_subnet_cidrs, local.az_count, local.total_subnet_count)

  # Common tags for all resources
  common_tags = merge(var.tags, {
    ManagedBy = "Terraform"
  })

  # ROSA-required tags
  private_subnet_tags = merge(local.common_tags, {
    "kubernetes.io/role/internal-elb" = "1"
  })

  public_subnet_tags = merge(local.common_tags, {
    "kubernetes.io/role/elb" = "1"
  })
}

# VPC
resource "aws_vpc" "main" {
  count = local.persists_through_sleep ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

# Internet Gateway (required for public subnets and NAT Gateways)
resource "aws_internet_gateway" "main" {
  count = local.persists_through_sleep ? 1 : 0

  vpc_id = one(aws_vpc.main[*].id)

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-igw"
  })
}

# Private Subnets (for Worker Nodes)
resource "aws_subnet" "private" {
  count = local.persists_through_sleep ? local.az_count : 0

  vpc_id            = one(aws_vpc.main[*].id)
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

# Public Subnets (for NAT Gateways and load balancers)
resource "aws_subnet" "public" {
  count = local.persists_through_sleep ? local.az_count : 0

  vpc_id                  = one(aws_vpc.main[*].id)
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.public_subnet_tags, {
    Name = "${var.name_prefix}-public-${local.azs[count.index]}"
    Type = "public"
  })

  lifecycle {
    # ROSA automatically adds tags like "kubernetes.io/cluster/{cluster_id}" to subnets
    # Ignore tag changes to prevent Terraform from removing these service-managed tags
    ignore_changes = [tags]
  }
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count = local.persists_through_sleep && var.enable_nat_gateway ? local.az_count : 0

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nat-eip-${local.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateways (one per AZ)
resource "aws_nat_gateway" "main" {
  count = local.persists_through_sleep && var.enable_nat_gateway ? local.az_count : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nat-${local.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.main]
}

# Route table for public subnets
resource "aws_route_table" "public" {
  count = local.persists_through_sleep ? 1 : 0

  vpc_id = one(aws_vpc.main[*].id)

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = one(aws_internet_gateway.main[*].id)
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-public-rt"
  })
}

# Route table associations for public subnets
resource "aws_route_table_association" "public" {
  count = local.persists_through_sleep ? local.az_count : 0

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = one(aws_route_table.public[*].id)
}

# Route tables for private subnets
resource "aws_route_table" "private" {
  count = local.persists_through_sleep ? local.az_count : 0

  vpc_id = one(aws_vpc.main[*].id)

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.enable_nat_gateway && length(aws_nat_gateway.main) > 0 ? aws_nat_gateway.main[count.index].id : null
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-private-rt-${local.azs[count.index]}"
  })
}

# Route table associations for private subnets
resource "aws_route_table_association" "private" {
  count = local.persists_through_sleep ? local.az_count : 0

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# VPC Endpoints for cost optimization (S3, ECR)
resource "aws_vpc_endpoint" "s3" {
  count = local.persists_through_sleep ? 1 : 0

  vpc_id            = one(aws_vpc.main[*].id)
  service_name      = "com.amazonaws.${data.aws_region.current.id}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = length(aws_route_table.public) > 0 && length(aws_route_table.private) > 0 ? concat([one(aws_route_table.public[*].id)], aws_route_table.private[*].id) : []

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-s3-endpoint"
  })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  count = local.persists_through_sleep ? 1 : 0

  vpc_id              = one(aws_vpc.main[*].id)
  service_name        = "com.amazonaws.${data.aws_region.current.id}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [one(aws_security_group.vpc_endpoint[*].id)]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ecr-dkr-endpoint"
  })
}

resource "aws_vpc_endpoint" "ecr_api" {
  count = local.persists_through_sleep ? 1 : 0

  vpc_id              = one(aws_vpc.main[*].id)
  service_name        = "com.amazonaws.${data.aws_region.current.id}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [one(aws_security_group.vpc_endpoint[*].id)]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ecr-api-endpoint"
  })
}

# STS Endpoint (required for IAM roles - IRSA, OIDC provider operations)
# Even in public networks, this is beneficial for:
# - Cost optimization (avoids NAT Gateway data transfer charges)
# - Performance (lower latency, traffic stays within AWS network)
# - Security (traffic doesn't traverse the internet)
resource "aws_vpc_endpoint" "sts" {
  count = local.persists_through_sleep ? 1 : 0

  vpc_id              = one(aws_vpc.main[*].id)
  service_name        = "com.amazonaws.${data.aws_region.current.id}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [one(aws_security_group.vpc_endpoint[*].id)]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-sts-endpoint"
  })
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoint" {
  count = local.persists_through_sleep ? 1 : 0

  name        = "${var.name_prefix}-vpc-endpoint-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = one(aws_vpc.main[*].id)

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
