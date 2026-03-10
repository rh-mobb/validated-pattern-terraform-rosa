#------------------------------------------------------------------------------
# Transit Gateway for ROSA VPC to External VPC Connectivity
#------------------------------------------------------------------------------

module "tgw" {
  count   = var.enabled ? 1 : 0
  source  = "terraform-aws-modules/transit-gateway/aws"
  version = "~> 2.0"

  name        = "${var.cluster_name}-bgp-tgw"
  description = "Transit Gateway for BGP testing between ROSA and external VPC"

  enable_auto_accept_shared_attachments = true

  vpc_attachments = {
    rosa = {
      vpc_id     = var.vpc_id
      subnet_ids = var.private_subnet_ids
      tags = {
        Name = "${var.cluster_name}-tgw-rosa-attach"
      }
    }
    ext = {
      vpc_id     = module.ext_vpc[0].vpc_id
      subnet_ids = module.ext_vpc[0].private_subnet_ids
      tags = {
        Name = "${var.cluster_name}-tgw-ext-attach"
      }
    }
  }

  tags = merge(var.tags, {
    Owner   = var.owner_tag
    Project = var.project_tag
  })
}

#------------------------------------------------------------------------------
# Static routes in TGW for CUDN CIDRs -> ROSA VPC
# TGW doesn't automatically learn CUDN routes because they're virtual networks
# inside the cluster, not actual AWS subnets. We need static routes.
#------------------------------------------------------------------------------

data "aws_ec2_transit_gateway_route_table" "main" {
  count = var.enabled ? 1 : 0

  filter {
    name   = "transit-gateway-id"
    values = [module.tgw[0].ec2_transit_gateway_id]
  }

  filter {
    name   = "default-association-route-table"
    values = ["true"]
  }

  depends_on = [module.tgw]
}

# TGW routes for each CUDN CIDR
resource "aws_ec2_transit_gateway_route" "cudn" {
  count = var.enabled ? length(var.cudn_cidrs) : 0

  destination_cidr_block         = var.cudn_cidrs[count.index]
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.main[0].id
  transit_gateway_attachment_id  = module.tgw[0].ec2_transit_gateway_vpc_attachment["rosa"].id

  depends_on = [module.tgw]
}

#------------------------------------------------------------------------------
# Routes from ROSA VPC to External VPC via Transit Gateway
#------------------------------------------------------------------------------

# Routes in ROSA private route tables to ext VPC
resource "aws_route" "rosa_to_ext_private" {
  count = var.enabled ? length(var.private_subnet_ids) : 0

  route_table_id         = data.aws_route_table.rosa_vpc_private[count.index].route_table_id
  destination_cidr_block = var.ext_vpc_cidr
  transit_gateway_id     = module.tgw[0].ec2_transit_gateway_id

  depends_on = [module.tgw]
}

# Routes in ROSA public route tables to ext VPC
# Note: Public subnets typically share a single route table, so we only create 1 route
# to avoid "RouteAlreadyExists" errors
resource "aws_route" "rosa_to_ext_public" {
  count = var.enabled && length(var.public_subnet_ids) > 0 ? 1 : 0

  route_table_id         = data.aws_route_table.rosa_vpc_public[0].route_table_id
  destination_cidr_block = var.ext_vpc_cidr
  transit_gateway_id     = module.tgw[0].ec2_transit_gateway_id

  depends_on = [module.tgw]
}

#------------------------------------------------------------------------------
# Routes from External VPC to ROSA VPC CIDR via Transit Gateway
# Note: ext_vpc uses multi_az=true so it has same AZ count as ROSA VPC
#------------------------------------------------------------------------------

resource "aws_route" "ext_to_rosa" {
  count = var.enabled ? length(var.availability_zones) : 0

  route_table_id         = module.ext_vpc[0].private_route_table_ids[count.index]
  destination_cidr_block = var.rosa_vpc_cidr
  transit_gateway_id     = module.tgw[0].ec2_transit_gateway_id

  depends_on = [module.tgw, module.ext_vpc]
}

#------------------------------------------------------------------------------
# Routes from External VPC to CUDN CIDRs via Transit Gateway
# Creates routes for each combination of (ext VPC route table, CUDN CIDR)
#------------------------------------------------------------------------------

locals {
  # Calculate total number of routes needed: ext_vpc_subnets * cudn_cidrs
  # ext_vpc has same AZ count as ROSA VPC (multi_az=true)
  ext_vpc_subnet_count     = length(var.availability_zones)
  ext_vpc_cudn_route_count = var.enabled ? local.ext_vpc_subnet_count * length(var.cudn_cidrs) : 0
}

resource "aws_route" "ext_to_cudn" {
  count = local.ext_vpc_cudn_route_count

  # Calculate which route table and CIDR this route is for
  # index = (subnet_index * num_cidrs) + cidr_index
  route_table_id         = module.ext_vpc[0].private_route_table_ids[floor(count.index / length(var.cudn_cidrs))]
  destination_cidr_block = var.cudn_cidrs[count.index % length(var.cudn_cidrs)]
  transit_gateway_id     = module.tgw[0].ec2_transit_gateway_id

  depends_on = [module.tgw, module.ext_vpc]
}
