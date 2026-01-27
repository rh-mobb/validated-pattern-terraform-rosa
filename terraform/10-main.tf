# Infer egress-zero mode: private network with strict egress enabled
locals {
  # Egress-zero mode: private network with strict egress enabled
  is_egress_zero = var.network_type == "private" && var.enable_strict_egress
}

# Network Module - conditionally select public or private based on network_type
# Note: Terraform requires the source to be a literal string, so we use separate module blocks with count
module "network_public" {
  count  = var.network_type == "public" ? 1 : 0
  source = "../modules/infrastructure/network-public"

  name_prefix = var.cluster_name
  vpc_cidr    = var.vpc_cidr
  multi_az    = var.multi_az
  # subnet_cidr_size is automatically calculated based on VPC CIDR and number of subnets

  tags                           = local.tags
  persists_through_sleep         = var.persists_through_sleep
  persists_through_sleep_network = var.persists_through_sleep_network
}

module "network_private" {
  count  = var.network_type == "private" ? 1 : 0
  source = "../modules/infrastructure/network-private"

  name_prefix = var.cluster_name
  vpc_cidr    = var.vpc_cidr
  multi_az    = var.multi_az
  # subnet_cidr_size is automatically calculated based on VPC CIDR and number of subnets

  # For egress-zero: disable NAT Gateway and enable strict egress
  # For private: enable NAT Gateway (default) unless strict egress is enabled
  enable_nat_gateway   = !local.is_egress_zero
  enable_strict_egress = local.is_egress_zero
  flow_log_s3_bucket   = var.flow_log_s3_bucket
  cluster_id           = null # Can be set after cluster creation

  tags                           = local.tags
  persists_through_sleep         = var.persists_through_sleep
  persists_through_sleep_network = var.persists_through_sleep_network
}

# Create a local to reference the active network module
locals {
  network = var.network_type == "public" ? module.network_public[0] : module.network_private[0]
}

# Additional machine pools - resolve subnet_index to actual subnet IDs
locals {
  # Resolve subnet_index to actual subnet IDs from network module
  # Only resolve when destroy is disabled (resources will be created)
  # Remove subnet_index and add subnet_id for the cluster module
  additional_machine_pools_resolved = var.persists_through_sleep && length(local.network.private_subnet_ids) > 0 ? {
    for pool_name, pool_config in var.additional_machine_pools : pool_name => merge(
      {
        for k, v in pool_config : k => v if k != "subnet_index"
      },
      {
        subnet_id = local.network.private_subnet_ids[pool_config.subnet_index]
      }
    )
  } : {}
}

module "iam" {
  source = "../modules/infrastructure/iam"

  cluster_name               = var.cluster_name
  account_role_prefix        = var.cluster_name     # No trailing dash - account-iam-resources module adds it
  operator_role_prefix       = var.cluster_name     # No trailing dash - operator-roles module adds it
  zero_egress                = local.is_egress_zero # Enable zero egress mode for egress-zero clusters
  tags                       = local.tags
  persists_through_sleep     = var.persists_through_sleep
  persists_through_sleep_iam = var.persists_through_sleep_iam
}

module "cluster" {
  source = "../modules/infrastructure/cluster"

  cluster_name = var.cluster_name
  region       = var.region
  vpc_id       = local.network.vpc_id
  vpc_cidr     = var.vpc_cidr

  # Subnet selection - pass private and public separately, cluster module will concatenate
  # Public clusters use both private and public subnets
  # Private and egress-zero clusters use only private subnets
  private_subnet_ids = local.network.private_subnet_ids
  public_subnet_ids  = var.network_type == "public" ? local.network.public_subnet_ids : []

  installer_role_arn             = module.iam.installer_role_arn
  support_role_arn               = module.iam.support_role_arn
  worker_role_arn                = module.iam.worker_role_arn
  oidc_config_id                 = module.iam.oidc_config_id    # OIDC is never gated
  oidc_endpoint_url              = module.iam.oidc_endpoint_url # OIDC is never gated
  enable_persistent_dns_domain   = var.enable_persistent_dns_domain
  persists_through_sleep         = var.persists_through_sleep
  persists_through_sleep_cluster = var.persists_through_sleep_cluster

  # Cluster configuration based on network type
  private            = var.network_type != "public"
  zero_egress        = local.is_egress_zero
  multi_az           = var.multi_az
  availability_zones = local.network.private_subnet_azs

