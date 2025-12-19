# Data sources
data "aws_region" "current" {}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

# Find latest RHEL 9 AMI
# Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/06-bastion.tf
data "aws_ami" "rhel9" {
  owners      = ["309956199498", "219670896067"] # Red Hat and AWS
  most_recent = true

  filter {
    name   = "name"
    values = ["RHEL-9*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  common_tags = merge(var.tags, {
    ManagedBy = "Terraform"
    Name      = "${var.name_prefix}-bastion"
  })
}

# IAM Role for Bastion (enables SSM Session Manager)
resource "aws_iam_role" "bastion" {
  count = var.enable_destroy == false ? 1 : 0

  name        = "${var.name_prefix}-bastion-iam-role"
  description = "IAM role for bastion host with SSM Session Manager access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# Attach SSM Managed Instance Core policy (required for Session Manager)
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  count = var.enable_destroy == false ? 1 : 0

  role       = one(aws_iam_role.bastion[*].name)
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance Profile for Bastion
resource "aws_iam_instance_profile" "bastion" {
  count = var.enable_destroy == false ? 1 : 0

  name = "${var.name_prefix}-bastion-instance-profile"
  role = one(aws_iam_role.bastion[*].name)

  tags = local.common_tags
}

# SSH Key Pair for Bastion
resource "aws_key_pair" "bastion" {
  count = var.enable_destroy == false ? 1 : 0

  key_name   = "${var.name_prefix}-bastion"
  public_key = file(var.bastion_public_ssh_key)

  tags = local.common_tags
}

# Security Group for Bastion
resource "aws_security_group" "bastion" {
  count = var.enable_destroy == false ? 1 : 0

  name        = "${var.name_prefix}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = var.vpc_id

  # SSH access - only needed if bastion_public_ip is true
  # When using SSM Session Manager, this ingress rule is not required
  ingress {
    description = "SSH from anywhere (only used if bastion_public_ip is true)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.bastion_public_ip ? ["0.0.0.0/0"] : []
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-bastion-sg"
  })
}

# Security Group for SSM VPC Endpoints
resource "aws_security_group" "ssm_endpoint" {
  count = var.enable_destroy == false ? 1 : 0

  name        = "${var.name_prefix}-bastion-ssm-endpoint-sg"
  description = "Security group for SSM VPC endpoints (required for Session Manager)"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-bastion-ssm-endpoint-sg"
  })
}

# SSM Endpoint (required for SSM Session Manager)
resource "aws_vpc_endpoint" "ssm" {
  count = var.enable_destroy == false ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [one(aws_security_group.ssm_endpoint[*].id)]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-bastion-ssm-endpoint"
  })
}

# EC2 Messages Endpoint (required for SSM Session Manager)
resource "aws_vpc_endpoint" "ec2messages" {
  count = var.enable_destroy == false ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [one(aws_security_group.ssm_endpoint[*].id)]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-bastion-ec2messages-endpoint"
  })
}

# SSM Messages Endpoint (required for SSM Session Manager)
resource "aws_vpc_endpoint" "ssmmessages" {
  count = var.enable_destroy == false ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [one(aws_security_group.ssm_endpoint[*].id)]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-bastion-ssmmessages-endpoint"
  })
}

# Bastion EC2 Instance
resource "aws_instance" "bastion" {
  count = var.enable_destroy == false ? 1 : 0

  ami                         = data.aws_ami.rhel9.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [one(aws_security_group.bastion[*].id)]
  iam_instance_profile        = one(aws_iam_instance_profile.bastion[*].name)
  associate_public_ip_address = var.bastion_public_ip
  key_name                    = one(aws_key_pair.bastion[*].key_name)

  tags = local.common_tags

  user_data = <<-EOF
#!/bin/bash
set -e -x

# Install SSM Agent (required for Session Manager)
# Use curl + rpm directly to avoid dnf metadata issues in private subnets
# curl is available by default on RHEL, wget is not
curl -s https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm -o /tmp/amazon-ssm-agent.rpm
sudo rpm -Uvh /tmp/amazon-ssm-agent.rpm
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent
rm -f /tmp/amazon-ssm-agent.rpm

# Install useful system packages
sudo dnf install -y wget curl python3 python3-devel net-tools gcc libffi-devel openssl-devel jq bind-utils podman

# Install OpenShift/Kubernetes clients
wget -q https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
mkdir -p openshift
tar -zxvf openshift-client-linux.tar.gz -C openshift
sudo install openshift/oc /usr/local/bin/oc
sudo install openshift/kubectl /usr/local/bin/kubectl
rm -rf openshift openshift-client-linux.tar.gz

# Install Terraform (optional, for running Terraform from bastion)
# Uncomment if you want to run Terraform from the bastion:
# TERRAFORM_VERSION=1.6.0
# wget -q https://releases.hashicorp.com/terraform/$${TERRAFORM_VERSION}/terraform_$${TERRAFORM_VERSION}_linux_amd64.zip
# unzip terraform_$${TERRAFORM_VERSION}_linux_amd64.zip
# sudo mv terraform /usr/local/bin/
# rm terraform_$${TERRAFORM_VERSION}_linux_amd64.zip
EOF

  # Ensure SSM Agent is running before considering instance ready
  user_data_replace_on_change = true
}
