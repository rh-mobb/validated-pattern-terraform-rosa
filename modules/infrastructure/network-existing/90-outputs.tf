output "vpc_id" {
  description = "ID of the existing VPC"
  value       = data.aws_vpc.existing.id
  sensitive   = false
}

output "vpc_cidr_block" {
  description = "CIDR block of the existing VPC"
  value       = data.aws_vpc.existing.cidr_block
  sensitive   = false
}

output "private_subnet_ids" {
  description = "List of private subnet IDs (tagged with kubernetes.io/role/internal-elb)"
  value       = var.private_subnet_ids
  sensitive   = false
}

output "public_subnet_ids" {
  description = "List of public subnet IDs (tagged with kubernetes.io/role/elb, empty if not provided)"
  value       = var.public_subnet_ids
  sensitive   = false
}

output "private_subnet_azs" {
  description = "List of availability zones used for private subnets"
  value       = [for subnet in data.aws_subnet.private : subnet.availability_zone]
  sensitive   = false
}

output "public_subnet_azs" {
  description = "List of availability zones used for public subnets (empty if not provided)"
  value       = length(var.public_subnet_ids) > 0 ? [for subnet in data.aws_subnet.public : subnet.availability_zone] : []
  sensitive   = false
}

# Output for compatibility with other network modules
output "nat_gateway_ids" {
  description = "Empty list (no NAT gateways created by this module)"
  value       = []
  sensitive   = false
}

output "nat_gateway_id" {
  description = "Null (no NAT gateway created by this module)"
  value       = null
  sensitive   = false
}

output "internet_gateway_id" {
  description = "Null (no internet gateway created by this module - assumed to exist)"
  value       = null
  sensitive   = false
}

output "vpc_endpoint_ids" {
  description = "Empty map (no VPC endpoints created by this module - assumed to exist or managed separately)"
  value       = {}
  sensitive   = false
}
