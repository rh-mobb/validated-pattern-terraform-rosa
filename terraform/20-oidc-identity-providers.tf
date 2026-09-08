# Purpose: create generic OpenID providers from variable-owned map keys,
# accepting the client secret either directly (env var / TF_VAR) or by
# resolving it from AWS Secrets Manager. Direct values take priority.
# What this is not: neither delivery path prevents the resolved secret from
# being stored in Terraform state.
# Prerequisites: external authentication disabled, state encrypted with
# restricted access, and (for Secrets Manager entries) one secret per entry.
# Authoritative references:
# - https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/secretsmanager_secret_version
# - https://registry.terraform.io/providers/terraform-redhat/rhcs/1.7.7/docs/resources/identity_provider
# Covers: for_each, secret_id, source, cluster_id, name, mapping_method, openid, ca, client_id, client_secret, issuer, extra_scopes, extra_authorize_parameters, claims
# Does: Resolves each secret and creates one module instance per configured map key.
# Why: Caller-owned keys keep instance identity known before cluster creation completes.
# Change: A changed key destroys one identity provider and creates a different instance.
# Trap: Secret lookup protects tfvars only; the resolved value remains in Terraform state.
# Evidence: https://developer.hashicorp.com/terraform/language/meta-arguments/for_each

locals {
  # The keys of oidc_client_secrets are provider identifiers (e.g. "entra"),
  # not secret material. Extract them as nonsensitive for use in for_each filters.
  oidc_direct_secret_keys = nonsensitive(keys(var.oidc_client_secrets))
}

data "aws_secretsmanager_secret_version" "oidc_identity_provider" {
  # Only look up secrets for entries not covered by oidc_client_secrets.
  for_each = var.persists_through_sleep ? {
    for k, v in var.oidc_identity_providers : k => v
    if !contains(local.oidc_direct_secret_keys, k)
  } : {}

  secret_id = each.value.client_secret_secret_id
}

module "oidc_identity_provider" {
  source   = "../modules/infrastructure/oidc-idp"
  for_each = var.persists_through_sleep ? var.oidc_identity_providers : {}

  # The cluster output is intentionally inside the module body. Terraform can
  # order creation even when this value is unknown during a greenfield plan.
  cluster_id     = module.cluster.cluster_id
  name           = each.value.name
  mapping_method = each.value.mapping_method
  openid = {
    ca                         = each.value.ca
    client_id                  = each.value.client_id
    client_secret              = contains(local.oidc_direct_secret_keys, each.key) ? var.oidc_client_secrets[each.key] : data.aws_secretsmanager_secret_version.oidc_identity_provider[each.key].secret_string
    issuer                     = each.value.issuer
    extra_scopes               = each.value.extra_scopes
    extra_authorize_parameters = each.value.extra_authorize_parameters
    claims                     = each.value.claims
  }
}
