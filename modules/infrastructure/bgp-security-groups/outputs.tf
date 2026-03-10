#------------------------------------------------------------------------------
# BGP Security Groups Module Outputs
#------------------------------------------------------------------------------

output "security_group_ids" {
  description = "List of security group IDs for BGP router machine pools"
  value = var.enabled ? concat(
    length(aws_security_group.rfc1918) > 0 ? [aws_security_group.rfc1918[0].id] : [],
    length(aws_security_group.allow_all) > 0 ? [aws_security_group.allow_all[0].id] : []
  ) : []
}

output "rfc1918_security_group_id" {
  description = "Security group ID for RFC1918 traffic"
  value       = var.enabled && length(aws_security_group.rfc1918) > 0 ? aws_security_group.rfc1918[0].id : null
}

output "allow_all_security_group_id" {
  description = "Security group ID for all traffic"
  value       = var.enabled && length(aws_security_group.allow_all) > 0 ? aws_security_group.allow_all[0].id : null
}
