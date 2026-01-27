output "bastion_instance_id" {
  description = "Instance ID of the bastion host (for SSM Session Manager access, null if persists_through_sleep is false)"
  value       = length(aws_instance.bastion) > 0 ? one(aws_instance.bastion[*].id) : null
  sensitive   = false
}

output "bastion_public_ip" {
  description = "Public IP address of the bastion host (only set if bastion_public_ip is true, null if persists_through_sleep is false)"
  value       = length(aws_instance.bastion) > 0 && var.bastion_public_ip ? one(aws_instance.bastion[*].public_ip) : null
  sensitive   = false
}

output "bastion_private_ip" {
  description = "Private IP address of the bastion host (null if persists_through_sleep is false)"
  value       = length(aws_instance.bastion) > 0 ? one(aws_instance.bastion[*].private_ip) : null
  sensitive   = false
}

output "bastion_security_group_id" {
  description = "Security group ID of the bastion host (null if persists_through_sleep is false)"
  value       = length(aws_security_group.bastion) > 0 ? one(aws_security_group.bastion[*].id) : null
  sensitive   = false
}

output "ssh_command" {
  description = "SSH command to connect to bastion (only if bastion_public_ip is true, null if persists_through_sleep is false)"
  value       = length(aws_instance.bastion) > 0 && var.bastion_public_ip ? "ssh ec2-user@${one(aws_instance.bastion[*].public_ip)}" : null
  sensitive   = false
}

output "ssm_session_command" {
  description = "AWS SSM Session Manager command to connect to bastion (null if persists_through_sleep is false)"
  value       = length(aws_instance.bastion) > 0 ? "aws ssm start-session --target ${one(aws_instance.bastion[*].id)} --region ${var.region}" : null
  sensitive   = false
}

output "sshuttle_command" {
  description = "sshuttle command to create VPN-like access to VPC via bastion (null if persists_through_sleep is false)"
  value = length(aws_instance.bastion) > 0 ? (
    var.bastion_public_ip ? (
      "sshuttle --remote ec2-user@${one(aws_instance.bastion[*].public_ip)} --dns ${var.vpc_cidr}"
      ) : (
      "sshuttle --ssh-cmd=\"ssh -o ProxyCommand='sh -c \\\"aws --region ${var.region} ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=22\\\"'\" --remote ec2-user@${one(aws_instance.bastion[*].id)} --dns ${var.vpc_cidr}"
    )
  ) : null
  sensitive = false
}

output "ssh_tunnel_command" {
  description = "SSH tunnel command to forward local port 6443 to cluster API via bastion (null if persists_through_sleep is false)"
  value = length(aws_instance.bastion) > 0 ? (
    var.bastion_public_ip ? (
      "ssh -f -N -L 6443:<cluster-api-hostname>:443 ec2-user@${one(aws_instance.bastion[*].public_ip)}"
      ) : (
      "ssh -f -N -L 6443:<cluster-api-hostname>:443 -o ProxyCommand='aws --region ${var.region} ssm start-session --target ${one(aws_instance.bastion[*].id)} --document-name AWS-StartSSHSession --parameters portNumber=22' ec2-user@${one(aws_instance.bastion[*].id)}"
    )
  ) : null
  sensitive = false
}

output "ssm_endpoint_ids" {
  description = "Map of SSM VPC endpoint IDs created by the bastion module (empty if persists_through_sleep is false). Note: S3 endpoint is created by the network module."
  value = length(aws_vpc_endpoint.ssm) > 0 ? {
    ssm         = one(aws_vpc_endpoint.ssm[*].id)
    ec2messages = one(aws_vpc_endpoint.ec2messages[*].id)
    ssmmessages = one(aws_vpc_endpoint.ssmmessages[*].id)
  } : {}
  sensitive = false
}
