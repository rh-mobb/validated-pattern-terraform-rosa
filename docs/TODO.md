# TODO

This file tracks work items and improvements for the ROSA HCP Terraform infrastructure repository.

## How to Use This File

- Add new items to the appropriate section
- Mark items as `[DONE]` when completed
- Move completed items to the "Completed" section at the bottom
- Use `[IN PROGRESS]` for items currently being worked on
- Add your name/initials when starting work on an item

## Priority Legend

- 🔴 **High Priority**: Critical bugs, security issues, blocking issues
- 🟡 **Medium Priority**: Important features, significant improvements
- 🟢 **Low Priority**: Nice-to-have features, minor improvements

---

## Critical Issues

### Egress-Zero Cluster

- [ ] 🔴 **Fix egress-zero cluster worker node startup**
  - Worker nodes are not starting successfully (0/1 replicas)
  - Investigation needed: console logs, security groups, VPC endpoints, IAM permissions
  - See [CHANGELOG.md](../CHANGELOG.md) for current status
  - **Status**: Work in Progress - Non-functional

---

## Network Modules

- [ ] 🟡 **Add support for custom VPC endpoint policies**
  - Allow users to specify custom policies for VPC endpoints
  - Useful for compliance and security requirements

- [ ] 🟢 **Add VPC Flow Logs to network-public and network-private modules**
  - Currently only network-egress-zero has Flow Logs support
  - Add optional Flow Logs to other network modules

- [ ] 🟢 **Add support for additional VPC endpoints**
  - CloudWatch Metrics endpoint
  - SNS endpoint
  - SQS endpoint
  - Others as needed

- [ ] 🟡 **Document VPC endpoint costs and optimization strategies**
  - Add cost considerations to module READMEs
  - Document when to use Gateway vs Interface endpoints

---

## IAM Module

- [ ] 🟡 **Add support for custom IAM role policies**
  - Allow attaching additional policies to account roles
  - Useful for compliance requirements

- [ ] 🟢 **Add validation for role name length**
  - AWS IAM role names have a 64-character limit
  - Add validation to prevent errors

- [ ] 🟢 **Document IAM role naming conventions**
  - Clarify how prefixes are used
  - Document role name format

---

## Cluster Module

- [ ] 🟡 **Add support for additional cluster properties**
  - Document all available properties
  - Add examples for common configurations

- [ ] 🟢 **Add support for custom machine pool configurations**
  - Taints and labels
  - Additional autoscaling options

- [ ] 🟡 **Improve error messages for validation failures**
  - Machine type validation
  - Replica count validation
  - More helpful error messages

- [ ] 🟢 **Add support for cluster upgrades**
  - Document upgrade process
  - Add examples for version upgrades

---

## Bastion Module

- [ ] 🟡 **Add support for multiple bastion instances**
  - High availability bastion setup
  - Load balancer for bastion access

- [ ] 🟢 **Add pre-installation of additional tools**
  - `rosa` CLI
  - `aws` CLI updates
  - Other utilities

- [ ] 🟢 **Add bastion monitoring and alerting**
  - CloudWatch metrics
  - SNS notifications for bastion health

- [ ] 🟡 **Document bastion security hardening**
  - SSH key rotation
  - Security group best practices
  - SSM Session Manager best practices

---

## Documentation

- [ ] 🔴 **Document firewall and permission requirements for Terraform deployment**
  - **Network/Firewall Requirements**:
    - Outbound HTTPS (443) to ROSA API endpoints (api.openshift.com, console.redhat.com)
    - Outbound HTTPS (443) to AWS APIs (EC2, IAM, STS, S3, ECR, CloudWatch, etc.)
    - Outbound HTTPS (443) to Terraform Registry (registry.terraform.io)
    - DNS resolution (UDP 53) for all above domains
    - If using S3 backend: Outbound HTTPS (443) to S3 endpoints
    - If using DynamoDB backend: Outbound HTTPS (443) to DynamoDB endpoints
  - **IAM Permissions Required**:
    - Full IAM permissions (for creating roles, policies, OIDC provider)
    - EC2 permissions (VPC, subnets, security groups, instances, NAT gateways, VPC endpoints)
    - S3 permissions (if using S3 backend or VPC Flow Logs)
    - DynamoDB permissions (if using DynamoDB for state locking)
    - CloudWatch Logs permissions (if using VPC Flow Logs)
    - KMS permissions (if using customer-managed KMS keys)
    - Route53 permissions (if managing DNS)
  - **RHCS API Access**:
    - ROSA API token with appropriate permissions
    - Access to create/manage clusters, machine pools, identity providers
  - **Bastion/Managed Server Considerations**:
    - Document running Terraform from bastion hosts
    - Document running Terraform from CI/CD systems (GitHub Actions, GitLab CI, Jenkins)
    - Document running Terraform from managed servers with egress proxies
    - Network egress requirements from bastion/managed server
    - IAM role assumption requirements (if using cross-account or role assumption)
  - **Multi-Account Scenarios**:
    - Cross-account IAM role assumptions
    - Network connectivity between accounts (VPC peering, Transit Gateway)
    - State sharing across accounts
  - Create comprehensive guide: `docs/DEPLOYMENT_REQUIREMENTS.md`

