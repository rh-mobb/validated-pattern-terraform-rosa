# Storage Module

This module creates KMS keys for EBS and EFS encryption, EFS file system, and required IAM policies for ROSA HCP clusters.

## Features

- **EBS KMS Key**: Customer-managed KMS key for EBS volume encryption
- **EFS KMS Key**: Customer-managed KMS key for EFS encryption
- **EFS File System**: Encrypted EFS file system with mount targets in all private subnets
- **IAM Policies**: Policies for KMS and EFS access by CSI drivers
- **IAM Roles**: Role for EFS CSI driver with proper OIDC trust policy
- **Security Groups**: Automatic security group rules for EFS access

## Usage

```hcl
module "storage" {
  source = "../../modules/infrastructure/storage"

  cluster_name         = "my-rosa-cluster"
  cluster_id          = module.cluster.cluster_id
  oidc_endpoint_url   = module.iam.oidc_endpoint_url
  private_subnet_ids  = module.network.private_subnet_ids
  private_subnet_cidrs = module.network.private_subnet_cidrs

  enable_efs = true

  tags = {
    Environment = "production"
  }
}

# Use EBS KMS key in cluster module
module "cluster" {
  source = "../../modules/infrastructure/cluster"

  # ... other configuration ...
  kms_key_arn = module.storage.ebs_kms_key_arn
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 6.0 |

## Inputs

### Required

| Name | Description | Type |
|------|-------------|------|
| cluster_name | Name of the ROSA HCP cluster | `string` |
| cluster_id | ID of the ROSA HCP cluster (used for security group lookup) | `string` |
| oidc_endpoint_url | OIDC endpoint URL (used for IAM role trust policies) | `string` |
| private_subnet_ids | List of private subnet IDs for EFS mount targets | `list(string)` |
| private_subnet_cidrs | List of private subnet CIDR blocks for EFS security group rules | `list(string)` |

### Optional

| Name | Description | Type | Default |
|------|-------------|------|---------|
| enable_efs | Enable EFS file system creation | `bool` | `true` |
| enable_efs_backup | Enable EFS backup (not yet implemented) | `bool` | `false` |
| kms_key_deletion_window | Deletion window in days for KMS keys | `number` | `10` |
| tags | Tags to apply to all resources | `map(string)` | `{}` |
| persists_through_sleep | Set to false to put cluster in sleep mode (destroys resources). Default true keeps cluster active | `bool` | `true` |

## Outputs

| Name | Description |
|------|-------------|
| ebs_kms_key_id | ID of the KMS key for EBS encryption |
| ebs_kms_key_arn | ARN of the KMS key for EBS encryption |
| efs_kms_key_id | ID of the KMS key for EFS encryption |
| efs_kms_key_arn | ARN of the KMS key for EFS encryption |
| efs_file_system_id | ID of the EFS file system |
| efs_file_system_arn | ARN of the EFS file system |
| efs_csi_role_arn | ARN of the IAM role for EFS CSI driver |
| kms_csi_policy_arn | ARN of the IAM policy for KMS CSI access |

## Integration with Cluster Module

The EBS KMS key should be passed to the cluster module:

```hcl
module "cluster" {
  source = "../../modules/infrastructure/cluster"

  # ... other configuration ...
  kms_key_arn = module.storage.ebs_kms_key_arn
}
```

## Integration with Bootstrap

The storage resources are automatically used by the GitOps bootstrap script when provided:

```hcl
module "cluster" {
  source = "../../modules/infrastructure/cluster"

  # ... other configuration ...
  enable_gitops_bootstrap = true
  ebs_kms_key_arn        = module.storage.ebs_kms_key_arn
  efs_file_system_id     = module.storage.efs_file_system_id
}
```

## References

- Reference Implementation: `./reference/pfoster/rosa-hcp-dedicated-vpc/terraform/7.storage.tf`
- ROSA Storage Documentation: https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/storage/configuring-persistent-storage
- AWS EFS CSI Driver: https://cloud.redhat.com/experts/rosa/aws-efs/
