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

  # AWS Secrets Manager's console offers two ways to store a value: "Plaintext"
  # (secret_string IS the value) and "Key/value" (secret_string is a JSON
  # object, e.g. {"entra":"<value>"}). Both are common and the console does
  # not warn which one downstream code expects. Accept either shape here: try
  # decoding as JSON and pulling this entry's own key out of it; if the secret
  # isn't JSON, or doesn't contain that key, fall back to the raw string.
  oidc_secretsmanager_resolved = {
    for k, v in data.aws_secretsmanager_secret_version.oidc_identity_provider : k => try(
      jsondecode(v.secret_string)[k],
      v.secret_string,
    )
  }
}

data "aws_secretsmanager_secret_version" "oidc_identity_provider" {
  # Only look up secrets for entries not covered by oidc_client_secrets.
  for_each = var.persists_through_sleep ? {
    for k, v in var.oidc_identity_providers : k => v
    if !contains(local.oidc_direct_secret_keys, k)
  } : {}

  secret_id = each.value.client_secret_secret_id

  lifecycle {
    # Guard against the exact failure mode that caused this: a Key/Value
    # secret whose JSON key doesn't match this provider's map key (or a
    # deeply nested/multi-key secret) would otherwise silently fall through
    # to the raw JSON string. Catch that here instead of an opaque
    # post-deploy login failure. precondition/postcondition are only valid
    # on resource, data, and output blocks — not on module blocks.
    postcondition {
      condition     = !can(regex("^\\s*[{\\[]", nonsensitive(try(jsondecode(self.secret_string)[each.key], self.secret_string))))
      error_message = "Secret \"${each.value.client_secret_secret_id}\" still looks like a JSON object after resolution for oidc_identity_providers[\"${each.key}\"] — its Key/Value key name probably doesn't match \"${each.key}\". Store it as Plaintext, or as Key/Value with the key named exactly \"${each.key}\"."
    }
  }
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
    client_secret              = contains(local.oidc_direct_secret_keys, each.key) ? var.oidc_client_secrets[each.key] : local.oidc_secretsmanager_resolved[each.key]
    issuer                     = each.value.issuer
    extra_scopes               = each.value.extra_scopes
    extra_authorize_parameters = each.value.extra_authorize_parameters
    claims                     = each.value.claims
  }
}
