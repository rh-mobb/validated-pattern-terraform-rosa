# Get AWS account ID (needed for cluster properties and other resources)
data "aws_caller_identity" "current" {}

locals {
  # Determine if destroy is enabled (use override if provided, else global)
  destroy_enabled = var.enable_destroy_cluster != null ? var.enable_destroy_cluster : var.enable_destroy

  # Determine OpenShift version to use
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
  # If openshift_version is provided, use it; otherwise use the latest installable version
  openshift_version_to_use = var.openshift_version != null ? var.openshift_version : (
    # Get the latest version from the data source (last item after ordering by id)
    length(data.rhcs_versions.available.items) > 0 ? element(data.rhcs_versions.available.items, length(data.rhcs_versions.available.items) - 1).name : null
  )

  # Determine replicas and autoscaling settings
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
  # HCP: if unspecified and multi-az, use 1 per subnet (total = 1 * number of subnets); if unspecified and single-az, use 2
  # NOTE: hcp_replicas is the TOTAL number of replicas across all subnets, not per subnet
  autoscaling_enabled = length(var.machine_pools) > 0 ? var.machine_pools[0].autoscaling_enabled : true
  hcp_replicas = length(var.machine_pools) > 0 ? var.machine_pools[0].min_replicas : (
    var.multi_az ? (1 * length(var.subnet_ids)) : 2
  )

  # Determine machine pool names - HCP creates one pool per subnet if multi-AZ
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
  # NOTE: ROSA creates "workers" (plural) for single-AZ
  # For multi-AZ, ROSA creates "workers-0", "workers-1", "workers-2" (one per subnet)
  # Use a list (not set) to match reference implementation for count-based iteration
  # Conditionally set machine pools based on destroy flag
  machine_pools_to_create = local.destroy_enabled == false ? var.machine_pools : []
  hcp_machine_pools = local.destroy_enabled == false ? (
    length(var.machine_pools) > 0 ? [for pool in var.machine_pools : pool.name] : (
      var.multi_az ? [for idx in range(length(var.subnet_ids)) : "workers-${idx}"] : ["workers"]
    )
  ) : []

  # Common tags
  common_tags = merge(var.tags, {
    ManagedBy   = "Terraform"
    ClusterName = var.cluster_name
  })

  # Cluster properties
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
  # zero_egress property is set when zero_egress variable is true
  cluster_properties = merge(
    {
      rosa_creator_arn = data.aws_caller_identity.current.arn
    },
    var.zero_egress ? { "zero_egress" = "true" } : {}
  )
}

# Query available OpenShift versions
# Reference: https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/data-sources/versions
# Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
data "rhcs_versions" "available" {
  search = "enabled='t' and rosa_enabled='t' and hosted_control_plane_enabled = 't' and channel_group='${var.channel_group}'"
  order  = "id"
}

# Query available machine types for ROSA
# Reference: https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/data-sources/machine_types
# Note: This data source returns machine types for the current region context
data "rhcs_machine_types" "available" {}

