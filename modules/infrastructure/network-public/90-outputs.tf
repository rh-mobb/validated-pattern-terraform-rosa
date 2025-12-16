output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
  sensitive   = false
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
  sensitive   = false
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
  sensitive   = false
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
  sensitive   = false
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs (one per AZ)"
  value       = aws_nat_gateway.main[*].id
  sensitive   = false
}

output "nat_gateway_id" {
  description = "ID of the first NAT Gateway (for backwards compatibility)"
  value       = length(aws_nat_gateway.main) > 0 ? aws_nat_gateway.main[0].id : null
  sensitive   = false
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
  sensitive   = false
}

output "vpc_endpoint_ids" {
  description = "Map of VPC endpoint service names to endpoint IDs"
  value = {
    s3      = aws_vpc_endpoint.s3.id
    ecr_dkr = aws_vpc_endpoint.ecr_dkr.id
    ecr_api = aws_vpc_endpoint.ecr_api.id
    sts     = aws_vpc_endpoint.sts.id
  }
  sensitive = false
}

output "private_subnet_azs" {
  description = "List of availability zones used for private subnets"
  value       = aws_subnet.private[*].availability_zone
  sensitive   = false
}

output "public_subnet_azs" {
  description = "List of availability zones used for public subnets"
  value       = aws_subnet.public[*].availability_zone
  sensitive   = false
}