- [ ] 🟡 **Add architecture diagrams**
  - Network topology diagrams for each module
  - Cluster architecture diagrams
  - Multi-team workflow diagrams

- [ ] 🟢 **Add troubleshooting guide**
  - Common issues and solutions
  - Debugging steps
  - ROSA CLI troubleshooting commands

- [ ] 🟢 **Add migration guide**
  - Migrating from manual ROSA deployments
  - Migrating between network types
  - Version upgrade guides

- [ ] 🟡 **Add examples for common use cases**
  - Multi-region deployments
  - Disaster recovery setup
  - Development/staging/production patterns

- [ ] 🟢 **Add video tutorials or walkthroughs**
  - Quick start video
  - Module composition tutorial
  - Troubleshooting walkthrough

---

## Testing & Quality

- [ ] 🟡 **Add Terraform tests**
  - Unit tests for modules
  - Integration tests for example clusters
  - Use `terratest` or similar framework

- [ ] 🟡 **Add pre-commit hooks**
  - `terraform fmt`
  - `terraform validate`
  - `checkov` security scanning
  - Documentation checks

- [ ] 🟢 **Add CI/CD pipeline**
  - GitHub Actions or GitLab CI
  - Automated testing
  - Automated security scanning
  - Automated documentation generation

- [ ] 🟡 **Add example cluster tests**
  - Validate example clusters can be deployed
  - Smoke tests for cluster functionality

---

## Security

- [ ] 🟡 **Add security scanning automation**
  - Integrate `checkov` into CI/CD
  - Add security policy documentation
  - Regular security audits

- [ ] 🟢 **Add secrets management examples**
  - AWS Secrets Manager integration
  - HashiCorp Vault integration
  - Environment variable best practices

- [ ] 🟡 **Add security hardening guide**
  - Network security best practices
  - IAM best practices
  - Cluster security configurations

---

## Performance & Optimization

- [ ] 🟢 **Add cost optimization guide**
  - Right-sizing recommendations
  - Cost comparison between network types
  - Reserved instance recommendations

- [ ] 🟢 **Add performance tuning guide**
  - Cluster sizing recommendations
  - Network performance optimization
  - VPC endpoint optimization

---

## Features

- [ ] 🟡 **Add support for ROSA Classic (non-HCP) clusters**
  - Classic cluster module
  - Migration guide from Classic to HCP

- [ ] 🟢 **Add support for additional cloud providers**
  - Multi-cloud support (if applicable)
  - Provider-specific optimizations

- [ ] 🟢 **Add Terraform Cloud/Enterprise integration examples**
  - Remote state configuration
  - Workspace setup
  - Team collaboration patterns

- [ ] 🟡 **Add support for GitOps workflows**
  - ArgoCD integration examples
  - Flux integration examples
  - Cluster configuration management

---

## Infrastructure as Code Improvements

- [ ] 🟡 **Add Terraform workspaces support**
  - Environment-specific configurations
  - Workspace examples

- [ ] 🟢 **Add support for Terraform Cloud/Enterprise**
  - Remote state backends
  - Team collaboration features

- [ ] 🟢 **Add module versioning strategy**
  - Semantic versioning for modules
  - Module registry setup
  - Version pinning examples

---

## Developer Experience

- [ ] 🟡 **Add development environment setup guide**
  - Required tools and versions
  - Local development setup
  - Testing environment setup

- [ ] 🟢 **Add Makefile improvements**
  - Add more utility targets
  - Add validation targets
  - Add cleanup targets

- [ ] 🟢 **Add VS Code/Cursor configuration**
  - Terraform extension settings
  - Recommended extensions
  - Workspace settings

---

## Completed

_Items will be moved here as they are completed_

---

## Notes

- This TODO list is maintained by the team
- Feel free to add items or update priorities
- Link to related issues or PRs when available
- Update status as work progresses

