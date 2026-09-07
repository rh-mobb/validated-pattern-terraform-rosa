<!--
Purpose: Give a CI pipeline a directory-owned machine identity on an external-auth ROSA HCP cluster.
What this is not: This does not apply to a built-in-OAuth cluster, where no such identity exists.
Prerequisites: A cluster created with external_auth_providers_enabled = true and a dedicated confidential application.
Authoritative references:
- https://github.com/openshift/openshift-docs/blob/3fc89d132cac41b69f79d37fd8ee3f99d134700d/authentication/external-auth.adoc
- https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-client-creds-grant-flow
- https://kubernetes.io/docs/reference/access-authn-authz/rbac/
-->

# External-auth clusters

This page applies **only** to a cluster created with
`external_auth_providers_enabled = true`. Confirm that using
[the entry page](index.md#which-cluster-do-you-have); on a built-in-OAuth cluster
none of it works, and the token this page produces authenticates nothing.

Here the API server validates your identity provider's tokens directly, so a
confidential application can authenticate to the cluster with no human involved.
That is the one capability this architecture has and the default one does not.

**A [ServiceAccount](service-account-identity.md) also works here**, and is
simpler. Choose the directory identity when policy requires the identity to
originate in the directory; otherwise the ServiceAccount is the lighter option.

The repository's
[External Authentication with Entra ID](../external-auth-entra-id.md#cicd-pipeline-access)
guide already covers directory-user device code, ROPC, ServiceAccount and
break-glass choices for this architecture. This page covers what that one does
not: runnable least-privilege RBAC and a custody-safe application-token helper.
It does not restate the directory-user flow.

## Choose an identity

Start with the workload and audit requirements, not with a preferred grant:

| Deciding constraint | Route | Cost or boundary accepted |
|---|---|---|
| Machine-only workload; no directory-user identity is required | External machine JWT with a dedicated confidential application | Rotate a secret or certificate, accept its audience in the provider, and choose a username claim present in both human and application tokens. |
| Directory-user identity is required for audit; a human can seed once; tenant policy permits device code; cache survives between builds | [Device code](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code) from the existing guide | The runner holds a [refresh-token cache](https://learn.microsoft.com/en-us/entra/identity-platform/refresh-tokens) and becomes interactive again when cache, revocation, or Conditional Access prevents refresh. |
| Workload runs inside Kubernetes | [Projected ServiceAccount token](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#serviceaccount-token-volume-projection) | Kubernetes owns token delivery and rotation; directory identity does not appear in the audit subject. |
| External runner cannot use a directory application but policy permits a Kubernetes identity | Exported TokenRequest ServiceAccount token | CI must custody, rotate, and delete the exported bearer; projected auto-rotation is unavailable outside a Pod. |
| A user principal is mandatory but MFA or interactive Conditional Access is enforced | Do not use ROPC; use device code if policy permits it | A human seed and persistent cache remain operational dependencies. |
| Legacy user/password integration is the only viable path and policy has no interactive requirement | [ROPC](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth-ropc) from the existing guide, as an exception | CI stores a directory password; MFA, passwordless users, and interactive Conditional Access are incompatible. |

Break-glass credentials are an emergency recovery path, not a standing pipeline
identity. The existing guide owns their operational procedure.

## The directory machine identity

Use a dedicated confidential application for CI. Do not reuse the console client
credential: doing so collapses audit identities and increases the revocation
blast radius.

Historical report, not verified in this review: on one ROSA HCP 4.20.30
direct-external cluster, an application-only token reportedly lasted 3,900 seconds,
authenticated as `<issuer>#<object-id>` and drove a namespace-scoped action.
The original capture was not located, so this is not retained live evidence.
The documented issuer, audience and claim-mapping requirements still apply.
Acquire a fresh token per job and use its actual expiry; do not assume that
historical lifetime is your provider's policy.

There are two ways to arrange this on the cluster side:

### Option 1 — a dedicated audience, added to the cluster

Add the machine token's exact `aud` to the provider's plural audience list. This
is the clearest separation but changes provider configuration.

```text
# Covers: accepted audiences, token aud
# Does: Adds the machine token's audience to the provider's accepted list without disturbing the console client's.
# Why: Audience matching is any-of, so a dedicated machine audience keeps the two audit identities separable.
# Change: Removing the machine audience makes every machine token unauthenticated at the API server.
# Trap: This is a cluster provider change, so it needs the same review as any other authentication edit.
# Evidence: https://github.com/openshift/openshift-docs/blob/3fc89d132cac41b69f79d37fd8ee3f99d134700d/modules/external-auth-fields.adoc#L116-L129
accepted audiences = [<human-audience>, <pipeline-audience>]
token aud           = <pipeline-audience>
```

### Option 2 — an audience the cluster already accepts

Give the dedicated CI application an App Role on a resource whose audience is
already accepted, then request `<resource-identifier>/.default`. The cluster
configuration does not change. Decode the returned token and compare its `aud`
byte for byte; do not assume it is a bare application ID rather than an `api://`
URI.

Microsoft documents the [client-credentials flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-client-creds-grant-flow),
[App Roles](https://learn.microsoft.com/en-us/entra/identity-platform/howto-add-app-roles-in-apps),
and [`.default` scope](https://learn.microsoft.com/en-us/entra/identity-platform/scopes-oidc#the-default-scope).
The App Role, assignment, and consent steps are tenant operations and are not
performed by this repository.

## One username claim serves humans and machines

One provider username mapping serves human and machine tokens here. A
human-oriented claim such as `preferred_username` can be absent from an
application-only token. For Entra ID, Microsoft documents `profile` as required
to receive [`preferred_username` and `oid` in an ID token](https://learn.microsoft.com/en-us/entra/identity-platform/id-token-claims-reference).
Select an immutable claim proven present in both populations, typically `sub` or
an issuer object identifier.

This is the machine path's main human-side consequence: choosing `sub` or an
object identifier so the app token can authenticate also changes **human**
subjects from email-style names to issuer-qualified values. Treat the mapping as
one joint human-and-machine identity contract, not a pipeline-only option.

## RBAC subjects on this architecture

RBAC matches the string from the authenticated request and does not require an
OpenShift `User` object. Bind the complete subject returned by `oc auth whoami`:

```yaml
# Covers: subjects, apiGroup, kind, name
# Does: Binds the complete realized external-auth user string as one Kubernetes RBAC subject.
# Why: RBAC compares the authenticated string exactly and does not infer an OpenShift User object.
# Change: Removing the issuer prefix or selecting another kind prevents the intended subject from matching.
# Trap: A bare object identifier can look plausible while granting no access to an issuer-qualified identity.
# Evidence: Observed behavior, not vendor-documented
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    # Observed behavior, not vendor-documented: this issuer rendered the
    # subject as <issuer-url>#<machine-object-id>; the format is not universal.
    name: <issuer-url>#<machine-object-id>
```

See [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
and [OpenShift external authentication](https://github.com/openshift/openshift-docs/blob/3fc89d132cac41b69f79d37fd8ee3f99d134700d/authentication/external-auth.adoc).

`examples/pipeline-identities/external-auth/machine-identity-binding.yaml` is the runnable form of
the block above. The separate `service-account/service-account.yaml` binds a Kubernetes
ServiceAccount to the same Role, so authorization stays comparable while
authentication changes.

## Custody-safe token acquisition

`scripts/utils/fetch_oidc_client_token.py` reads `OIDC_CLIENT_ID` and
`OIDC_CLIENT_SECRET` from the environment, sends the secret only in the TLS
request body, checks exact audience membership, and writes only the bearer to a
new owner-only file. It never prints the response body or a token prefix.

**This helper belongs to this architecture only.** The token it fetches is accepted by the
API server of a direct-external cluster. On a built-in-OAuth cluster the same
token authenticates nothing, and no argument to this script changes that.

```bash
# Covers: env:OIDC_CLIENT_ID, env:OIDC_CLIENT_SECRET, --token-url, --scope, --expected-audience, --output
# Does: Fetches one application token, enforces exact audience membership and writes it owner-only.
# Why: Body-safe custody and byte-exact audience validation prevent secret leakage and shape ambiguity.
# Change: A different scope changes the resource audience; omitting the audience check accepts an unusable token.
# Trap: Bare and api-prefixed identifiers are different audience strings even when they share one application.
# Evidence: https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-client-creds-grant-flow
# set +x prevents xtrace from echoing the secret; umask 077 makes every file
# this job creates owner-only before it exists.
set +x
umask 077
# Environment input keeps the secret out of argv; CI environment capture must
# also be disabled for these variables.
export OIDC_CLIENT_ID='<pipeline-client-id>'
export OIDC_CLIENT_SECRET='<pipeline-client-secret>'

# .default requests the configured application permissions for a resource.
# Ref: https://learn.microsoft.com/en-us/entra/identity-platform/scopes-oidc#the-default-scope
# The expected aud check is exact string membership: api://<identifier> and
# <identifier> are different values.
python3 scripts/utils/fetch_oidc_client_token.py \
  --token-url 'https://<issuer-host>/<token-path>' \
  --scope '<resource-audience>/.default' \
  --expected-audience '<resource-audience>' \
  --output '<owner-only-job-directory>/access-token'

unset OIDC_CLIENT_SECRET
```

Use the token file to build a job-local kubeconfig. Do not pass the token with
`oc --token`, put it in an environment dump, or allow shell tracing.

---
