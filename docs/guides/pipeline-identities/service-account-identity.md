<!--
Purpose: Give a CI pipeline a Kubernetes ServiceAccount identity on any ROSA HCP cluster.
What this is not: This is not a directory identity, and it does not grant install RBAC.
Prerequisites: A pipeline namespace, a least-privilege Role, and a rotation policy.
Authoritative references:
- https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/
- https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/#tokenrequest-api
- https://kubernetes.io/docs/reference/access-authn-authz/rbac/
-->

# ServiceAccount identity

**This is the recommended pipeline identity on every ROSA HCP cluster**, and on a
built-in-OAuth cluster it is the demonstrated and recommended machine path. Start here;
[the decision page](index.md) explains when something else is warranted.

TokenRequest is core Kubernetes, so the cluster's authentication architecture
changes nothing on this page. The machine steps are byte-for-byte the same on a
built-in-OAuth cluster and an external-auth one; only what *humans* do differs.
That is why a team can build its pipeline before the architecture decision is
made.

Examples for this page live in `examples/pipeline-identities/service-account/`.

## How RBAC actually decides


**RBAC compares strings from the authenticated request. It does not look up a
`User`, `Identity` or `Group` object before deciding.**

An authenticator returns a request identity: a username string, zero or more
group strings, an optional UID, and optional extra attributes. RBAC then
compares your RoleBinding's subject names against those strings, and that is the
entire mechanism.

Three practical consequences, all of which cause real support cases:

- A subject can be authorized even where the OpenShift `User` and `Group` APIs
  hold nothing matching it. On a direct-external cluster those APIs are absent
  altogether, and authorization still works.
- Conversely, creating a `Group` object does not grant anything unless the
  authenticated request actually carries that group string.
- So to find what to bind, read **the request**, not the object store. That is
  why this guide uses `oc whoami` and `oc auth whoami` rather than
  `oc get users` or `oc get groups`.

