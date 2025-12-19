output "vpc_id" {
  description = "ID of the VPC (null if enable_destroy_network is true)"
  value       = length(aws_vpc.main) > 0 ? one(aws_vpc.main[*].id) : null
  sensitive   = false
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC (null if enable_destroy_network is true)"
  value       = length(aws_vpc.main) > 0 ? one(aws_vpc.main[*].cidr_block) : null
  sensitive   = false
}

output "private_subnet_ids" {
  description = "List of private subnet IDs (empty if enable_destroy_network is true)"
  value       = aws_subnet.private[*].id
  sensitive   = false
}

output "vpc_endpoint_ids" {
  description = "Map of VPC endpoint service names to endpoint IDs (empty if enable_destroy_network is true)"
  value = length(aws_vpc_endpoint.s3) > 0 ? {
    s3                    = one(aws_vpc_endpoint.s3[*].id)
    ecr_dkr               = one(aws_vpc_endpoint.ecr_dkr[*].id)
    ecr_api               = one(aws_vpc_endpoint.ecr_api[*].id)
    cloudwatch_logs       = one(aws_vpc_endpoint.cloudwatch_logs[*].id)
    cloudwatch_monitoring = one(aws_vpc_endpoint.cloudwatch_monitoring[*].id)
    sts                   = one(aws_vpc_endpoint.sts[*].id)
  } : {}
  sensitive = false
}

output "security_group_id" {
  description = "ID of the security group for worker nodes with strict egress control (null if enable_destroy_network is true)"
  value       = length(aws_security_group.worker_nodes) > 0 ? one(aws_security_group.worker_nodes[*].id) : null
  sensitive   = false
}

output "private_subnet_azs" {
  description = "List of availability zones used for private subnets (empty if enable_destroy_network is true)"
  value       = aws_subnet.private[*].availability_zone
  sensitive   = false
}

output "rosa_api_vpc_endpoint_id" {
  description = "ID of the ROSA-created VPC endpoint for API server access (if cluster_id was provided and endpoint found, null if enable_destroy_network is true)"
  value       = length(data.aws_vpc_endpoint.rosa_api) > 0 ? data.aws_vpc_endpoint.rosa_api[0].id : null
  sensitive   = false
}
