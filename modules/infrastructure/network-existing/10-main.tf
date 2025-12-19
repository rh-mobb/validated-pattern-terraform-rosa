locals {
  # Combine all subnet IDs for reference
  all_subnet_ids = concat(var.private_subnet_ids, var.public_subnet_ids)
}

# Data source to fetch VPC information (for validation and outputs)
data "aws_vpc" "existing" {
  id = var.vpc_id
}

# Data sources to fetch subnet information (for validation and outputs)
data "aws_subnet" "private" {
  count = length(var.private_subnet_ids)
  id    = var.private_subnet_ids[count.index]
}

data "aws_subnet" "public" {
  count = length(var.public_subnet_ids)
  id    = var.public_subnet_ids[count.index]
}

# Tag private subnets with ROSA-required tags
# Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html-single/install_clusters/index
resource "aws_ec2_tag" "private_subnets" {
  count = length(var.private_subnet_ids)

  resource_id = var.private_subnet_ids[count.index]
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}

# Tag public subnets with ROSA-required tags (if provided)
resource "aws_ec2_tag" "public_subnets" {
  count = length(var.public_subnet_ids)

  resource_id = var.public_subnet_ids[count.index]
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

# Apply additional common tags to private subnets
# aws_ec2_tag only supports key/value pairs, so we need separate resources for each tag
resource "aws_ec2_tag" "private_subnets_name" {
  for_each = {
    for idx, subnet_id in var.private_subnet_ids : subnet_id => data.aws_subnet.private[idx].availability_zone
  }

  resource_id = each.key
  key         = "Name"
  value       = "${var.name_prefix}-private-${each.value}"
}

resource "aws_ec2_tag" "private_subnets_type" {
  for_each = toset(var.private_subnet_ids)

  resource_id = each.value
  key         = "Type"
  value       = "private"
}

resource "aws_ec2_tag" "private_subnets_managed_by" {
  for_each = toset(var.private_subnet_ids)

  resource_id = each.value
  key         = "ManagedBy"
  value       = "Terraform"
}

# Apply custom tags to private subnets
resource "aws_ec2_tag" "private_subnets_custom" {
  for_each = {
    for pair in flatten([
      for subnet_id in var.private_subnet_ids : [
        for tag_key, tag_value in var.tags : {
          subnet_id = subnet_id
          tag_key   = tag_key
          tag_value = tag_value
        }
      ]
    ]) : "${pair.subnet_id}-${pair.tag_key}" => pair
  }

  resource_id = each.value.subnet_id
  key         = each.value.tag_key
  value       = each.value.tag_value
}

# Apply additional common tags to public subnets (if provided)
resource "aws_ec2_tag" "public_subnets_name" {
  for_each = length(var.public_subnet_ids) > 0 ? {
    for idx, subnet_id in var.public_subnet_ids : subnet_id => data.aws_subnet.public[idx].availability_zone
  } : {}

  resource_id = each.key
  key         = "Name"
  value       = "${var.name_prefix}-public-${each.value}"
}

resource "aws_ec2_tag" "public_subnets_type" {
  for_each = toset(var.public_subnet_ids)

  resource_id = each.value
  key         = "Type"
  value       = "public"
}

resource "aws_ec2_tag" "public_subnets_managed_by" {
  for_each = toset(var.public_subnet_ids)

  resource_id = each.value
  key         = "ManagedBy"
  value       = "Terraform"
}

# Apply custom tags to public subnets
resource "aws_ec2_tag" "public_subnets_custom" {
  for_each = length(var.public_subnet_ids) > 0 ? {
    for pair in flatten([
      for subnet_id in var.public_subnet_ids : [
        for tag_key, tag_value in var.tags : {
          subnet_id = subnet_id
          tag_key   = tag_key
          tag_value = tag_value
        }
      ]
    ]) : "${pair.subnet_id}-${pair.tag_key}" => pair
  } : {}

  resource_id = each.value.subnet_id
  key         = each.value.tag_key
  value       = each.value.tag_value
}
