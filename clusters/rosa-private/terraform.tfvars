# Infrastructure Configuration
# This file contains variables for the infrastructure layer (VPC, network, cluster creation)
# Based on egress-zero example - Private ROSA HCP cluster

#------------------------------------------------------------------------------
# BGP Configuration
# Enable BGP infrastructure for advertising pod/UDN networks via AWS VPC Route Server
#------------------------------------------------------------------------------
enable_bgp             = true
bgp_rosa_asn           = "65001"    # OCP AS number - used for FRR/MetalLB config
bgp_route_server_asn   = "65000"    # AS number of AWS Route Server
bgp_ext_vpc_cidr       = "192.168.0.0/16"
bgp_cudn_cidrs         = ["10.100.0.0/16", "10.200.0.0/16", "10.150.0.0/16"]  # CIDRs for Cluster User Defined Networks
bgp_router_instance_type = "c5.metal"
bgp_owner_tag          = "rosa-bgp"
bgp_project_tag        = "ROSA-Virt BGP"

#------------------------------------------------------------------------------

cluster_name = "rosa-private"
enable_client_vpn = true
# Sleep Mode - set to false to destroy/skip resources
# persists_through_sleep = true means resources WILL be created
persists_through_sleep = true  # Create all resources (network, IAM, cluster)
# Network Configuration
network_type = "public" # Private clusters use PrivateLink for API endpoint
zero_egress  = true    # Set to true if zero internet egress is required. Matches ROSA API property name.
private      = true      # Private API endpoint (PrivateLink)
region       = "ap-southeast-4"  # Melbourne
vpc_cidr     = "10.40.0.0/16"

# Bastion Host
enable_bastion    = true  # Required for private clusters (SSM Session Manager access)
bastion_public_ip = false # SSM-only access (more secure, no public IP)

# Cluster Topology
multi_az = true # Multi-AZ for production HA (availability zones automatically determined)
# Note: For multi-AZ clusters, default_min_replicas and default_max_replicas are per-AZ values
# Example: min_replicas=1 means 1 replica per pool (3 total for 3 pools: workers-0, workers-1, workers-2)

# Machine Pool Configuration
default_instance_type = "m5.xlarge" # EC2 instance type for default worker nodes
# default_min_replicas and default_max_replicas use module defaults:
# - Multi-AZ: min=1, max=2 per AZ (each pool gets these values, 3 total min, 6 total max)

# Version pinning for production
# openshift_version = "4.20.12"

# Network CIDRs
service_cidr = "172.30.0.0/16" # CIDR block for Kubernetes services
pod_cidr     = "10.128.0.0/14" # CIDR block for pods
host_prefix  = 23              # Host prefix for subnet allocation

# Compliance
fips = false # Set to true for FIPS 140-2 compliance (requires FIPS-compliant instance types)

# Audit logging
# flow_log_s3_bucket = "my-org-vpc-flow-logs"

# Additional Machine Pools
# Create custom machine pools beyond the default pool
# subnet_index: 0 = first AZ, 1 = second AZ, 2 = third AZ, etc.
# Note: Replica values are per-pool (not per-AZ like default pools)
#
# BGP Router Pools: 3 metal nodes (one per AZ) with bgp_router labels
# These nodes run FRR/MetalLB to advertise pod networks via BGP to AWS Route Server
additional_machine_pools = {
  "bm1" = {
    subnet_index        = 0
    instance_type       = "c5.metal"
    autoscaling_enabled = false
    min_replicas        = null
    max_replicas        = null
    replicas            = 1
    labels = {
      "bgp_router"        = "true"
      "bgp_router_subnet" = "1"
      "az"                = "1"
    }
    tags = {
      "bgp_router"        = "true"
      "bgp_router_subnet" = "1"
      "az"                = "1"
    }
  }
  "bm2" = {
    subnet_index        = 1
    instance_type       = "c5.metal"
    autoscaling_enabled = false
    min_replicas        = null
    max_replicas        = null
    replicas            = 1
    labels = {
      "bgp_router"        = "true"
      "bgp_router_subnet" = "2"
      "az"                = "2"
    }
    tags = {
      "bgp_router"        = "true"
      "bgp_router_subnet" = "2"
      "az"                = "2"
    }
  }
  "bm3" = {
    subnet_index        = 2
    instance_type       = "c5.metal"
    autoscaling_enabled = false
    min_replicas        = null
    max_replicas        = null
    replicas            = 1
    labels = {
      "bgp_router"        = "true"
      "bgp_router_subnet" = "3"
      "az"                = "3"
    }
    tags = {
      "bgp_router"        = "true"
      "bgp_router_subnet" = "3"
      "az"                = "3"
    }
  }
}

# Destroy protection - set to true to allow resource destruction
# enable_destroy = false

# tags = {
#   Environment = "production"
#   ManagedBy   = "terraform"
#   Project     = "rosa-hcp"
# }

# DNS Configuration
enable_persistent_dns_domain = true # Use persistent DNS domain that survives cluster recreation

# IAM Integration
enable_cert_manager_iam = true # Create IAM role for cert-manager to use AWS Private CA

# Cluster Protection
enable_termination_protection = false # Prevent accidental cluster deletion (requires OCM console to disable)

# Logging
enable_cloudwatch_logging = true # Enable CloudWatch logging for OpenShift Logging Operator

# Control Plane Log Forwarding (new ROSA managed log forwarder)
enable_control_plane_log_forwarding         = true                                                         # Enable control plane log forwarding
control_plane_log_groups                    = ["api", "authentication", "controller manager", "scheduler"] # Forward all supported log groups (case-insensitive, converted to lowercase)
control_plane_log_cloudwatch_enabled        = true                                                         # Enable CloudWatch destination
control_plane_log_cloudwatch_log_group_name = null                                                         # Uses default pattern: <cluster_name>-control-plane-logs
control_plane_log_s3_enabled                = true                                                         # Enable S3 destination
control_plane_log_s3_bucket_name            = null                                                         # Optional: If null, auto-generates unique name: <cluster_name>-control-plane-logs-<random_suffix>
control_plane_log_s3_bucket_prefix          = null                                                         # Optional prefix for organizing logs

# Legacy audit logging (deprecated - disable when control plane log forwarding is enabled)
enable_audit_logging = true  # Disable legacy audit logging in favor of new control plane log forwarding

# GitOps Bootstrap
enable_gitops_bootstrap = true # Enable GitOps operator installation after cluster creation
gitops_git_repo_url     = "https://github.com/rh-mobb/rosa-cluster-config.git"
gitops_git_path         = "dev/pczarkow" # Path to cluster configuration directory in Git repo

# Debug / Timing
enable_timing = true # Enable cluster creation timing capture

