module "network" {
  source = "../../../modules/infrastructure/network-egress-zero"

  name_prefix = var.cluster_name
  vpc_cidr    = var.vpc_cidr
  multi_az    = var.multi_az
  # subnet_cidr_size is automatically calculated based on VPC CIDR and number of subnets
  flow_log_s3_bucket = var.flow_log_s3_bucket # Audit logging
  # cluster_id is optional - can be added after cluster creation to enable ROSA VPC endpoint lookup
  # Note: Cannot pass module.cluster.cluster_id here due to circular dependency (cluster depends on network)
  # After initial cluster creation, you can add: cluster_id = module.cluster.cluster_id
  tags                 = local.tags
  enable_destroy       = var.enable_destroy
  enable_destroy_network = var.enable_destroy_network
}

module "iam" {
  source = "../../../modules/infrastructure/iam"

  cluster_name         = var.cluster_name
  account_role_prefix  = var.cluster_name # No trailing dash - account-iam-resources module adds it
  operator_role_prefix = var.cluster_name # No trailing dash - operator-roles module adds it
  zero_egress          = true              # Enable zero egress mode (attaches ECR read-only policy to worker role)
  tags                 = local.tags
  enable_destroy       = var.enable_destroy
  enable_destroy_iam   = var.enable_destroy_iam
}

module "cluster" {
  source = "../../../modules/infrastructure/cluster"

  cluster_name       = var.cluster_name
  region             = var.region
  vpc_id             = module.network.vpc_id
  vpc_cidr           = var.vpc_cidr
  subnet_ids         = module.network.private_subnet_ids
  installer_role_arn = module.iam.installer_role_arn
  support_role_arn   = module.iam.support_role_arn
  worker_role_arn    = module.iam.worker_role_arn
  oidc_config_id     = module.iam.oidc_config_id # OIDC is never gated
  oidc_endpoint_url  = module.iam.oidc_endpoint_url # OIDC is never gated
  enable_persistent_dns_domain = var.enable_persistent_dns_domain
  enable_destroy     = var.enable_destroy
  enable_destroy_cluster = var.enable_destroy_cluster

  # Production hardening - maximum security
  private                    = true            # PrivateLink API only
  # etcd_encryption            = true            # Encrypt etcd data
  kms_key_arn                = var.kms_key_arn # Customer-managed KMS for encryption
  # disable_workload_monitoring = true            # Disable workload monitoring (may require internet egress)
  zero_egress                 = true            # Enable zero egress mode (egress-zero cluster)
  multi_az                   = true            # Always multi-AZ for production
  availability_zones         = module.network.private_subnet_azs

  # Egress-zero clusters may take longer for nodes to start due to network connectivity
  # Set to false to allow cluster creation to complete even if nodes are still starting
  wait_for_std_compute_nodes_complete = false

  # Pin to stable version for production
  openshift_version = var.openshift_version

  # Custom network CIDRs (if needed to avoid conflicts)
  service_cidr = var.service_cidr
  pod_cidr     = var.pod_cidr
  host_prefix  = var.host_prefix

  # Production machine pools - larger instances, proper scaling
  # NOTE: For multi-AZ, ROSA automatically creates "workers-0", "workers-1", "workers-2" (one per subnet)
  # Do NOT provide machine_pools - let the module automatically generate the correct pool names
  # The module will use default_instance_type, default_min_replicas, and default_max_replicas
  default_instance_type = var.instance_type
  default_min_replicas  = 3 # Minimum for HA (multi-AZ: 1 per subnet)
  default_max_replicas  = 6 # Double min replicas
  # machine_pools = [] # Leave empty to use module defaults and let ROSA create pools automatically

  # Optional: Allow API endpoint access from additional IPv4 CIDR blocks
  # By default, the VPC endpoint security group only allows access from within the VPC
  # Uncomment and configure to allow access from VPN ranges, bastion hosts, or other VPCs
  # For egress-zero clusters, this is useful for allowing access from VPN or Transit Gateway connected networks
  # api_endpoint_allowed_cidrs = [
  #   "10.0.0.0/32",      # Example: Specific IP (e.g., bastion host via SSM Session Manager)
  #   "192.168.1.0/24"   # Example: VPN range or Transit Gateway connected VPC CIDR
  # ]

  tags = var.tags
  # tags = merge(var.tags, {
  #   Environment = "production"
  #   Security    = "high"
  #   Compliance  = var.fips ? "fips-140-2" : "standard"
  # })

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
# NOTE: For egress-zero clusters, bastion_public_ip should always be false
# The bastion module creates SSM VPC endpoints required for Session Manager access
module "bastion" {
  count  = var.enable_bastion ? 1 : 0
  source = "../../../modules/infrastructure/bastion"

  name_prefix            = var.cluster_name
  vpc_id                 = module.network.vpc_id
  subnet_id              = length(module.network.private_subnet_ids) > 0 ? module.network.private_subnet_ids[0] : null # Use first private subnet
  private_subnet_ids     = module.network.private_subnet_ids    # All private subnets for VPC endpoints
  region                 = var.region
  vpc_cidr               = var.vpc_cidr
  bastion_public_ip      = var.bastion_public_ip # Should be false for egress-zero
  bastion_public_ssh_key = var.bastion_public_ssh_key
  enable_destroy         = var.enable_destroy

  tags = var.tags

  depends_on = [module.network]
}
