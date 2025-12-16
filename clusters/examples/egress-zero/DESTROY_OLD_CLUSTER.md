# Destroying Old Egress-Zero Cluster

This guide helps you destroy a cluster that was deployed with the old structure (before infrastructure/configuration separation).

## Option 1: Use Terraform Destroy with Old State (Recommended)

The old state file is still present. You can destroy using it directly:

```bash
cd clusters/examples/egress-zero

# Initialize terraform with the old state file
terraform init -reconfigure

# Review what will be destroyed
terraform plan -destroy -state=terraform.tfstate

# Destroy the cluster
terraform destroy -state=terraform.tfstate -auto-approve
```

**Note**: This requires the old module paths. If this doesn't work, use Option 2.

## Option 2: Temporarily Restore Old Structure

If Option 1 fails due to module path changes, temporarily restore the old structure:

1. **Create temporary old-style configuration** (see script below)
2. **Run destroy**
3. **Clean up temporary files**

### Quick Script

```bash
cd clusters/examples/egress-zero

# Backup current structure
mv infrastructure infrastructure.new
mv configuration configuration.new

# Create temporary old-style main.tf that matches old state
cat > 10-main.tf << 'EOF'
module "network" {
  source = "../../../modules/infrastructure/network-egress-zero"
  # ... (copy from infrastructure/10-main.tf)
}

module "iam" {
  source = "../../../modules/infrastructure/iam"
  # ... (copy from infrastructure/10-main.tf)
}

module "cluster" {
  source = "../../../modules/infrastructure/cluster"
  # ... (copy from infrastructure/10-main.tf)
}

module "identity_admin" {
  count  = var.admin_password != null ? 1 : 0
  source = "../../../modules/configuration/identity-admin"
  cluster_id     = module.cluster.cluster_id
  admin_password = var.admin_password
}

module "bastion" {
  count  = var.enable_bastion ? 1 : 0
  source = "../../../modules/infrastructure/bastion"
  # ... (copy from infrastructure/10-main.tf)
}
EOF

# Copy other necessary files temporarily
cp infrastructure/00-providers.tf 00-providers.tf
cp infrastructure/01-variables.tf 01-variables.tf
cp infrastructure/90-outputs.tf 90-outputs.tf
cp infrastructure/terraform.tfvars terraform.tfvars

# Initialize and destroy
terraform init -reconfigure
terraform destroy -state=terraform.tfstate -auto-approve

# Clean up temporary files
rm -f 00-providers.tf 01-variables.tf 10-main.tf 90-outputs.tf terraform.tfvars
mv infrastructure.new infrastructure
mv configuration.new configuration
```

## Option 3: Use AWS Console/CLI (Last Resort)

If Terraform destroy fails, you can manually delete resources via AWS Console or CLI:

1. Delete the ROSA cluster via OCM/Console
2. Delete VPC and networking resources
3. Delete IAM roles
4. Delete bastion host (if exists)

**Warning**: This approach may leave orphaned resources and is not recommended.
