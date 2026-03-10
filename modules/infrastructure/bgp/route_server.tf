#------------------------------------------------------------------------------
# AWS VPC Route Server
# Creates a route server in the ROSA VPC for BGP peering with router nodes
#------------------------------------------------------------------------------

resource "aws_vpc_route_server" "rosa" {
  count                     = var.enabled ? 1 : 0
  amazon_side_asn           = var.route_server_asn
  persist_routes            = "disable"
  sns_notifications_enabled = false

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-route-server"
    Owner   = var.owner_tag
    Project = var.project_tag
  })
}

resource "aws_vpc_route_server_vpc_association" "rosa" {
  count           = var.enabled ? 1 : 0
  route_server_id = aws_vpc_route_server.rosa[0].route_server_id
  vpc_id          = var.vpc_id

  timeouts {
    create = "10m"
    delete = "10m"
  }
}

#------------------------------------------------------------------------------
# Route Server Propagation
# Uses count based on subnet count - handles duplicate route tables gracefully
# Note: If multiple subnets share a route table, AWS will return success for
# enabling propagation on an already-propagated route table
#------------------------------------------------------------------------------

resource "aws_vpc_route_server_propagation" "private" {
  count           = var.enabled ? length(var.private_subnet_ids) : 0
  route_server_id = aws_vpc_route_server.rosa[0].route_server_id
  route_table_id  = data.aws_route_table.rosa_vpc_private[count.index].route_table_id

  depends_on = [aws_vpc_route_server_vpc_association.rosa]
}

resource "aws_vpc_route_server_propagation" "public" {
  count           = var.enabled ? length(var.public_subnet_ids) : 0
  route_server_id = aws_vpc_route_server.rosa[0].route_server_id
  route_table_id  = data.aws_route_table.rosa_vpc_public[count.index].route_table_id

  depends_on = [aws_vpc_route_server_vpc_association.rosa]
}

#------------------------------------------------------------------------------
# Route Server Endpoints (2 per subnet for HA)
# Endpoints must be destroyed before association can be destroyed
#------------------------------------------------------------------------------

resource "aws_vpc_route_server_endpoint" "subnet1_ep1" {
  count           = var.enabled && length(var.private_subnet_ids) >= 1 ? 1 : 0
  route_server_id = aws_vpc_route_server.rosa[0].route_server_id
  subnet_id       = var.private_subnet_ids[0]

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-rs-subnet1-ep1"
    Owner   = var.owner_tag
    Project = var.project_tag
  })

  timeouts {
    create = "10m"
    delete = "10m"
  }

  depends_on = [aws_vpc_route_server_vpc_association.rosa]
}

resource "aws_vpc_route_server_endpoint" "subnet1_ep2" {
  count           = var.enabled && length(var.private_subnet_ids) >= 1 ? 1 : 0
  route_server_id = aws_vpc_route_server.rosa[0].route_server_id
  subnet_id       = var.private_subnet_ids[0]

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-rs-subnet1-ep2"
    Owner   = var.owner_tag
    Project = var.project_tag
  })

  timeouts {
    create = "10m"
    delete = "10m"
  }

  depends_on = [aws_vpc_route_server_vpc_association.rosa]
}

resource "aws_vpc_route_server_endpoint" "subnet2_ep1" {
  count           = var.enabled && length(var.private_subnet_ids) >= 2 ? 1 : 0
  route_server_id = aws_vpc_route_server.rosa[0].route_server_id
  subnet_id       = var.private_subnet_ids[1]

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-rs-subnet2-ep1"
    Owner   = var.owner_tag
    Project = var.project_tag
  })

  timeouts {
    create = "10m"
    delete = "10m"
  }

  depends_on = [aws_vpc_route_server_vpc_association.rosa]
}

resource "aws_vpc_route_server_endpoint" "subnet2_ep2" {
  count           = var.enabled && length(var.private_subnet_ids) >= 2 ? 1 : 0
  route_server_id = aws_vpc_route_server.rosa[0].route_server_id
  subnet_id       = var.private_subnet_ids[1]

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-rs-subnet2-ep2"
    Owner   = var.owner_tag
    Project = var.project_tag
  })

  timeouts {
    create = "10m"
    delete = "10m"
  }

  depends_on = [aws_vpc_route_server_vpc_association.rosa]
}

resource "aws_vpc_route_server_endpoint" "subnet3_ep1" {
  count           = var.enabled && length(var.private_subnet_ids) >= 3 ? 1 : 0
  route_server_id = aws_vpc_route_server.rosa[0].route_server_id
  subnet_id       = var.private_subnet_ids[2]

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-rs-subnet3-ep1"
    Owner   = var.owner_tag
    Project = var.project_tag
  })

  timeouts {
    create = "10m"
    delete = "10m"
  }

  depends_on = [aws_vpc_route_server_vpc_association.rosa]
}

resource "aws_vpc_route_server_endpoint" "subnet3_ep2" {
  count           = var.enabled && length(var.private_subnet_ids) >= 3 ? 1 : 0
  route_server_id = aws_vpc_route_server.rosa[0].route_server_id
  subnet_id       = var.private_subnet_ids[2]

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-rs-subnet3-ep2"
    Owner   = var.owner_tag
    Project = var.project_tag
  })

  timeouts {
    create = "10m"
    delete = "10m"
  }

  depends_on = [aws_vpc_route_server_vpc_association.rosa]
}
