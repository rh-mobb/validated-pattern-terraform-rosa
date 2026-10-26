<!--
Purpose: Explain which pipeline identities exist on a cluster using the built-in OpenShift OAuth server.
What this is not: This does not add a client-credentials grant to the OpenShift OAuth server.
Prerequisites: A cluster whose oauth.config.openshift.io/cluster resource exists.
Authoritative references:
- https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/authentication_and_authorization/understanding-authentication
- https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/authentication_and_authorization/understanding-identity-provider
- https://kubernetes.io/docs/reference/access-authn-authz/rbac/
-->

# Built-in OAuth clusters

This is the default cluster this pattern creates, with or without OIDC identity
providers configured for human login. Confirm you are on one using
[the entry page](index.md#which-cluster-do-you-have) before relying on anything
below.

**Short answer: use a dedicated
[ServiceAccount](service-account-identity.md).** It is the demonstrated and
recommended machine path. If policy requires directory origin, resolve the
architecture or exception explicitly; do not try an unsupported OAuth grant.

## The OAuth grant boundary and the measured token result

**The OpenShift OAuth server has no client-credentials grant.** Its
[documented flows](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/authentication_and_authorization/configuring-internal-oauth)
are authorization code and implicit grant. Configure an OIDC identity provider
through the pattern's [`oidc_identity_providers`](../built-in-oauth-oidc.md) input
to add upstream login for users; this does not add a machine client-credentials flow.
The OAuth server maps the provider's claims to a cluster username and groups and
issues its own access token for the user's API requests. See the
[authentication model](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/authentication_and_authorization/understanding-authentication)
and [identity-provider configuration](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/authentication_and_authorization/understanding-identity-provider).

**A provider-issued token for a real directory user was refused HTTP
401 on ROSA HCP 4.20.33 on 2026-09-04.** The provider issued a valid access token for that directory
user; the API server returned `Unauthorized`. The same user logged in through
the OpenShift OAuth server and could use the API. This measured user-token result
is separate from the documented grant boundary.

For a pipeline, use the demonstrated ServiceAccount path below. If policy requires
a directory machine identity, the pattern's documented direct-external-auth path
uses a provider-issued token from a confidential application; evaluate that
cluster architecture with the [external-auth guide](external-auth-clusters.md).
Direct client-credentials JWT acceptance on the tested built-in-OAuth cluster was
not exercised. The recommendation does not depend on asserting a universal
machine-token refusal.

## Recommended: a dedicated ServiceAccount

Apply `examples/pipeline-identities/service-account/namespace-and-role.yaml` and
`service-account.yaml`, then request a token per
job. The mechanics are the same on either architecture and are in
[ServiceAccount identity](service-account-identity.md) below.

Use a **dedicated** ServiceAccount rather than reusing a workload's, so rotation,
audit and deletion do not affect running applications.

A projected ServiceAccount token applied and rolled out a Deployment on ROSA
HCP 4.20.33 on 2026-09-05; delete and Secret list were refused under the example
Role. The earlier same-work comparison with a directory machine identity is
historical and not verified here because its original capture was not located.
The directory-ownership trade-off is stated under
[ServiceAccount identity](service-account-identity.md).

## When a directory identity is required for audit

If policy requires that pipeline actions appear in the audit log under a
directory user rather than a ServiceAccount, a documented exception is a
person authenticating through the OAuth server and the pipeline reusing that
session. Treat that as a documented exception, not a design:

- the token is issued to a human principal, so the audit trail attributes
  automation to a person;
- there is no unattended re-issue — when the token expires, a human must log in
  again; and
- the cluster's OAuth access-token lifetime, not your pipeline schedule, decides
  how often that happens.

Read that lifetime rather than assuming one. Observed behavior, not
vendor-documented: on ROSA HCP 4.20.33 on 2026-09-04 the guest `oauth/cluster` resource had
**no `spec.tokenConfig` at all**, so the platform default applied and nothing in
the cluster stated a number.

```bash
# Covers: get, -o, auth can-i, patch
# Does: Reads whether this cluster states an OAuth token lifetime of its own.
# Why: An absent tokenConfig means the platform default applies, which is not a number this guide can supply.
# Change: Reading a different cluster returns that cluster's configuration.
# Trap: On a hosted control plane `oc auth can-i patch` returning yes is an RBAC answer, not permission to change it -- a validating admission policy can still deny the write, and does for image configuration.
# Evidence: Observed behavior, not vendor-documented
oc get oauth cluster -o jsonpath='{.spec.tokenConfig}'

# The permission check the Trap above warns about, so you can see the asymmetry
# for yourself. A `yes` here is an RBAC answer only: on a hosted control plane a
# validating admission policy can still refuse the write, and does exactly that
# for image configuration.
oc auth can-i patch oauth/cluster
```

If the requirement is genuinely "a non-human identity that is not a
ServiceAccount", the answer is a cluster created for direct external
authentication — an external-auth cluster — not a workaround on this one.

## Not a pipeline identity: the cluster administrator

The long-lived HTPasswd cluster administrator this pattern can create is a
break-glass and bootstrap identity. It is `cluster-admin`, it is a single shared
credential, and using it from CI collapses the audit trail and gives every
pipeline job full cluster authority. Bind a Role to a ServiceAccount instead.

## RBAC subjects on this architecture

A user authenticated through the built-in OAuth server appears to RBAC as the
username the identity provider mapping produced — a **bare** username, optionally
carrying a configured prefix. Its groups are the provider's group claim, also
bare. A ServiceAccount appears as a ServiceAccount subject with its namespace.

Observed behavior, not vendor-documented: on ROSA HCP 4.20.33 on 2026-09-04 with an OIDC
identity provider, a fresh login produced a bare username and a bare provider
group, with no issuer prefix on either.

Neither is issuer-qualified. If you have read an external-auth cluster, or copied a binding from
an external-auth cluster, **that is the difference that will silently fail**: an
`<issuer>#<object-id>` subject matches nothing here.

`examples/pipeline-identities/built-in-oauth/user-and-group-binding.yaml` shows both the
OAuth-authenticated user subject and the group subject, because an identity
provider that emits a groups claim lets you bind the group once instead of every
user. Confirm the realized strings before binding:

```bash
# Covers: whoami, auth whoami, -o, jq
# Does: Prints the exact subject and groups this request authenticated with.
# Why: RBAC compares those strings byte for byte and infers nothing from a similar name.
# Change: Binding a different string, or adding an issuer prefix, produces a binding that never matches.
# Trap: `oc get groups` answers a different question and misleads twice -- it lists cluster-scoped Group objects, so an ordinary user is refused, and a provider group carried in the token need not exist as an object at all.
# Evidence: https://kubernetes.io/docs/reference/access-authn-authz/rbac/
# The subject to bind is whatever this prints -- copy it, do not retype it.
oc whoami

# The groups this request actually authenticated with, taken from the provider's
# claim. This is the list RBAC matches against, and it is the one to read.
# Observed behavior, not vendor-documented: `oc get groups -o name` was refused
# for an ordinary user on ROSA HCP 4.20.33, because listing Group objects is a
# cluster-scoped read and a different question from "who am I right now".
oc auth whoami -o json | jq -r '.status.userInfo.groups[]?'
```

Then prove the binding grants, **from the identity's own session** rather than
by impersonation, because impersonation succeeds on the strength of your rights
rather than theirs:

```bash
# Covers: --kubeconfig, auth can-i, --namespace, create, delete
# Does: Checks one permitted verb and one deliberately omitted verb from the bound session.
# Why: A single positive check cannot distinguish a working binding from an over-broad one.
# Change: Widening the example Role changes both answers; narrowing it changes only the first.
# Trap: Running this as an administrator with --as tests your impersonation rights, not the binding.
# Evidence: Observed behavior, not vendor-documented
# Expect yes. The example Role grants create, get, list, watch, patch, update.
oc --kubeconfig='<identity-session-kubeconfig>' auth can-i create deployments \
  --namespace='<pipeline-namespace>'

# Expect no. The example Role omits delete on purpose, so a "yes" here means the
# session is carrying authority from somewhere other than this binding.
oc --kubeconfig='<identity-session-kubeconfig>' auth can-i delete deployments \
  --namespace='<pipeline-namespace>'
```

---
