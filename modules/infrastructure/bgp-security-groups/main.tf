#------------------------------------------------------------------------------
# BGP Security Groups Module
# Creates security groups for BGP router nodes
# This module runs BEFORE the cluster to provide security group IDs for machine pools
#------------------------------------------------------------------------------

resource "aws_security_group" "rfc1918" {
  count       = var.enabled ? 1 : 0
  name_prefix = "${var.cluster_name}-bgp-allow-rfc1918-"
  description = "Allow traffic from all IPv4 private prefixes (RFC1918)"
  vpc_id      = var.vpc_id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
    ]
    description = "Allow all traffic from RFC1918 ranges"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-bgp-allow-rfc1918"
    Owner   = var.owner_tag
    Project = var.project_tag
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "allow_all" {
  count       = var.enabled ? 1 : 0
  name_prefix = "${var.cluster_name}-bgp-allow-all-"
  description = "Allow traffic from all sources"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all inbound traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-bgp-allow-all"
    Owner   = var.owner_tag
    Project = var.project_tag
  })

  lifecycle {
    create_before_destroy = true
  }
}
