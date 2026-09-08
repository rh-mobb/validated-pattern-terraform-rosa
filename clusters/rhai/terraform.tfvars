# Infrastructure Configuration for RHAI cluster
# Red Hat AI on OpenShift demo/lab cluster

cluster_name = "rhai"

# Version pinning
openshift_version = "4.22.8"

# Network Configuration
network_type = "public"
zero_egress  = false
private      = false
region       = "ap-southeast-2"
vpc_cidr     = "10.20.0.0/16"

# Cluster Topology
multi_az = false

# Machine Pool Configuration
default_instance_type = "m5.2xlarge"

# External authentication (create-time only; replaces HTPasswd IDP)
external_auth_providers_enabled = false

# Break-glass HTPasswd admin - disabled (incompatible with external auth)
enable_cluster_admin = true

# GitOps Bootstrap
enable_gitops_bootstrap = true
gitops_git_repo_url     = "https://github.com/rh-mobb/rosa-cluster-config.git"
gitops_git_path         = "dev/rhai"

# Additional Machine Pools
additional_machine_pools = {
  # "compute-0" = {
  #   subnet_index        = 0
  #   instance_type       = "m5.xlarge"
  #   autoscaling_enabled = true
  #   min_replicas        = 1
  #   max_replicas        = 2
  # }
  # "compute-1" = {
  #   subnet_index        = 0
  #   instance_type       = "m5.xlarge"
  #   autoscaling_enabled = false
  #   replicas            = 1
  # }
  # "infra" = {
  #   subnet_index          = 0
  #   instance_type         = "m5.xlarge"
  #   autoscaling_enabled   = false # Changed from True to False
  #   replicas              = 3
  #   # min_replicas        = 1   # Must be set to Null
  #   # max_replicas        = 3   # Must be set to Null
  #   version               = "4.22.4"
  # }
}

# Entra ID OIDC Identity Provider
# Client secret stored in AWS Secrets Manager (ap-southeast-2)
oidc_identity_providers = {
  entra = {
    name                    = "entra-id"
    client_id               = "d33dc511-47f9-495a-b846-f4b8a6c5a49f"
    client_secret_secret_id = "rhai/entra-id/client-secret"
    issuer                  = "https://login.microsoftonline.com/64dc69e4-d083-49fc-9569-ebece1dd1408/v2.0"
    extra_scopes            = ["email", "profile"]
    claims = {
      email              = ["email"]
      name               = ["name"]
      preferred_username = ["preferred_username", "upn"]
    }
  }
}

# Optional Features - minimal for lab/demo
persists_through_sleep               = true
enable_persistent_dns_domain         = true
enable_control_plane_log_forwarding  = true
control_plane_log_cloudwatch_enabled = true
enable_cert_manager_iam              = false
enable_termination_protection        = false

# Debug / Timing
enable_timing = true