The UID is a fourth string and is **not** the RBAC username. Treat it as opaque.
On ROSA HCP 4.20.33 on 2026-09-04, a ServiceAccount and an OAuth-authenticated
directory user each carried a 36-character UUID-shaped UID. That observation
does not constrain other issuers or make UID a valid Kubernetes label value. If a
pipeline records identity, put the UID in an annotation, or hash it with a
documented mapping; do not assume it satisfies
[label-value syntax](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/#syntax-and-character-set).

To read all four strings at once, use the `SelfSubjectReview` API rather than
guessing from a username:

```bash
# Covers: auth whoami, -o
# Does: Returns the username, groups, UID and extra attributes for the current request.
# Why: These are exactly the strings RBAC compares, taken from the request rather than from any object.
# Change: Running it with a different kubeconfig reports that credential's identity, not yours.
# Trap: `oc whoami` prints only the username, so a group or UID problem is invisible through it.
# Evidence: https://kubernetes.io/docs/reference/kubernetes-api/authentication-resources/self-subject-review-v1/
oc auth whoami -o json
```

References: [Kubernetes authentication](https://kubernetes.io/docs/reference/access-authn-authz/authentication/),
[Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/),
[SelfSubjectReview](https://kubernetes.io/docs/reference/kubernetes-api/authentication-resources/self-subject-review-v1/)
and [OpenShift authentication and authorization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/authentication_and_authorization/understanding-authentication).

---

## Where the runner lives decides the delivery mechanism

| Runner location | Mechanism | Who holds the credential |
|---|---|---|
| **Inside** the cluster (a Pod, an in-cluster CI) | [Projected ServiceAccount token](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#serviceaccount-token-volume-projection) | Kubernetes. It mounts the token and rotates it; nothing is exported. Prefer this whenever it is available. |
| **Outside** the cluster (an external CI server, a hosted runner) | Mint and deliver: an authorized identity calls TokenRequest and places the bearer in the CI credential store | You do. Projected auto-rotation is unavailable outside a Pod, so custody, rotation and deletion become your process. |

Observed on ROSA HCP 4.20.33 on 2026-09-05: a Pod using an explicit projected
ServiceAccount token (requested lifetime 600 seconds, default API audience)
applied a Deployment and completed its rollout under the shipped namespaced
Role. Deployment deletion and Secret listing both returned `Forbidden`. The
bearer stayed in the Pod's mounted volume; no external kubeconfig or credential
store was used. This observes a real deploy through the recommended in-cluster
path; the earlier rotation measurement is a separate observation.

Most external CI is the second row, and the rest of this section is about it.

## One-time cluster-side setup

A platform administrator creates the identity and grants exactly what the deploy
needs — a namespaced Role, not `cluster-admin`:

```bash
# Covers: create serviceaccount, create rolebinding, --role, --serviceaccount, -n
# Does: Creates a dedicated pipeline identity and binds it to one namespaced Role.
# Why: A dedicated account keeps rotation, audit and deletion independent of application workloads.
# Change: Binding a ClusterRole, or using --clusterrole, widens the grant beyond this namespace.
# Trap: --serviceaccount takes namespace:name; omitting the namespace binds a subject that never matches.
# Evidence: https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/
oc create serviceaccount '<pipeline-service-account>' -n '<pipeline-namespace>'

oc create rolebinding '<pipeline-service-account>-deploy' \
  --role='<pipeline-workload-role>' \
  --serviceaccount='<pipeline-namespace>:<pipeline-service-account>' \
  -n '<pipeline-namespace>'
```

`examples/pipeline-identities/service-account/service-account.yaml` and
`namespace-and-role.yaml` are the declarative form of exactly these objects; use
whichever fits how the cluster is managed.

Observed on ROSA HCP 4.20.33 on 2026-09-04: this imperative
sequence — imperative setup, a per-run token, a job-local kubeconfig built from
it — created a Deployment in the target namespace, and `delete` on the same
resource was refused as `Forbidden` because the example Role omits that verb. The
observation covers the setup and deployment commands, not live execution of
the later exported-token custody helper or either CI orchestrator.

## Bind the ServiceAccount, not its rendered username

A ServiceAccount token authenticates with a username **and** three groups.
Observed on ROSA HCP 4.20.33 on 2026-09-04:

```text
username: system:serviceaccount:<namespace>:<service-account>
groups:
  - system:serviceaccounts
  - system:serviceaccounts:<namespace>
  - system:authenticated
```

`oc whoami` prints only the username, so it is tempting to copy that string into
a `kind: User` subject. **Use `kind: ServiceAccount` with a namespace instead.**

The `User` form does match — RBAC is comparing strings either way — but it is the
wrong shape for two reasons. It is brittle: nothing ties it to the object, so it
silently stops meaning what you intended if the account is recreated elsewhere,
and no tooling will tell you the subject has gone stale. And it hides the three
groups, which is the part that matters for a security review:

- `system:authenticated` is carried by **every** authenticated request on the
  cluster, human or machine. Any ClusterRoleBinding to it applies to your
  pipeline too.
- `system:serviceaccounts` and `system:serviceaccounts:<namespace>` are the same
  problem at narrower scope.

So your pipeline's effective permissions are the Role you wrote **plus** whatever
those three groups already carry. Auditing the RoleBinding alone understates the
grant. `oc auth can-i --list` from the bound session, shown below, is the read
that tells the truth.

See [ServiceAccounts](https://kubernetes.io/docs/concepts/security/service-accounts/)
and [default roles and role bindings](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#default-roles-and-role-bindings)
for what the platform binds to those groups out of the box.

## Per-run token mint

Apply the ServiceAccount and RBAC once, then request a token for each external
job:

```bash
# Covers: env:TOKEN_FILE, env:EXPIRY_FILE, env:RESPONSE_FILE, --namespace, --duration, --output
# Does: Requests a namespaced ServiceAccount token and retains its realized expiry separately from the bearer.
# Why: Per-job acquisition and owner-only files support explicit rotation without legacy token Secrets.
# Change: The requested duration is advisory and must not replace the server-returned expiration timestamp.
# Trap: JSON output contains the bearer, so an ordinary temporary file or CI artifact leaks credentials.
# Evidence: https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/#tokenrequest-api
# set +x prevents xtrace from echoing the bearer; umask 077 makes every file
# this job creates owner-only before it exists.
set +x
umask 077
TOKEN_FILE='<owner-only-job-directory>/service-account-token'
EXPIRY_FILE='<owner-only-job-directory>/service-account-expiry'
# The JSON response embeds the bearer in .status.token, so the temp file is
# itself a secret: umask 077 keeps it owner-only and the EXIT trap guarantees
# deletion even when jq fails.
RESPONSE_FILE=$(mktemp "${TMPDIR:-/tmp}/token-request.XXXXXX.json")
trap 'rm -f "$RESPONSE_FILE"' EXIT

# --duration is a request, not a guaranteed ceiling. JSON output retains the
# server's expirationTimestamp so rotation follows the realized value.
oc create token '<pipeline-service-account>' \
  --namespace='<pipeline-namespace>' \
  --duration='<rotation-policy-duration>' \
  --output=json >"${RESPONSE_FILE}"
jq -er '.status.token' "${RESPONSE_FILE}" >"${TOKEN_FILE}"
jq -er '.status.expirationTimestamp' "${RESPONSE_FILE}" >"${EXPIRY_FILE}"
chmod 600 "${TOKEN_FILE}" "${EXPIRY_FILE}"
```

The authenticated subject is
`system:serviceaccount:<pipeline-namespace>:<pipeline-service-account>`, on both
architectures. Confirm it rather than assuming it:

```bash
# Covers: --kubeconfig, whoami, --request-timeout
# Does: Proves which subject the API server authenticated for the issued token.
# Why: The RoleBinding must name this exact string, and a namespace mismatch produces a different one.
# Change: A token from another ServiceAccount or namespace authenticates as a different subject.
# Trap: Passing the token on the command line puts a credential in the process list and shell history.
# Evidence: https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/
# Read the bearer from the owner-only file into a kubeconfig or a request; do
# not expand it into argv. This example uses a job-local kubeconfig.
oc --kubeconfig='<owner-only-job-directory>/kubeconfig' whoami --request-timeout=30s
```

Then audit what that identity can actually do, which is not the same as what your
RoleBinding granted:

```bash
# Covers: --kubeconfig, auth can-i, --list, --namespace
# Does: Enumerates every permission the bound session really holds in the namespace.
# Why: The effective grant is your Role plus anything bound to the three groups the token carries.
# Change: Removing a group-scoped ClusterRoleBinding elsewhere narrows this list without touching your Role.
# Trap: Reviewing only the RoleBinding understates the grant, sometimes substantially.
# Evidence: https://kubernetes.io/docs/reference/access-authn-authz/rbac/#default-roles-and-role-bindings
oc --kubeconfig='<owner-only-job-directory>/kubeconfig' auth can-i --list \
  --namespace='<pipeline-namespace>'
```

Do this once when the identity is created, and again after any cluster-wide RBAC
change. It is the difference between "we granted three verbs" and "this token can
do three verbs".

## Do not change the audience unless the API server is not the recipient

`oc create token` also accepts `--audience`, which sets the `aud` claim the
[TokenRequest API](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/#tokenrequest-api)
puts in the issued token. The default is the API server's own audience, which is
what a pipeline talking to the cluster needs.

Requesting a different audience produces a **valid token that this API server
will not accept**. Observed on ROSA HCP 4.20.33 on 2026-09-04:
a token minted with a non-default audience was rejected with **HTTP 401
`Unauthorized`**, while a token minted with the default audience from the same
ServiceAccount in the same minute succeeded with **HTTP 200**.

This matters because the failure is indistinguishable from a credential problem.
The token is well-formed, unexpired and signed by the cluster; it simply names a
recipient that is not the API server, and the
[ServiceAccount credential authentication checks](https://kubernetes.io/docs/concepts/security/service-accounts/#authenticating-credentials)
refuses it. Set `--audience` only when the recipient is some other service that
validates this cluster's ServiceAccount issuer — and then do not reuse that token
against the API.

## Lifetime, and the two numbers that matter

Duration behavior observed on ROSA HCP 4.20.33 with built-in OAuth on
2026-09-04. Earlier reports described similar external-auth results; those
original captures were not located, so that comparison is not verified here.

| Requested | Realized | Note |
|---|---|---|
| `1s` | refused | Below the server minimum. |
| `2m` | refused | Also below it. The minimum on the tested service was **ten minutes**. |
| `10m` | 600 s, exactly | The shortest accepted value. |
| `8760h` (one year) | 31,536,000 s, exactly | |
| `87600h` (ten years) | 315,360,000 s, exactly | No warning, no cap, no truncation. |

The realized subject was `system:serviceaccount:<namespace>:<name>` in every
case. The documented mechanism is shared across architectures; this table
is a one-version observation.

The tested requests had a floor and no cap through ten years:

- **The floor is real.** A per-run token asked for in minutes will be refused
  outright, which is a confusing failure if you assumed any positive duration
  would be accepted. Ten minutes was the shortest value this service issued.
  Kubernetes allows a service to set its own minimum, so read the refusal rather
  than assuming this number travels.
- **Do not expect a useful service-side cap.** Nothing warned, capped or
  truncated through ten years in this run. Choose a short duration and enforce
  rotation. Minting is cheap; the cost is delivery and
  custody. Ask for the shortest duration your rotation process tolerates, above
  the floor.

This is also not a promise that every Kubernetes issuer behaves this way. The
TokenRequest API explicitly allows the issuer to return an expiry different from
the request, which is why the mint above retains `expirationTimestamp` rather
than the value it asked for.

## An open watch is not proof of token validity

This is the behaviour most likely to be misread in production.

Observed on ROSA HCP 4.20.33 with built-in OAuth on 2026-09-04. After a
ServiceAccount token expired, *new* requests were denied, while an
**already-open watch continued to receive events after that refusal**.

| Cluster | Denial onset after nominal expiry |
|---|---|
| 4.20.30, direct external auth — historical, not verified; original capture unavailable | `(30.186 s, 90.155 s]` |
| 4.20.33, built-in OAuth | `(15.428 s, 61.188 s]` |

Only the 4.20.33 row has a retained reading available to this review. Its bracket
means a successful new request at the lower sample and refusal at the upper
sample; it is not the exact expiry-to-refusal transition. The older derived
number is preserved as historical context, not a second verified reading.
Design for nominal expiry: neither number grants a grace period.

The consequence for a pipeline: one that holds a long watch looks healthy well
past its credential's expiry and then fails at the next *new* request, which is
usually a later step or a later run. The failure appears far from its cause.

So:

- reacquire **before** expiry, and before starting a new batch of requests;
- never treat a working watch as evidence that the credential is still valid;
  and
- do not design around the observed onset window; a sampled result is not a
  platform contract.

## The trade-off a security reviewer will raise

A ServiceAccount is a **local account on the cluster**. Organisations that
require every identity to originate in the central directory will see that as an
exception, and it is a fair objection rather than a misunderstanding: this
identity does not exist in the directory, is not covered by directory joiner and
leaver processes, and is not disabled when a person leaves.

What it gets in exchange is real: no client secret in CI, no dependence on a
provider's availability at deploy time, a subject that is scoped to one namespace
by construction, and revocation by deleting one object — with one measured
caveat about *verifying* that revocation, which
[the entry page records](index.md#why-the-serviceaccount-is-the-default). On a
built-in-OAuth cluster it is the demonstrated and recommended machine path.
Its OAuth server has no client-credentials grant; a directory-origin policy
therefore needs an explicit architecture or exception decision, not an assumed
OAuth flow. On an external-auth cluster, compare it with the documented
directory machine identity.

Whether the exception is temporary or permanent depends on which architecture the
cluster ends up using — which is exactly the decision
[the entry page](index.md) asks you to establish first.

## Worked pipelines

`examples/pipeline-identities/service-account/` carries a complete pipeline for
each of two common CI systems. They deploy the same manifests, with the same
identity, under the same custody rules; the difference is only how each system
expresses a job.

| Path | Runner | Where the token comes from |
|---|---|---|
| `service-account/jenkins/` | a Jenkins agent Pod, using the Kubernetes plugin | a credential in the Jenkins store, injected as an environment variable and written to an owner-only file |
| `service-account/gitlab/` | a GitLab runner | a masked, protected CI/CD variable, written to an owner-only file |

The helper deliberately requires **Python 3**. A fresh `mkdir -m 700` private
directory can support a shell-only design under the same exclusive job-ownership
boundary. This implementation retains Python for the file-descriptor operations
(`O_EXCL`, `O_NOFOLLOW`, permission/ownership checks and inode-bound refusal
cleanup) and JSON serialization of environment values. That also protects direct
helper invocation instead of relying solely on the wrapper's directory allocation.
The trade-off is one explicit runner-image dependency; Bash and Python 3 are
listed together in both CI image prerequisites. A shell rewrite would need to
retain the same custody boundary and handle kubeconfig string escaping.

Both call `run-deployment.sh`. It allocates a fresh mode-0700 directory under
`/tmp` and passes its exact kubeconfig path to `mint-kubeconfig.sh`. The helper
uses an exclusive, no-symlink open and sets mode 0600 **before** writing JSON
(kubeconfig also accepts JSON). Existing files, including dangling symlinks,
are refused without replacement. The private parent directory is required.

The bearer comes from the environment and reaches `oc` only through the file,
never argv. Shell tracing is disabled. The helper authenticates and compares the
exact ServiceAccount subject before deployment; failure removes its own output.
The wrapper removes that same destination on normal success/failure and catchable
termination. Cleanup failure makes the wrapper fail. Shared-UID hostile writers
are outside this model: run trusted job code on an isolated ephemeral agent.

`PIPELINE_TOKEN_EXPIRY` remains optional non-secret metadata. Its default
600-second margin is **advisory**, not derived from all remaining steps. A value
at or below that margin refuses the run; a missing or unparsable expiry is
reported as unobserved. Passing it does not prove validity throughout the
20-minute Jenkins budget. Apply and rollout now have separate process bounds,
but that does not turn the default margin into a whole-job lifetime proof.

The GitLab example reserves 18 minutes for script and two for `after_script`
inside its 20-minute job timeout, with a 15-minute outer deployment bound. Use
Runner 16.4 or later and ensure the runner's effective maximum permits that
budget. The fresh after-script shell verifies a non-secret cleanup completion
receipt; it does not inherit the random credential path. See
[runner timeout budgeting](https://docs.gitlab.com/ci/runners/configure_runners/#set-script-and-after_script-timeouts).
GitLab after-script failure does not change a successful script's job status;
missing cleanup evidence is an incident, not evidence of successful custody.

On 2026-09-05 the exact shipped GitLab YAML passed the GitLab 19.2.1 CI-lint API
with HTTP 200, `valid: true`, no errors and no warnings. This was static lint
(`dry_run: false`), not a pipeline execution or validation of the example's
placeholder credentials and targets.

On the same date, the exact shipped Jenkinsfile passed the real
Jenkins 2.568.3 `/pipeline-model-converter/validate` endpoint with
`pipeline-model-definition` 2.2293.v6e7193cec599 and Kubernetes plugin
4547.v52f3080db_8cd. Its 4,436 bytes had SHA-256
`f418ea2e2fa7dedffa1af32371fc0760e4457442346b6005963137ac340f5ba6`.
The response was `Jenkinsfile successfully validated.`; removing the final brace
produced a parser error. Both responses used HTTP 200, so inspect the body.
This disposable controller had zero executors and ran no job. Execution of
either wrapper by its orchestrator, credentials and target configuration remain
unobserved.

No shell trap, Jenkins `post`, or GitLab `after_script` guarantees cleanup after
SIGKILL, agent loss or a failed filesystem. Credentials stay outside artifact
and cache paths. Use ephemeral job storage with no retained credential volume;
the runner owner must destroy stranded storage and apply separately owned token
expiry/revocation. A successful deployment alone proves neither cleanup nor
revocation. See [GitLab after_script limits](https://docs.gitlab.com/ci/yaml/#after_script).

### Which token do the pipelines use?

Neither pipeline mints its own token. This example deliberately leaves
TokenRequest authority with a **separately authenticated rotator**, which delivers
the bearer machine-to-machine into the CI credential store. The initial
[bootstrap mint](#per-run-token-mint) is separate from steady-state rotation.

This is a design choice, not a Kubernetes limitation. A namespaced Role can grant
`create` on `serviceaccounts/token` with `resourceNames` restricting the target
ServiceAccount: the TokenRequest URL includes its name, unlike an unnamed
collection-create request. See the [request-name parser](https://github.com/kubernetes/kubernetes/blob/v1.33.0/staging/src/k8s.io/apiserver/pkg/endpoints/request/requestinfo.go#L193)
and [RBAC name matcher](https://github.com/kubernetes/kubernetes/blob/v1.33.0/plugin/pkg/auth/authorizer/rbac/rbac.go#L163).
Scoped automated delegation is possible when policy permits it; it does not grant
minting for every ServiceAccount. The example grant remains unchanged and contains
no TokenRequest authority. A rotator also needs an independent authentication and
renewal path; possession of an expired pipeline token cannot bootstrap renewal.

If your CI system can assume a cluster identity directly — for example an
in-cluster runner with a projected token — prefer that and skip the store
entirely.

## Custody

For external CI, keep the token in the CI credential store or an owner-only job
file, reacquire before expiry, and verify job-local cleanup with the failure
boundaries above. Prefer projected tokens when the workload runs inside Kubernetes.

## Authorization is not permission

Every identity above can receive the same Role or ClusterRole. **Authentication
does not imply permission and does not close image supply.** A pipeline can
authenticate perfectly and still fail because it lacks a verb, or because a
worker cannot pull one digest.

Use a namespace Role for ordinary workloads. Use a separately reviewed install
role for namespaced Operator operations. Platform administration owns namespace,
catalog, OperatorGroup and RBAC setup; on a disconnected cluster that pipeline also needs a
complete mirrored image closure, which is a separate problem with its own
failure modes.

The examples intentionally grant no credential administration, provider
mutation, catalog administration, mirror policy, or RBAC authoring.