  # Identity provider configuration
  enable_identity_provider     = var.persists_through_sleep
  admin_username               = var.admin_username
  admin_password_for_bootstrap = var.admin_password_override != null ? var.admin_password_override : random_password.admin_password[0].result

  # Production features (for egress-zero and optionally private)
  # Cluster module will create its own KMS key if enable_storage is true
  kms_key_arn = var.kms_key_arn

  # Storage configuration - cluster module creates KMS keys and EFS
  enable_storage       = true
  enable_efs           = var.enable_efs != null ? var.enable_efs : true
  private_subnet_cidrs = local.network.private_subnet_cidrs

  # GitOps bootstrap configuration
  enable_gitops_bootstrap = var.enable_gitops_bootstrap != null ? var.enable_gitops_bootstrap : false
  # admin_password_for_bootstrap is set above in identity provider configuration
  # Storage resources are automatically available from cluster module outputs
  ebs_kms_key_arn    = null # Will use cluster module's created KMS key
  efs_file_system_id = null # Will use cluster module's created EFS
  # GitOps repository configuration
  git_path            = var.gitops_git_path
  gitops_git_repo_url = var.gitops_git_repo_url

  # Cert Manager, Termination Protection, and CloudWatch Logging
  enable_cert_manager_iam       = var.enable_cert_manager_iam
  enable_termination_protection = var.enable_termination_protection
  enable_cloudwatch_logging     = var.enable_cloudwatch_logging
  enable_secrets_manager_iam    = var.enable_secrets_manager_iam
  additional_secrets            = var.additional_secrets
  openshift_version             = var.openshift_version
  service_cidr                  = var.service_cidr
  pod_cidr                      = var.pod_cidr
  host_prefix                   = var.host_prefix

  # Machine pools - conditional based on network type
  # Public clusters have explicit machine_pools configuration
  # Egress-zero clusters use module defaults (empty array, uses default_instance_type, etc.)
  machine_pools = var.network_type == "public" ? [
    {
      name                = "workers" # Must match ROSA's default pool name
      instance_type       = var.instance_type
      min_replicas        = var.multi_az ? 3 : 2 # 3 for multi-AZ, 2 for single AZ
      max_replicas        = var.multi_az ? 6 : 4 # Double min replicas
      multi_az            = var.multi_az
      autoscaling_enabled = true
    }
  ] : [] # Empty for egress-zero (uses module defaults)

  # For egress-zero: use default_instance_type, default_min_replicas, default_max_replicas
  # These are only used when machine_pools is empty
  default_instance_type = local.is_egress_zero ? var.instance_type : null
  default_min_replicas  = local.is_egress_zero ? 1 : null # Minimum for HA (multi-AZ: 1 per subnet)
  default_max_replicas  = local.is_egress_zero ? 3 : null # Double min replicas

  # Additional machine pools - resolved with actual subnet IDs
  additional_machine_pools = {
    for pool_name, pool_config in local.additional_machine_pools_resolved : pool_name => {
      subnet_id                     = pool_config.subnet_id
      instance_type                 = pool_config.instance_type
      autoscaling_enabled           = pool_config.autoscaling_enabled
      min_replicas                  = pool_config.min_replicas
      max_replicas                  = pool_config.max_replicas
      replicas                      = pool_config.replicas
      auto_repair                   = pool_config.auto_repair
      labels                        = pool_config.labels
      taints                        = pool_config.taints
      additional_security_group_ids = pool_config.additional_security_group_ids
      capacity_reservation_id       = pool_config.capacity_reservation_id
      disk_size                     = pool_config.disk_size
      ec2_metadata_http_tokens      = pool_config.ec2_metadata_http_tokens
      tags                          = pool_config.tags
      version                       = pool_config.version
      upgrade_acknowledgements_for  = pool_config.upgrade_acknowledgements_for
      kubelet_configs               = pool_config.kubelet_configs
      tuning_configs                = pool_config.tuning_configs
      ignore_deletion_error         = pool_config.ignore_deletion_error
    }
  }

  # Egress-zero specific settings
  # Egress-zero clusters may take longer for nodes to start due to network connectivity
  # Set to false to allow cluster creation to complete even if nodes are still starting
  wait_for_std_compute_nodes_complete = local.is_egress_zero ? false : true