# ROSA HCP Cluster
# Reference: https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/resources/cluster_rosa_hcp
# Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
resource "rhcs_cluster_rosa_hcp" "main" {
  count = local.destroy_enabled == false ? 1 : 0
  name           = var.cluster_name
  cloud_region   = var.region
  aws_account_id = data.aws_caller_identity.current.account_id

  # AWS billing account ID (optional, defaults to current account)
  aws_billing_account_id = var.aws_billing_account_id != null ? var.aws_billing_account_id : data.aws_caller_identity.current.account_id

  # Network configuration
  aws_subnet_ids     = var.subnet_ids
  availability_zones = var.availability_zones
  machine_cidr       = var.vpc_cidr # Required: VPC CIDR block

  # STS configuration - required attribute (not block)
  # Reference: https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/resources/cluster_rosa_hcp#sts
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/03-roles.tf
  sts = {
    role_arn             = var.installer_role_arn # role_arn is the installer role ARN (not operator role)
    support_role_arn     = var.support_role_arn
    operator_role_prefix = var.cluster_name
    oidc_config_id       = var.oidc_config_id
    oidc_endpoint_url    = var.oidc_endpoint_url
    instance_iam_roles = {
      worker_role_arn = var.worker_role_arn
    }
  }

  # Security and encryption settings
  private         = var.private
  etcd_encryption = var.etcd_encryption

  # Optional encryption
  kms_key_arn = var.kms_key_arn

  # Network CIDR configuration
  service_cidr = var.service_cidr
  pod_cidr     = var.pod_cidr
  host_prefix  = var.host_prefix

  # Version configuration
  # Use determined version (provided or latest installable)
  version       = local.openshift_version_to_use
  channel_group = var.channel_group

  # Compute machine type (used for default machine pool)
  compute_machine_type = length(var.machine_pools) > 0 ? var.machine_pools[0].instance_type : var.default_instance_type

  # Replicas for default machine pool
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
  # NOTE: we are only deriving this because we use the rhcs_hcp_machine_pool.default resource to manage our
  #       machine pools and we require this input for the cluster.
  # HCP: if unspecified and multi-az, use 1 per subnet; if unspecified and single-az, use 2
  # For multi-AZ: hcp_replicas should be the total number (e.g., 3 for 3 subnets with 1 per subnet)
  # For single-AZ: hcp_replicas should be 2 (minimum for HA)
  # NOTE: Cluster-level replicas must always be set (even with autoscaling) for validation
  #       Autoscaling is handled at the machine pool level, not cluster level
  replicas = local.hcp_replicas

  # EC2 metadata HTTP tokens (required for security)
  ec2_metadata_http_tokens = "required"

  # Properties
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
  # Properties are constructed in locals.cluster_properties for better readability and maintainability
  properties = local.cluster_properties

  # Lifecycle settings
  disable_waiting_in_destroy          = false
  wait_for_create_complete            = true
  wait_for_std_compute_nodes_complete = var.wait_for_std_compute_nodes_complete

  tags = local.common_tags

  lifecycle {
    # CRITICAL: Destroy order is handled by Terraform's implicit dependency graph:
    # - This cluster resource depends on IAM module outputs (installer_role_arn, support_role_arn, etc.)
    # - During destroy, Terraform destroys resources in REVERSE dependency order
    # - Therefore, cluster (which depends on IAM outputs) will be destroyed BEFORE IAM resources
    # - This ensures Terraform maintains permissions to destroy the cluster
    # - No explicit depends_on needed - the dependency on IAM outputs is sufficient

    # Validate instance type is available for ROSA in the specified region
    precondition {
      condition = contains(
        [for mt in data.rhcs_machine_types.available.items : mt.id],
        length(var.machine_pools) > 0 ? var.machine_pools[0].instance_type : var.default_instance_type
      )
      error_message = "Instance type '${length(var.machine_pools) > 0 ? var.machine_pools[0].instance_type : var.default_instance_type}' is not available for ROSA in region '${var.region}'. Use 'terraform console' and run 'data.rhcs_machine_types.available.items' to see available machine types."
    }

    # Validate replicas is a multiple of number of subnets for multi-AZ clusters
    precondition {
      condition = var.multi_az ? (local.hcp_replicas % length(var.subnet_ids) == 0) : true
      error_message = "For multi-AZ clusters, replicas (${local.hcp_replicas}) must be a multiple of the number of subnets (${length(var.subnet_ids)}). For ${length(var.subnet_ids)} subnets, use replicas like ${length(var.subnet_ids)}, ${length(var.subnet_ids) * 2}, ${length(var.subnet_ids) * 3}, etc."
    }
  }

  # Explicit dependency on IAM outputs ensures cluster is destroyed BEFORE IAM during destroy
  # During destroy, Terraform destroys resources in reverse dependency order
  # Since cluster depends on IAM outputs, cluster will be destroyed first
  depends_on = [
    var.installer_role_arn,
    var.support_role_arn,
    var.worker_role_arn,
    var.oidc_config_id,
    var.oidc_endpoint_url
  ]
}

# Machine Pools
# Reference: https://registry.terraform.io/providers/terraform-redhat/rhcs/latest/docs/resources/hcp_machine_pool
# Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
# For HCP, we read the default machine pools created by the cluster, then manage them
# Using count (not for_each) to match reference implementation for magic import pattern
data "rhcs_hcp_machine_pool" "default" {
  count = local.destroy_enabled == false ? length(local.hcp_machine_pools) : 0

  cluster = one(rhcs_cluster_rosa_hcp.main[*].id)
  name    = local.hcp_machine_pools[count.index]
}

