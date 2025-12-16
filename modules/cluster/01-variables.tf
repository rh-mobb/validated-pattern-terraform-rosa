# Required Variables
variable "cluster_name" {
  description = "Name of the ROSA HCP cluster"
  type        = string
  nullable    = false
}

variable "region" {
  description = "AWS region for the cluster"
  type        = string
  nullable    = false
}

variable "vpc_id" {
  description = "VPC ID from network module"
  type        = string
  nullable    = false
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC (required for machine_cidr)"
  type        = string
  nullable    = false
}

variable "subnet_ids" {
  description = "List of private subnet IDs from network module (aws_subnet_ids)"
  type        = list(string)
  nullable    = false
}

variable "installer_role_arn" {
  description = "ARN of the Installer role from IAM module"
  type        = string
  nullable    = false
}

variable "support_role_arn" {
  description = "ARN of the Support role from IAM module"
  type        = string
  nullable    = false
}

variable "worker_role_arn" {
  description = "ARN of the Worker role from IAM module"
  type        = string
  nullable    = false
}

variable "oidc_config_id" {
  description = "OIDC configuration ID from IAM module"
  type        = string
  nullable    = false
}

variable "oidc_endpoint_url" {
  description = "OIDC endpoint URL from IAM module"
  type        = string
  nullable    = false
}

# Cluster Configuration Variables (with organizational defaults)
# Note: availability_zones should come from network module output (private_subnet_azs)
variable "availability_zones" {
  description = "List of availability zones from network module. Automatically determined based on multi_az setting."
  type        = list(string)
  nullable    = false
}

variable "multi_az" {
  description = "Deploy across multiple availability zones"
  type        = bool
  default     = true
  nullable    = false
}

variable "aws_billing_account_id" {
  description = "The AWS billing account identifier where all resources are billed. If not provided, defaults to the current AWS account ID."
  type        = string
  default     = null
  nullable    = true
}

variable "private" {
  description = "Use PrivateLink API endpoint (organizational default: true)"
  type        = bool
  default     = true
  nullable    = false
}

variable "etcd_encryption" {
  description = "Enable etcd encryption (organizational default: false)"
  type        = bool
  default     = false
  nullable    = false
}

variable "fips" {
  description = "Enable FIPS 140-2 compliance"
  type        = bool
  default     = false
  nullable    = false
}

variable "zero_egress" {
  description = "Enable zero egress mode (egress-zero cluster). Sets zero_egress property to 'true' in cluster properties"
  type        = bool
  default     = false
  nullable    = false
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption (optional)"
  type        = string
  default     = null
  nullable    = true
}

variable "service_cidr" {
  description = "CIDR block for services"
  type        = string
  default     = "172.30.0.0/16"
  nullable    = false
}

variable "pod_cidr" {
  description = "CIDR block for pods"
  type        = string
  default     = "10.128.0.0/14"
  nullable    = false
}

variable "host_prefix" {
  description = "Host prefix for subnet allocation"
  type        = number
  default     = 23
  nullable    = false
}

variable "channel_group" {
  description = "Channel group for OpenShift version"
  type        = string
  default     = "stable"
  nullable    = false
}

variable "openshift_version" {
  description = "OpenShift version to pin (optional)"
  type        = string
  default     = null
  nullable    = true
}

variable "tags" {
  description = "Tags to apply to the cluster"
  type        = map(string)
  default     = {}
  nullable    = false
}

# Note: Admin user creation has been moved to a separate identity-admin module
# Use modules/identity-admin/ for admin user creation to enable independent lifecycle management

# Machine Pool Configuration
variable "machine_pools" {
  description = "List of machine pool configurations. If not provided, creates default pool"
  type = list(object({
    name                = string
    instance_type       = string
    min_replicas        = number
    max_replicas        = number
    multi_az            = bool
    autoscaling_enabled = bool
  }))
  default  = []
  nullable = false
}

# Default machine pool values (used if machine_pools is empty)
variable "default_instance_type" {
  description = "Default instance type for machine pool (if machine_pools not provided)"
  type        = string
  default     = "m5.xlarge"
  nullable    = false
}

variable "default_min_replicas" {
  description = "Default minimum replicas for machine pool (if machine_pools not provided)"
  type        = number
  default     = 3
  nullable    = false
}

variable "default_max_replicas" {
  description = "Default maximum replicas for machine pool (if machine_pools not provided)"
  type        = number
  default     = 6
  nullable    = false
}

variable "default_multi_az" {
  description = "Default multi-AZ setting for machine pool (if machine_pools not provided)"
  type        = bool
  default     = true
  nullable    = false
}

variable "wait_for_std_compute_nodes_complete" {
  description = <<EOF
  Wait for standard compute nodes to complete before considering cluster creation successful.

  Set to false if worker nodes may take longer to start (e.g., egress-zero clusters with network connectivity delays).
  When false, cluster creation will complete once the control plane is ready, and nodes will be created asynchronously.
  EOF
  type        = bool
  default     = true
  nullable    = false
}