  # Optional: Allow API endpoint access from additional IPv4 CIDR blocks
  # By default, the VPC endpoint security group only allows access from within the VPC
  # Uncomment and configure to allow access from VPN ranges, bastion hosts, or other VPCs
  # For egress-zero clusters, this is useful for allowing access from VPN or Transit Gateway connected networks
  # api_endpoint_allowed_cidrs = [
  #   "10.0.0.0/32",      # Example: Specific IP (e.g., bastion host via SSM Session Manager)
  #   "192.168.1.0/24"   # Example: VPN range or Transit Gateway connected VPC CIDR
  # ]

  tags = var.tags

  # CRITICAL: Explicit dependency ensures cluster is destroyed BEFORE IAM during destroy
  # During destroy, Terraform destroys resources in reverse dependency order
  # Since cluster depends on IAM outputs, cluster will be destroyed first
  # This matches the reference implementation: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf#L136
  depends_on = [module.network_public, module.network_private, module.iam]
}

# Admin Password Management
# Generate random password if override is not provided
# Store password in AWS Secrets Manager for secure access
resource "random_password" "admin_password" {
  count = var.admin_password_override == null ? 1 : 0

  length           = 20
  special          = true
  upper            = true
  lower            = true
  numeric          = true
  override_special = "@#&*-_"

  # Ensure password meets ROSA requirements:
  # - 14+ characters (we use 20)
  # - Contains uppercase letter (upper = true)
  # - Contains symbol or number (special = true, numeric = true)
}

# AWS Secrets Manager secret for admin password
# Stores either the override password or the generated random password
#
# Admin Password Secret (stored in AWS Secrets Manager)
# This secret persists through sleep operations to preserve credentials for cluster restart.
# Recovery window is set to 0 to disable the 7-30 day recovery period.
# This allows immediate deletion and recreation of secrets with the same name if needed.
resource "aws_secretsmanager_secret" "admin_password" {
  # Always create secret (persists through sleep for easy cluster restart)
  # Secret persists even when persists_through_sleep=false (sleep operation)
  count = 1

  name        = "rosa-hcp-${var.cluster_name}-admin-password"
  description = "Admin password for ROSA HCP cluster ${var.cluster_name} (persists through sleep)"

  # Set recovery window to 0 to disable the recovery period (default is 30 days)
  # This allows immediate deletion and recreation of secrets with the same name
  recovery_window_in_days = 0

  tags = merge(local.tags, {
    Name                   = "rosa-hcp-${var.cluster_name}-admin-password"
    Cluster                = var.cluster_name
    ManagedBy              = "Terraform"
    Purpose                = "ClusterAdminPassword"
    persists_through_sleep = "true"
  })
}

# Store the password in the secret
# Only create/update secret version when cluster exists (not during sleep)
resource "aws_secretsmanager_secret_version" "admin_password" {
  count = var.persists_through_sleep ? 1 : 0

  secret_id     = aws_secretsmanager_secret.admin_password[0].id
  secret_string = var.admin_password_override != null ? var.admin_password_override : random_password.admin_password[0].result

  # Allow secret to be updated manually if password changes
  lifecycle {
    ignore_changes = [
      secret_string
    ]
  }
}

# Identity provider is now created in the cluster module
# See modules/infrastructure/cluster/30-identity-provider.tf

# Bastion Host (optional, for development/demo use only)
# WARNING: This bastion is provided for development and demonstration purposes only.
# For production deployments, use AWS Transit Gateway, Direct Connect, or VPN connections.
# NOTE: For egress-zero clusters, bastion_public_ip should always be false
# The bastion module creates SSM VPC endpoints required for Session Manager access
# Only create bastion when persists_through_sleep is true and network resources exist (prevents errors during sleep)
module "bastion" {
  count  = var.enable_bastion && var.persists_through_sleep && length(local.network.private_subnet_ids) > 0 ? 1 : 0
  source = "../modules/infrastructure/bastion"

  name_prefix            = var.cluster_name
  vpc_id                 = local.network.vpc_id
  subnet_id              = local.network.private_subnet_ids[0] # Use first private subnet
  private_subnet_ids     = local.network.private_subnet_ids    # All private subnets for VPC endpoints
  region                 = var.region
  vpc_cidr               = var.vpc_cidr
  bastion_public_ip      = var.bastion_public_ip # Should be false for egress-zero
  bastion_public_ssh_key = var.bastion_public_ssh_key
  persists_through_sleep = var.persists_through_sleep

  tags = var.tags

  # Terraform will infer network module dependency from vpc_id and subnet_ids references
}
