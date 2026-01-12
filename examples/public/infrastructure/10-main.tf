module "network" {
  source = "../../../modules/infrastructure/network-public"

  name_prefix = var.cluster_name
  vpc_cidr    = var.vpc_cidr
  multi_az    = var.multi_az
  # subnet_cidr_size is automatically calculated based on VPC CIDR and number of subnets
  tags                 = local.tags
  enable_destroy       = var.enable_destroy
  enable_destroy_network = var.enable_destroy_network
}

# Additional machine pools - resolve subnet_index to actual subnet IDs
locals {
  # Resolve subnet_index to actual subnet IDs from network module
  # Only resolve when destroy is disabled (resources will be created)
  # Remove subnet_index and add subnet_id for the cluster module
  additional_machine_pools_resolved = var.enable_destroy == false && length(module.network.private_subnet_ids) > 0 ? {
    for pool_name, pool_config in var.additional_machine_pools : pool_name => merge(
      {
        for k, v in pool_config : k => v if k != "subnet_index"
      },
      {
        subnet_id = module.network.private_subnet_ids[pool_config.subnet_index]
      }
    )
  } : {}
}

module "iam" {
  source = "../../../modules/infrastructure/iam"

  cluster_name         = var.cluster_name
  account_role_prefix  = var.cluster_name # No trailing dash - account-iam-resources module adds it
  operator_role_prefix = var.cluster_name # No trailing dash - operator-roles module adds it
  tags                 = local.tags
  enable_destroy       = var.enable_destroy
  enable_destroy_iam   = var.enable_destroy_iam
}

module "cluster" {
  source = "../../../modules/infrastructure/cluster"

  # Required: Pass outputs from Network and IAM modules
  cluster_name       = var.cluster_name
  region             = var.region
  vpc_id             = module.network.vpc_id
  vpc_cidr           = var.vpc_cidr
  subnet_ids         = concat(module.network.private_subnet_ids, module.network.public_subnet_ids)
  installer_role_arn = module.iam.installer_role_arn
  support_role_arn   = module.iam.support_role_arn
  worker_role_arn    = module.iam.worker_role_arn
  oidc_config_id     = module.iam.oidc_config_id # OIDC is never gated
  oidc_endpoint_url  = module.iam.oidc_endpoint_url # OIDC is never gated
  enable_persistent_dns_domain = var.enable_persistent_dns_domain
  enable_destroy     = var.enable_destroy
  enable_destroy_cluster = var.enable_destroy_cluster

  # Dev defaults - relaxed security for development
  private            = false # Public API endpoint for easier access
  etcd_encryption    = false # Dev doesn't require encryption
  availability_zones = module.network.private_subnet_azs
  multi_az           = var.multi_az

  # Machine pool configuration - smaller for dev
  # NOTE: If machine_pools is not provided, ROSA creates "workers" (plural) for single-AZ
  # For multi-AZ, ROSA creates "workers-0", "workers-1", "workers-2" (one per subnet)
  machine_pools = [
    {
      name                = "workers" # Must match ROSA's default pool name
      instance_type       = var.instance_type
      min_replicas        = var.multi_az ? 3 : 2 # 3 for multi-AZ, 2 for single AZ
      max_replicas        = var.multi_az ? 6 : 4 # Double min replicas
      multi_az            = var.multi_az
      autoscaling_enabled = true
    }
  ]

  # Additional machine pools - resolved with actual subnet IDs
  additional_machine_pools = {
    for pool_name, pool_config in local.additional_machine_pools_resolved : pool_name => {
      subnet_id                    = pool_config.subnet_id
      instance_type                = pool_config.instance_type
      autoscaling_enabled          = pool_config.autoscaling_enabled
      min_replicas                 = pool_config.min_replicas
      max_replicas                 = pool_config.max_replicas
      replicas                     = pool_config.replicas
      auto_repair                  = pool_config.auto_repair
      labels                       = pool_config.labels
      taints                       = pool_config.taints
      additional_security_group_ids = pool_config.additional_security_group_ids
      capacity_reservation_id       = pool_config.capacity_reservation_id
      disk_size                     = pool_config.disk_size
      ec2_metadata_http_tokens      = pool_config.ec2_metadata_http_tokens
      tags                          = pool_config.tags
      version                       = pool_config.version
      upgrade_acknowledgements_for  = pool_config.upgrade_acknowledgements_for
      kubelet_configs              = pool_config.kubelet_configs
      tuning_configs               = pool_config.tuning_configs
      ignore_deletion_error         = pool_config.ignore_deletion_error
    }
  }

