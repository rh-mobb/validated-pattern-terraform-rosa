# GitOps Operator
# Note: Admin user and bastion are created in infrastructure, not configuration
# Configuration reads admin credentials from infrastructure state
module "gitops" {
  count  = var.deploy_gitops ? 1 : 0
  source = "../../../../modules/configuration/gitops"

  cluster_id   = data.terraform_remote_state.infrastructure.outputs.cluster_id
  cluster_name  = data.terraform_remote_state.infrastructure.outputs.cluster_name
  api_url       = data.terraform_remote_state.infrastructure.outputs.api_url

  admin_username = var.admin_username
  admin_password = var.admin_password

  tags = var.tags
}