resource "rhcs_hcp_machine_pool" "default" {
  # Only create resources for pools that exist (magic import pattern)
  # The data source count matches local.hcp_machine_pools, so use that for resource count
  # This ensures we create resources for all expected pools, and the data source will populate values if pools exist
  # Gate with destroy_enabled flag
  count = local.destroy_enabled == false ? length(local.hcp_machine_pools) : 0

  # Use expected pool name from local.hcp_machine_pools (not from data source, which may be null)
  # For multi-AZ: "workers-0", "workers-1", "workers-2"
  # For single-AZ: "workers"
  name    = local.hcp_machine_pools[count.index]
  cluster = one(rhcs_cluster_rosa_hcp.main[*].id)

  # Handle null subnet_id - derive from count.index if data source returns null
  # Since hcp_machine_pools list matches subnet order, use count.index to map to subnet_ids
  # For multi-AZ: count.index 0 -> subnet_ids[0], count.index 1 -> subnet_ids[1], etc.
  # For single-AZ: count.index 0 -> subnet_ids[0]
  subnet_id = try(data.rhcs_hcp_machine_pool.default[count.index].subnet_id, null) != null ? (
    data.rhcs_hcp_machine_pool.default[count.index].subnet_id
  ) : var.subnet_ids[count.index % length(var.subnet_ids)]

  # Handle null auto_repair - default to true (standard ROSA default)
  auto_repair = try(data.rhcs_hcp_machine_pool.default[count.index].auto_repair, null) != null ? (
    data.rhcs_hcp_machine_pool.default[count.index].auto_repair
  ) : true

  # NOTE: if autoscaling is specified, replicas must be null
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
  # Handle null replicas - use calculated value if data source returns null
  replicas = local.autoscaling_enabled ? null : (
    try(data.rhcs_hcp_machine_pool.default[count.index].replicas, null) != null ?
    data.rhcs_hcp_machine_pool.default[count.index].replicas :
    local.hcp_replicas
  )

  # Autoscaling configuration - required attribute (not block)
  autoscaling = {
    enabled      = local.autoscaling_enabled
    min_replicas = local.autoscaling_enabled ? local.hcp_replicas : null
    max_replicas = local.autoscaling_enabled ? (
      length(var.machine_pools) > 0 ? var.machine_pools[0].max_replicas : var.default_max_replicas
    ) : null
  }

  # AWS node pool configuration - required attribute (not block)
  # Reference: https://github.com/rh-mobb/terraform-rosa/blob/main/04-cluster.tf
  # Preserve instance type from data source, but allow override via machine_pools variable
  # Handle null aws_node_pool gracefully (may be null on initial creation or subsequent applies)
  aws_node_pool = {
    instance_type = length(var.machine_pools) > 0 ? var.machine_pools[0].instance_type : (
      try(data.rhcs_hcp_machine_pool.default[count.index].aws_node_pool.instance_type, null) != null ?
      data.rhcs_hcp_machine_pool.default[count.index].aws_node_pool.instance_type :
      var.default_instance_type
    )
    ec2_metadata_http_tokens = try(data.rhcs_hcp_machine_pool.default[count.index].aws_node_pool.ec2_metadata_http_tokens, null) != null ? (
      data.rhcs_hcp_machine_pool.default[count.index].aws_node_pool.ec2_metadata_http_tokens
    ) : "required" # Default to "required" to match cluster-level setting
    tags = local.common_tags
  }

  lifecycle {
    # Magic import: When using data.rhcs_hcp_machine_pool, Terraform should automatically import
    # the existing machine pool if it exists. However, if the pool was deleted and recreated,
    # we may need to manually import it first using: terraform import <resource_address> <cluster_id>,<machine_pool_id>
    # The machine_pool_id can be found in the data source's id attribute after refresh.

    precondition {
      condition     = var.multi_az ? true : (local.hcp_replicas >= 2)
      error_message = "must have a minimum of 2 'replicas' for single az use cases."
    }

    precondition {
      condition     = local.autoscaling_enabled ? (
        (length(var.machine_pools) > 0 ? var.machine_pools[0].max_replicas : var.default_max_replicas) >= local.hcp_replicas
      ) : true
      error_message = "'max_replicas' must be greater than or equal to 'min_replicas'."
    }

    # Validate instance type is available for ROSA in the specified region
    # Handle null aws_node_pool gracefully
    precondition {
      condition = contains(
        [for mt in data.rhcs_machine_types.available.items : mt.id],
        length(var.machine_pools) > 0 ? var.machine_pools[0].instance_type : (
          try(data.rhcs_hcp_machine_pool.default[count.index].aws_node_pool.instance_type, null) != null ?
          data.rhcs_hcp_machine_pool.default[count.index].aws_node_pool.instance_type :
          var.default_instance_type
        )
      )
      error_message = "Instance type '${length(var.machine_pools) > 0 ? var.machine_pools[0].instance_type : (try(data.rhcs_hcp_machine_pool.default[count.index].aws_node_pool.instance_type, null) != null ? data.rhcs_hcp_machine_pool.default[count.index].aws_node_pool.instance_type : var.default_instance_type)}' is not available for ROSA in region '${var.region}'. Use 'terraform console' and run 'data.rhcs_machine_types.available.items' to see available machine types."
    }
  }
}

# Note: Admin user creation has been moved to a separate identity-admin module
# This allows for independent lifecycle management (create initially, remove when external IDP is configured)
# See modules/identity-admin/ for the admin user creation module
