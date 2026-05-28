# Infra Nodes — ROSA HCP vs ROSA Classic

Comparison of infra node topology, default workload placement, and what's required to configure a dedicated infra machine pool.

---

## Background

OpenShift infra nodes serve two purposes:

1. **Subscription cost** — nodes labelled `node-role.kubernetes.io/infra` are classified as infrastructure nodes and do not consume ROSA worker node entitlements
2. **Workload isolation** — platform services (ingress, monitoring, registry) are moved off general-purpose worker nodes onto dedicated infra nodes

The standard infra node label and taint:

```
Label:  node-role.kubernetes.io/infra: ""
Taint:  node-role.kubernetes.io/infra:NoSchedule
```

---

## ROSA Classic

> **TODO**: Audit a live ROSA Classic cluster and populate this section.

ROSA Classic ships with **3 dedicated infra nodes** as part of the default cluster topology. Red Hat pre-configures the platform operators so that ingress, monitoring, and image registry land on infra nodes from day one — no post-deploy configuration required.

### Default infra workloads (Classic — to be confirmed by audit)

| Namespace | Workload | Type |
|---|---|---|
| openshift-ingress | router-default | Deployment |
| openshift-monitoring | prometheus-k8s | StatefulSet |
| openshift-monitoring | alertmanager-main | StatefulSet |
| openshift-monitoring | thanos-querier | Deployment |
| openshift-image-registry | image-registry | Deployment |
| _others_ | _TBD from audit_ | — |

### Open questions for Classic audit

- Which DaemonSets have the infra toleration pre-applied?
- Which operator CRs carry the nodeSelector/tolerations (and what exact fields)?
- Are there any workloads on infra nodes beyond the traditional 3 (ingress, monitoring, registry)?
- What does `oc get nodes -l node-role.kubernetes.io/infra` show for taints?

---

## ROSA HCP

Audited against a fresh ROSA HCP 4.19 cluster (`autonode`, OCP 4.19.30, `m6g.xlarge`, 2-node single-AZ, `us-east-1`).

### Default topology

ROSA HCP has **no dedicated infra nodes** out of the box. All platform workloads land on the default worker machine pool. Configuring infra nodes is a customer responsibility.

### Pods without infra toleration (fresh HCP cluster — full audit)

All of the following lack `node-role.kubernetes.io/infra` toleration on a fresh cluster:

#### DaemonSets (run on every node)

| Namespace | DaemonSet | Notes |
|---|---|---|
| kube-system | konnectivity-agent | HCP control-plane connectivity |
| kube-system | global-pull-secret-syncer | |
| openshift-cluster-csi-drivers | aws-ebs-csi-driver-node | Node storage |
| openshift-cluster-node-tuning-operator | tuned | |
| openshift-dns | dns-default | **Critical** — node DNS |
| openshift-dns | node-resolver | |
| openshift-image-registry | node-ca | |
| openshift-insights | insights-runtime-extractor | |
| openshift-machine-config-operator | kube-rbac-proxy-crio | |
| openshift-monitoring | node-exporter | |
| openshift-multus | multus | **Critical** — node networking |
| openshift-multus | multus-additional-cni-plugins | |
| openshift-multus | network-metrics-daemon | |
| openshift-network-diagnostics | network-check-target | |
| openshift-network-operator | iptables-alerter | |
| openshift-ovn-kubernetes | ovnkube-node | **Critical** — node networking |

> **Important**: These DaemonSets *must* run on infra nodes for the nodes to remain functional (networking, DNS, storage). They need the infra toleration added — but they stay as DaemonSets running everywhere, they are not "moved" to infra nodes.

#### Deployments / StatefulSets

| Namespace | Workload | Move to infra? |
|---|---|---|
| openshift-monitoring | prometheus-k8s | ✅ Yes — via operator CR |
| openshift-monitoring | alertmanager-main | ✅ Yes — via operator CR |
| openshift-monitoring | thanos-querier | ✅ Yes — via operator CR |
| openshift-monitoring | prometheus-operator | ✅ Yes — via operator CR |
| openshift-monitoring | prometheus-operator-admission-webhook | ✅ Yes — via operator CR |
| openshift-monitoring | kube-state-metrics | ✅ Yes — via operator CR |
| openshift-monitoring | metrics-server | ✅ Yes — via operator CR |
| openshift-monitoring | monitoring-plugin | ✅ Yes — via operator CR |
| openshift-monitoring | telemeter-client | ✅ Yes — via operator CR |
| openshift-monitoring | openshift-state-metrics | ✅ Yes — via operator CR |
| openshift-monitoring | cluster-monitoring-operator | ⬜ Leave on workers |
| openshift-ingress | router-default | ✅ Yes — via IngressController CR |
| openshift-image-registry | image-registry | ✅ Yes — via imageregistry CR |
| openshift-console | console | ⬜ Leave on workers |
| openshift-console | downloads | ⬜ Leave on workers |
| openshift-console-operator | console-operator | ⬜ Leave on workers |
| openshift-cluster-samples-operator | cluster-samples-operator | ⬜ Leave on workers |
| openshift-deployment-validation-operator | deployment-validation-operator-catalog | ⬜ Leave on workers |
| openshift-gitops-operator | openshift-gitops-operator-controller-manager | ⬜ Leave on workers |
| openshift-insights | insights-operator | ⬜ Leave on workers |
| openshift-kube-storage-version-migrator | migrator | ⬜ Leave on workers |
| openshift-kube-storage-version-migrator-operator | kube-storage-version-migrator-operator | ⬜ Leave on workers |
| openshift-network-console | networking-console-plugin | ⬜ Leave on workers |
| openshift-network-diagnostics | network-check-source | ⬜ Leave on workers |
| openshift-service-ca | service-ca | ⬜ Leave on workers |
| openshift-service-ca-operator | service-ca-operator | ⬜ Leave on workers |

