#------------------------------------------------------------------------------
# BGP Module - Main Resources
# External VPC and data sources for route tables
#------------------------------------------------------------------------------

# Get route table for each private subnet
data "aws_route_table" "rosa_vpc_private" {
  count     = var.enabled ? length(var.private_subnet_ids) : 0
  subnet_id = var.private_subnet_ids[count.index]
}

# Get route table for each public subnet
data "aws_route_table" "rosa_vpc_public" {
  count     = var.enabled ? length(var.public_subnet_ids) : 0
  subnet_id = var.public_subnet_ids[count.index]
}

#------------------------------------------------------------------------------
# External VPC for BGP Testing (using network-private module)
#------------------------------------------------------------------------------
module "ext_vpc" {
  count  = var.enabled ? 1 : 0
  source = "../network-private"

  name_prefix        = "${var.cluster_name}-bgp-ext"
  vpc_cidr           = var.ext_vpc_cidr
  multi_az           = true
  availability_zones = var.availability_zones # Pin AZs to match ROSA VPC

  # Network infrastructure configuration
  enable_nat_gateway = true
  zero_egress        = false

  tags = merge(var.tags, {
    Owner   = var.owner_tag
    Project = var.project_tag
    Purpose = "BGP-External-VPC"
  })

  persists_through_sleep         = var.persists_through_sleep
  persists_through_sleep_network = var.persists_through_sleep_network
}

#------------------------------------------------------------------------------
# Bastion Host in External VPC
#------------------------------------------------------------------------------
module "ext_bastion" {
  count  = var.enabled ? 1 : 0
  source = "../bastion"

  name_prefix            = "${var.cluster_name}-bgp-ext"
  vpc_id                 = module.ext_vpc[0].vpc_id
  vpc_cidr               = var.ext_vpc_cidr
  subnet_id              = module.ext_vpc[0].private_subnet_ids[0]
  private_subnet_ids     = module.ext_vpc[0].private_subnet_ids
  bastion_public_ip      = false
  bastion_public_ssh_key = var.bastion_public_ssh_key
  region                 = var.region

  tags = merge(var.tags, {
    Owner   = var.owner_tag
    Project = var.project_tag
    Purpose = "BGP-External-VPC-Bastion"
  })

  depends_on = [module.ext_vpc]
}
