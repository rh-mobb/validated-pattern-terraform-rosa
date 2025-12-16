#!/bin/bash
# Script to destroy old egress-zero cluster deployed with pre-reorganization structure
# This temporarily recreates the old structure to match the old state file

set -e

CLUSTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$CLUSTER_DIR"

echo "=== Destroying Old Egress-Zero Cluster ==="
echo ""

# Check if old state file exists
if [ ! -f "terraform.tfstate" ]; then
    echo "Error: terraform.tfstate not found in current directory"
    exit 1
fi

# Check if infrastructure directory exists
if [ ! -d "infrastructure" ]; then
    echo "Error: infrastructure directory not found"
    exit 1
fi

# Backup current structure
echo "Backing up current structure..."
BACKUP_SUFFIX=$(date +%s)
if [ -d "infrastructure" ]; then
    cp -r infrastructure "infrastructure.backup.$BACKUP_SUFFIX"
fi
if [ -d "configuration" ]; then
    cp -r configuration "configuration.backup.$BACKUP_SUFFIX"
fi

# Create temporary old-style files in root
echo "Creating temporary old-style configuration..."

# Copy infrastructure files to root
cp infrastructure/00-providers.tf .
cp infrastructure/01-variables.tf .
cp infrastructure/terraform.tfvars .
cp infrastructure/90-outputs.tf .

# Copy and modify 10-main.tf - update module paths to old structure
# Old paths: ../../../modules/network-egress-zero
# New paths: ../../../../modules/infrastructure/network-egress-zero
sed 's|../../../../modules/infrastructure/|../../../modules/|g' infrastructure/10-main.tf > 10-main.tf
sed -i.bak 's|../../../../modules/configuration/|../../../modules/|g' 10-main.tf 2>/dev/null || \
sed -i '' 's|../../../../modules/configuration/|../../../modules/|g' 10-main.tf

# Initialize terraform
echo ""
echo "Initializing Terraform..."
terraform init -reconfigure

# Show what will be destroyed
echo ""
echo "=== Resources that will be destroyed ==="
terraform state list | head -30
TOTAL=$(terraform state list | wc -l | tr -d ' ')
echo "... ($TOTAL total resources)"

# Confirm
echo ""
read -p "Do you want to proceed with destroy? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Destroy cancelled. Cleaning up temporary files..."
    rm -f 00-providers.tf 01-variables.tf 10-main.tf 90-outputs.tf terraform.tfvars 10-main.tf.bak
    rm -rf "infrastructure.backup.$BACKUP_SUFFIX" "configuration.backup.$BACKUP_SUFFIX"
    exit 0
fi

# Destroy
echo ""
echo "Destroying cluster..."
terraform destroy -auto-approve

# Clean up temporary files
echo ""
echo "Cleaning up temporary files..."
rm -f 00-providers.tf 01-variables.tf 10-main.tf 90-outputs.tf terraform.tfvars 10-main.tf.bak
rm -rf .terraform .terraform.lock.hcl

# Restore backups (they're already there, just remove backups)
rm -rf "infrastructure.backup.$BACKUP_SUFFIX" "configuration.backup.$BACKUP_SUFFIX"

echo ""
echo "=== Destroy complete ==="
echo "Old state file (terraform.tfstate) has been updated."
echo "You may want to remove old state files:"
echo "  rm terraform.tfstate terraform.tfstate.backup terraform.tfstate.*.backup"