### How to configure infra nodes on HCP

See [`hack/infra-nodes/configure-infra-nodes.sh`](../hack/infra-nodes/configure-infra-nodes.sh).

**Prerequisites:**
- Infra machine pool provisioned with label `node-role.kubernetes.io/infra: ""` and taint `node-role.kubernetes.io/infra:NoSchedule`
- Nodes are `Ready`

**Run:**
```bash
# Dry run first
DRY_RUN=true ./hack/infra-nodes/configure-infra-nodes.sh

# Apply
./hack/infra-nodes/configure-infra-nodes.sh
```

The script runs in two phases:

1. **DaemonSet tolerations** — patches critical DaemonSets (networking, DNS, storage) so infra nodes remain functional after the taint is applied
2. **Operator CRs** — moves monitoring (`cluster-monitoring-config` ConfigMap), ingress (`IngressController`), and registry (`config.imageregistry.operator.openshift.io`) to infra nodes via their operator APIs (not direct pod patches, which operators would revert)

### Operator CR reference

#### Cluster Monitoring
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    prometheusK8s:
      nodeSelector: {node-role.kubernetes.io/infra: ""}
      tolerations: [{key: node-role.kubernetes.io/infra, effect: NoSchedule}]
    alertmanagerMain:
      nodeSelector: {node-role.kubernetes.io/infra: ""}
      tolerations: [{key: node-role.kubernetes.io/infra, effect: NoSchedule}]
    # ... (see script for full list)
```

#### Ingress
```bash
oc patch ingresscontroller default -n openshift-ingress-operator --type=merge -p '{
  "spec": {
    "nodePlacement": {
      "nodeSelector": {"matchLabels": {"node-role.kubernetes.io/infra": ""}},
      "tolerations": [{"key": "node-role.kubernetes.io/infra", "effect": "NoSchedule"}]
    }
  }
}'
```

#### Image Registry
```bash
oc patch config.imageregistry.operator.openshift.io/cluster --type=merge -p '{
  "spec": {
    "nodeSelector": {"node-role.kubernetes.io/infra": ""},
    "tolerations": [{"key": "node-role.kubernetes.io/infra", "effect": "NoSchedule"}]
  }
}'
```

---

## HCP vs Classic delta

> **TODO**: Populate after Classic cluster audit.

| Aspect | ROSA Classic | ROSA HCP |
|---|---|---|
| Infra nodes included by default | ✅ Yes (3 nodes) | ❌ No |
| Platform workloads pre-configured for infra | ✅ Yes (day-1) | ❌ No (customer responsibility) |
| Infra taint on default pool | ✅ Applied by Red Hat | ❌ N/A |
| DaemonSet tolerations pre-applied | ✅ (TBC from audit) | ❌ Must be patched manually |
| Monitoring operator CR pre-configured | ✅ (TBC from audit) | ❌ Must apply cluster-monitoring-config |
| Subscription savings | ✅ Infra nodes excluded | ✅ Infra nodes excluded |
| Relevant script | N/A (pre-configured) | `hack/infra-nodes/configure-infra-nodes.sh` |

---

## Audit commands

```bash
# Pods without infra toleration (what would go Pending after NoSchedule taint)
oc get pods -A -o json | jq -r '
  .items[] |
  select(.status.phase == "Running" or .status.phase == "Pending") |
  select(
    ((.spec.tolerations // []) | map(.key) | contains(["node-role.kubernetes.io/infra"])) | not
  ) |
  [.metadata.namespace, .metadata.name, (.spec.nodeName // "unscheduled")] | @tsv
' | sort | column -t

# Pods currently running on infra nodes
oc get pods -A -o wide --field-selector spec.nodeName=$(
  oc get nodes -l node-role.kubernetes.io/infra -o name | head -1 | cut -d/ -f2
) 2>/dev/null

# Verify infra nodes exist and are Ready
oc get nodes -l node-role.kubernetes.io/infra

# Verify taint is applied
oc describe nodes -l node-role.kubernetes.io/infra | grep -A5 Taints
```
