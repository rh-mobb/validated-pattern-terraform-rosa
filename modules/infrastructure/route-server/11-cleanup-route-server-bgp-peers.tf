# Cleanup route server BGP peers on destroy.
# The CUDN BGP operator registers route-server-peers at runtime when metal routers peer.
# After cluster teardown those peers can block endpoint deletion and cause Terraform to fail on
# aws_vpc_route_server_vpc_association destroy.
#
# depends_on endpoints ensures this null_resource is destroyed BEFORE endpoints (reverse of
# create order), so the destroy provisioner runs peer/endpoint cleanup first.
#
# Single implementation: scripts/cluster/cleanup-route-server-bgp-peers.sh (also callable manually).
locals {
  cleanup_route_server_bgp_peers_script = "${path.module}/../../../scripts/cluster/cleanup-route-server-bgp-peers.sh"
}

resource "null_resource" "cleanup_route_server_bgp_peers" {
  count = var.persists_through_sleep ? 1 : 0

  triggers = {
    cluster_name    = var.cluster_name
    region          = var.region
    route_server_id = aws_vpc_route_server.this[0].route_server_id
    cleanup_script  = local.cleanup_route_server_bgp_peers_script
  }

  provisioner "local-exec" {
    when    = create
    command = "echo 'Route server BGP peer cleanup registered (runs on destroy)'"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${self.triggers.cleanup_script} ${self.triggers.cluster_name}"
    environment = {
      AWS_REGION      = self.triggers.region
      ROUTE_SERVER_ID = self.triggers.route_server_id
    }
  }

  depends_on = [
    aws_vpc_route_server_endpoint.this,
    aws_vpc_route_server_propagation.private,
    aws_vpc_route_server_propagation.public,
  ]
}
