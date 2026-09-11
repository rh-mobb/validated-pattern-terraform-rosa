# ROSA default worker SG: allow all VPC↔CUDN traffic for BGP e2e validation.
# ROSA opens ICMP and SSH :22 from the VPC CIDR but blocks other cross-boundary traffic
# to overlay IPs (discovered via virt external VM ping on :8080; port is not the root cause).
# Pair with bastion_enable_bgp_e2e (bastion SG allows all traffic from CUDN CIDRs).

resource "aws_vpc_security_group_ingress_rule" "bgp_e2e_vpc_all" {
  count = var.enable_bgp_e2e_worker_sg && local.persists_through_sleep ? 1 : 0

  security_group_id = data.aws_security_groups.cluster_default[0].ids[0]
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
  from_port         = -1
  to_port           = -1
  description       = "BGP e2e: all traffic from VPC CIDR (ROSA default SG blocks cross-boundary non-ICMP/SSH)"

  depends_on = [data.aws_security_groups.cluster_default]
}