  # Optional: Allow API endpoint access from additional IPv4 CIDR blocks
  # By default, the VPC endpoint security group only allows access from within the VPC
  # Uncomment and configure to allow access from VPN ranges, bastion hosts, or other VPCs
  # api_endpoint_allowed_cidrs = [
  #   "10.0.0.0/32",      # Example: Specific IP (e.g., bastion host)
  #   "192.168.1.0/24"   # Example: VPN range or other VPC CIDR
  # ]

  tags = var.tags

  # CRITICAL: Explicit dependency ensures cluster is destroyed BEFORE IAM during destroy
  # During destroy, Terraform destroys resources in reverse dependency order
  # Since cluster depends on IAM outputs, cluster will be destroyed first
  # This matches the reference implementation: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf#L136
  depends_on = [module.network, module.iam]
}

# Admin Password Management
# Generate random password if override is not provided
# Store password in AWS Secrets Manager for secure access
resource "random_password" "admin_password" {
  count = var.admin_password_override == null ? 1 : 0

  length  = 20
  special = true
  upper   = true
  lower   = true
  numeric = true

  # Ensure password meets ROSA requirements:
  # - 14+ characters (we use 20)
  # - Contains uppercase letter (upper = true)
  # - Contains symbol or number (special = true, numeric = true)
}

# AWS Secrets Manager secret for admin password
# Stores either the override password or the generated random password
#
# Admin Password Secret (stored in AWS Secrets Manager)
# Recovery window is set to 0 to disable the 7-30 day recovery period.
# This allows immediate deletion and recreation of secrets with the same name.
resource "aws_secretsmanager_secret" "admin_password" {
  count = var.enable_destroy == false ? 1 : 0

  name        = "rosa-hcp-${var.cluster_name}-admin-password"
  description = "Admin password for ROSA HCP cluster ${var.cluster_name}"

  # Set recovery window to 0 to disable the recovery period (default is 30 days)
  # This allows immediate deletion and recreation of secrets with the same name
  recovery_window_in_days = 0

  tags = merge(local.tags, {
    Name        = "rosa-hcp-${var.cluster_name}-admin-password"
    Cluster     = var.cluster_name
    ManagedBy   = "Terraform"
    Purpose     = "ClusterAdminPassword"
  })
}

# Store the password in the secret
resource "aws_secretsmanager_secret_version" "admin_password" {
  count = var.enable_destroy == false ? 1 : 0

  secret_id = aws_secretsmanager_secret.admin_password[0].id
  secret_string = var.admin_password_override != null ? var.admin_password_override : random_password.admin_password[0].result
}

# Admin User (optional, for initial cluster access)
# This must be created in infrastructure as it's needed for configuration operations
# This can be removed once an external identity provider is configured
# Only create if enable_destroy is false (resources should be created)
module "identity_admin" {
  count  = var.enable_destroy == false ? 1 : 0
  source = "../../../modules/infrastructure/identity-admin"

  cluster_id     = module.cluster.cluster_id
  # Use override if provided, otherwise use the random password result
  admin_password = var.admin_password_override != null ? var.admin_password_override : random_password.admin_password[0].result
  enable_destroy = var.enable_destroy

  depends_on = [
    module.cluster,
    random_password.admin_password,
    aws_secretsmanager_secret_version.admin_password
  ]
}

# Bastion Host (optional, for development/demo use only)
# WARNING: This bastion is provided for development and demonstration purposes only.
# For production deployments, use AWS Transit Gateway, Direct Connect, or VPN connections.
module "bastion" {
  # Only create bastion when enable_destroy is false and network resources exist (prevents errors during cleanup)
  count  = var.enable_bastion && var.enable_destroy == false && length(module.network.private_subnet_ids) > 0 ? 1 : 0
  source = "../../../modules/infrastructure/bastion"

  name_prefix            = var.cluster_name
  vpc_id                 = module.network.vpc_id
  subnet_id              = module.network.private_subnet_ids[0] # Use first private subnet
  private_subnet_ids     = module.network.private_subnet_ids    # All private subnets for VPC endpoints
  region                 = var.region
  vpc_cidr               = var.vpc_cidr
  bastion_public_ip      = var.bastion_public_ip
  bastion_public_ssh_key = var.bastion_public_ssh_key
  enable_destroy         = var.enable_destroy

  tags = var.tags

  depends_on = [module.network]
}
