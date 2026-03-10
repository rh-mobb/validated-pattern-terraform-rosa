#------------------------------------------------------------------------------
# Route Server BGP Peers
# Creates BGP peers between route server endpoints and BGP router nodes
#
# Uses data.external to wait for BGP router instances to be running,
# then creates native aws_vpc_route_server_peer resources.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Wait for BGP Router Instances
# Uses external data source to poll for running instances with bgp_router_subnet tag
#------------------------------------------------------------------------------

data "external" "wait_for_router1" {
  count   = var.enabled && length(var.private_subnet_ids) >= 1 ? 1 : 0
  program = ["bash", "${path.module}/../../../scripts/bgp/wait_for_instance.sh"]

  query = {
    tag_key   = "bgp_router_subnet"
    tag_value = "1"
    region    = var.region
    timeout_s = "3600"
    sleep_s   = "30"
  }

  depends_on = [
    aws_vpc_route_server_endpoint.subnet1_ep1,
    aws_vpc_route_server_endpoint.subnet1_ep2,
  ]
}

data "external" "wait_for_router2" {
  count   = var.enabled && length(var.private_subnet_ids) >= 2 ? 1 : 0
  program = ["bash", "${path.module}/../../../scripts/bgp/wait_for_instance.sh"]

  query = {
    tag_key   = "bgp_router_subnet"
    tag_value = "2"
    region    = var.region
    timeout_s = "3600"
    sleep_s   = "30"
  }

  depends_on = [
    aws_vpc_route_server_endpoint.subnet2_ep1,
    aws_vpc_route_server_endpoint.subnet2_ep2,
  ]
}

data "external" "wait_for_router3" {
  count   = var.enabled && length(var.private_subnet_ids) >= 3 ? 1 : 0
  program = ["bash", "${path.module}/../../../scripts/bgp/wait_for_instance.sh"]

  query = {
    tag_key   = "bgp_router_subnet"
    tag_value = "3"
    region    = var.region
    timeout_s = "3600"
    sleep_s   = "30"
  }

  depends_on = [
    aws_vpc_route_server_endpoint.subnet3_ep1,
    aws_vpc_route_server_endpoint.subnet3_ep2,
  ]
}

#------------------------------------------------------------------------------
# BGP Peers - Subnet 1 (2 endpoints x 1 router)
#------------------------------------------------------------------------------

resource "aws_vpc_route_server_peer" "subnet1_ep1" {
  count = var.enabled && length(var.private_subnet_ids) >= 1 ? 1 : 0

  route_server_endpoint_id = aws_vpc_route_server_endpoint.subnet1_ep1[0].route_server_endpoint_id
  peer_address             = data.external.wait_for_router1[0].result.private_ip
  bgp_options {
    peer_asn                = var.rosa_asn
    peer_liveness_detection = "bgp-keepalive"
  }

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-rs-subnet1-ep1-peer"
    Owner   = var.owner_tag
    Project = var.project_tag
  })
}

resource "aws_vpc_route_server_peer" "subnet1_ep2" {
  count = var.enabled && length(var.private_subnet_ids) >= 1 ? 1 : 0

  route_server_endpoint_id = aws_vpc_route_server_endpoint.subnet1_ep2[0].route_server_endpoint_id
  peer_address             = data.external.wait_for_router1[0].result.private_ip
  bgp_options {
    peer_asn                = var.rosa_asn
    peer_liveness_detection = "bgp-keepalive"
  }

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-rs-subnet1-ep2-peer"
    Owner   = var.owner_tag
    Project = var.project_tag
  })
}

#------------------------------------------------------------------------------
# BGP Peers - Subnet 2 (2 endpoints x 1 router)
#------------------------------------------------------------------------------

resource "aws_vpc_route_server_peer" "subnet2_ep1" {
  count = var.enabled && length(var.private_subnet_ids) >= 2 ? 1 : 0

  route_server_endpoint_id = aws_vpc_route_server_endpoint.subnet2_ep1[0].route_server_endpoint_id
  peer_address             = data.external.wait_for_router2[0].result.private_ip
  bgp_options {
    peer_asn                = var.rosa_asn
    peer_liveness_detection = "bgp-keepalive"
  }

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-rs-subnet2-ep1-peer"
    Owner   = var.owner_tag
    Project = var.project_tag
  })
}

resource "aws_vpc_route_server_peer" "subnet2_ep2" {
  count = var.enabled && length(var.private_subnet_ids) >= 2 ? 1 : 0

  route_server_endpoint_id = aws_vpc_route_server_endpoint.subnet2_ep2[0].route_server_endpoint_id
  peer_address             = data.external.wait_for_router2[0].result.private_ip
  bgp_options {
    peer_asn                = var.rosa_asn
    peer_liveness_detection = "bgp-keepalive"
  }

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-rs-subnet2-ep2-peer"
    Owner   = var.owner_tag
    Project = var.project_tag
  })
}

#------------------------------------------------------------------------------
# BGP Peers - Subnet 3 (2 endpoints x 1 router)
#------------------------------------------------------------------------------

resource "aws_vpc_route_server_peer" "subnet3_ep1" {
  count = var.enabled && length(var.private_subnet_ids) >= 3 ? 1 : 0

  route_server_endpoint_id = aws_vpc_route_server_endpoint.subnet3_ep1[0].route_server_endpoint_id
  peer_address             = data.external.wait_for_router3[0].result.private_ip
  bgp_options {
    peer_asn                = var.rosa_asn
    peer_liveness_detection = "bgp-keepalive"
  }

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-rs-subnet3-ep1-peer"
    Owner   = var.owner_tag
    Project = var.project_tag
  })
}

resource "aws_vpc_route_server_peer" "subnet3_ep2" {
  count = var.enabled && length(var.private_subnet_ids) >= 3 ? 1 : 0

  route_server_endpoint_id = aws_vpc_route_server_endpoint.subnet3_ep2[0].route_server_endpoint_id
  peer_address             = data.external.wait_for_router3[0].result.private_ip
  bgp_options {
    peer_asn                = var.rosa_asn
    peer_liveness_detection = "bgp-keepalive"
  }

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-rs-subnet3-ep2-peer"
    Owner   = var.owner_tag
    Project = var.project_tag
  })
}

#------------------------------------------------------------------------------
# Disable Source/Dest Check on BGP Router Nodes
# This must be done after router instances are running
# No native Terraform resource exists for modifying existing ENI source_dest_check
#------------------------------------------------------------------------------

resource "null_resource" "disable_src_dst_check" {
  count = var.enabled ? 1 : 0

  triggers = {
    cluster_name = var.cluster_name
    region       = var.region
    router1_ip   = length(var.private_subnet_ids) >= 1 ? data.external.wait_for_router1[0].result.private_ip : ""
    router2_ip   = length(var.private_subnet_ids) >= 2 ? data.external.wait_for_router2[0].result.private_ip : ""
    router3_ip   = length(var.private_subnet_ids) >= 3 ? data.external.wait_for_router3[0].result.private_ip : ""
  }

  provisioner "local-exec" {
    command     = "${path.module}/../../../scripts/bgp/disable_src_dst_check.sh"
    interpreter = ["/bin/bash"]
    environment = {
      AWS_REGION = var.region
    }
  }

  depends_on = [
    aws_vpc_route_server_peer.subnet1_ep1,
    aws_vpc_route_server_peer.subnet1_ep2,
    aws_vpc_route_server_peer.subnet2_ep1,
    aws_vpc_route_server_peer.subnet2_ep2,
    aws_vpc_route_server_peer.subnet3_ep1,
    aws_vpc_route_server_peer.subnet3_ep2,
  ]
}
