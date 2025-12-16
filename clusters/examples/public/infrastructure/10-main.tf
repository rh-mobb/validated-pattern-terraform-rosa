module "network" {
  source = "../../../../modules/infrastructure/network-public"

  name_prefix = var.cluster_name
  vpc_cidr    = var.vpc_cidr
  multi_az    = var.multi_az
  # subnet_cidr_size is automatically calculated based on VPC CIDR and number of subnets
  tags = var.tags
}

module "iam" {
  source = "../../../../modules/infrastructure/iam"

  cluster_name         = var.cluster_name
  account_role_prefix  = var.cluster_name # No trailing dash - account-iam-resources module adds it
  operator_role_prefix = var.cluster_name # No trailing dash - operator-roles module adds it
  tags                 = var.tags
}

module "cluster" {
  source = "../../../../modules/infrastructure/cluster"

  # Required: Pass outputs from Network and IAM modules
  cluster_name       = var.cluster_name
  region             = var.region
  vpc_id             = module.network.vpc_id
  vpc_cidr           = var.vpc_cidr
  subnet_ids         = concat(module.network.private_subnet_ids, module.network.public_subnet_ids)
  installer_role_arn = module.iam.installer_role_arn
  support_role_arn   = module.iam.support_role_arn
  worker_role_arn    = module.iam.worker_role_arn
  oidc_config_id     = module.iam.oidc_config_id
  oidc_endpoint_url  = module.iam.oidc_endpoint_url

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

  tags = var.tags

  # CRITICAL: Explicit dependency ensures cluster is destroyed BEFORE IAM during destroy
  # During destroy, Terraform destroys resources in reverse dependency order
  # Since cluster depends on IAM outputs, cluster will be destroyed first
  # This matches the reference implementation: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf#L136
  depends_on = [module.network, module.iam]
}

# Admin User (optional, for initial cluster access)
# This must be created in infrastructure as it's needed for configuration operations
# This can be removed once an external identity provider is configured
module "identity_admin" {
  count  = var.admin_password != null ? 1 : 0
  source = "../../../../modules/configuration/identity-admin"

  cluster_id     = module.cluster.cluster_id
  admin_password = var.admin_password

  depends_on = [module.cluster]
}

# Bastion Host (optional, for development/demo use only)
# WARNING: This bastion is provided for development and demonstration purposes only.
# For production deployments, use AWS Transit Gateway, Direct Connect, or VPN connections.
module "bastion" {
  count  = var.enable_bastion ? 1 : 0
  source = "../../../../modules/infrastructure/bastion"

  name_prefix            = var.cluster_name
  vpc_id                 = module.network.vpc_id
  subnet_id              = module.network.private_subnet_ids[0] # Use first private subnet
  private_subnet_ids     = module.network.private_subnet_ids    # All private subnets for VPC endpoints
  region                 = var.region
  vpc_cidr               = var.vpc_cidr
  bastion_public_ip      = var.bastion_public_ip
  bastion_public_ssh_key = var.bastion_public_ssh_key

  tags = var.tags

  depends_on = [module.network]
}
