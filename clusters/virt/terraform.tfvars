# OpenShift Virtualization test cluster
# ROSA HCP with metal workers, EFS RWX, VPC Route Server, and CUDN BGP
#
# Post-deploy (preferred, issue #51):
# 1. enable_efs + enable_secrets_manager_iam + enable_route_server
#    - EFS filesystem + EFS CSI IAM (efsCsiRoleArn / efsFileSystemId on platform metadata)
#    - {cluster}-bgp-config in Secrets Manager for the BGP operator
# 2. GitOps (dev/virt) installs ESO, cluster-efs, rosa-virtualization, cudn-bgp-routing-operator
# 3. Charts bind IRSA / fileSystemId from rosa-platform-metadata (no account ARNs in git)
# Manual SA annotate / hardcoded routeServerIDs / EFS roleArn are no longer required.

cluster_name = "virt"

# Version - OCP 4.21+ required for FRR-K8s, CUDN, RouteAdvertisements, and current CNV CSV
openshift_version = "4.22.2"
channel           = "fast-4.22"

# Network Configuration
network_type = "public"
zero_egress  = false
private      = false
region       = "ap-southeast-2"
vpc_cidr     = "10.0.0.0/16"

# Multi-AZ required for BGP (one router per AZ) and Virt live migration
multi_az = true

# Default worker pool — m7i.2xlarge (8 vCPU / 32 GiB) for GitOps/build headroom;
# m5.xlarge packed out during ESO + operator image builds (Pending pods).
# Note: these nodes do not advertise devices.kubevirt.io/kvm — schedule VMs on the
# bgp_router metal pools below (dual-purpose BGP router + Virt compute in this recipe).
# Until bgp-cloud-connector#121, CUDN VMs must stay on bgp_router nodes (operator sets
# SourceDestCheck=false only on BGP peers; preserved CUDN egress uses the scheduling ENI).
default_instance_type = "m7i.2xlarge"
default_min_replicas  = 1
default_max_replicas  = 2

# EFS (RWX) for OpenShift Virtualization live migration + shared VM disks
enable_efs = true

# BGP Route Server + ESO IAM (Secrets Manager secret {cluster}-bgp-config)
enable_route_server        = true
route_server_asn           = 64512
enable_secrets_manager_iam = true

# Virt / BGP router machine pools — one baremetal node per AZ
# Labels match the BGP operator's routerNodeSelector (bgp_router: "true")
# and per-AZ selectors (bgp_router_subnet, az).
# KVM (devices.kubevirt.io/kvm) is available on these metal nodes — use
# nodeSelector bgp_router=true for VM workloads (required until bgp-cloud-connector#121
# for VPC-routable CUDN egress; operator disables SourceDestCheck on speakers only).
additional_machine_pools = {
  "bgp-router-0" = {
    subnet_index        = 0
    instance_type       = "c5.metal"
    autoscaling_enabled = false
    replicas            = 1
    labels = {
      bgp_router        = "true"
      bgp_router_subnet = "1"
      az                = "1"
    }
    tags = {
      bgp_router        = "true"
      bgp_router_subnet = "1"
      az                = "1"
    }
    ec2_metadata_http_tokens = "required"
  }
  "bgp-router-1" = {
    subnet_index        = 1
    instance_type       = "c5.metal"
    autoscaling_enabled = false
    replicas            = 1
    labels = {
      bgp_router        = "true"
      bgp_router_subnet = "2"
      az                = "2"
    }
    tags = {
      bgp_router        = "true"
      bgp_router_subnet = "2"
      az                = "2"
    }
    ec2_metadata_http_tokens = "required"
  }
  "bgp-router-2" = {
    subnet_index        = 2
    instance_type       = "c5.metal"
    autoscaling_enabled = false
    replicas            = 1
    labels = {
      bgp_router        = "true"
      bgp_router_subnet = "3"
      az                = "3"
    }
    tags = {
      bgp_router        = "true"
      bgp_router_subnet = "3"
      az                = "3"
    }
    ec2_metadata_http_tokens = "required"
  }
}

# GitOps Bootstrap - Virt + EFS CSI + CUDN BGP via Argo CD
# Break-glass HTPasswd admin for make cluster.virt.login (module default is false)
enable_cluster_admin = true

enable_gitops_bootstrap    = true
gitops_git_repo_url        = "https://github.com/rh-mobb/rosa-cluster-config.git"
gitops_git_path            = "dev/virt"
gitops_git_target_revision = "HEAD"

# DNS
enable_persistent_dns_domain = true

# Disable features not needed for Virt / BGP testing
enable_bastion                      = false # Step 6b: targeted apply with bastion-e2e.tfvars for external VM test only
enable_cert_manager_iam             = false
enable_termination_protection       = false
enable_cloudwatch_logging           = false
enable_audit_logging                = false
enable_control_plane_log_forwarding = false

# Timing
enable_timing = true
