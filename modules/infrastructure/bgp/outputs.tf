#------------------------------------------------------------------------------
# BGP Module Outputs
# Note: Security groups are in a separate module (bgp-security-groups)
#------------------------------------------------------------------------------

output "enabled" {
  description = "Whether BGP is enabled"
  value       = var.enabled
}

output "route_server_asn" {
  description = "BGP AS number for AWS VPC Route Server"
  value       = var.enabled ? var.route_server_asn : null
}

output "rosa_asn" {
  description = "BGP AS number for ROSA cluster"
  value       = var.enabled ? var.rosa_asn : null
}

output "route_server_endpoint_ips" {
  description = "Route server endpoint IPs for BGP peering"
  value = var.enabled ? {
    subnet1_ep1 = length(aws_vpc_route_server_endpoint.subnet1_ep1) > 0 ? aws_vpc_route_server_endpoint.subnet1_ep1[0].eni_address : null
    subnet1_ep2 = length(aws_vpc_route_server_endpoint.subnet1_ep2) > 0 ? aws_vpc_route_server_endpoint.subnet1_ep2[0].eni_address : null
    subnet2_ep1 = length(aws_vpc_route_server_endpoint.subnet2_ep1) > 0 ? aws_vpc_route_server_endpoint.subnet2_ep1[0].eni_address : null
    subnet2_ep2 = length(aws_vpc_route_server_endpoint.subnet2_ep2) > 0 ? aws_vpc_route_server_endpoint.subnet2_ep2[0].eni_address : null
    subnet3_ep1 = length(aws_vpc_route_server_endpoint.subnet3_ep1) > 0 ? aws_vpc_route_server_endpoint.subnet3_ep1[0].eni_address : null
    subnet3_ep2 = length(aws_vpc_route_server_endpoint.subnet3_ep2) > 0 ? aws_vpc_route_server_endpoint.subnet3_ep2[0].eni_address : null
  } : null
}

output "router_ips" {
  description = "BGP router node private IPs (discovered at apply time)"
  value = var.enabled ? {
    router1 = length(data.external.wait_for_router1) > 0 ? data.external.wait_for_router1[0].result.private_ip : null
    router2 = length(data.external.wait_for_router2) > 0 ? data.external.wait_for_router2[0].result.private_ip : null
    router3 = length(data.external.wait_for_router3) > 0 ? data.external.wait_for_router3[0].result.private_ip : null
  } : null
}

output "ext_vpc_id" {
  description = "External VPC ID"
  value       = var.enabled && length(module.ext_vpc) > 0 ? module.ext_vpc[0].vpc_id : null
}

output "ext_vpc_cidr" {
  description = "External VPC CIDR"
  value       = var.enabled ? var.ext_vpc_cidr : null
}

output "tgw_id" {
  description = "Transit Gateway ID"
  value       = var.enabled && length(module.tgw) > 0 ? module.tgw[0].ec2_transit_gateway_id : null
}

output "ext_bastion_instance_id" {
  description = "External VPC bastion instance ID"
  value       = var.enabled && length(module.ext_bastion) > 0 ? module.ext_bastion[0].bastion_instance_id : null
}

output "ext_bastion_private_ip" {
  description = "External VPC bastion private IP"
  value       = var.enabled && length(module.ext_bastion) > 0 ? module.ext_bastion[0].bastion_private_ip : null
}

output "ext_bastion_ssm_command" {
  description = "SSM command to connect to external VPC bastion"
  value       = var.enabled && length(module.ext_bastion) > 0 ? module.ext_bastion[0].ssm_session_command : null
}
