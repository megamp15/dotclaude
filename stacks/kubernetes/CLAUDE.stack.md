---
source: stacks/kubernetes
---

# Stack: Kubernetes

Cluster workload conventions — what good Kubernetes manifests and
day-2 operation look like. Layers on `core/`. Additive with `stacks/docker`
(almost always both apply) and `stacks/terraform` (for the cluster
itself, often).

## The premise

Kubernetes is a declarative API to a distributed state machine. The
failure modes that hurt are the ones that obscure that fact: imperative
`kubectl` edits, "it works on my cluster," manifests diverging from
actual cluster state, and config living in a person's shell history.

Treat the cluster like a database: all changes through version control,
applied via a tool, reviewed like code.

## Baseline conventions

- **GitOps over imperative.** Flux or Argo CD applies manifests from a repo. Hand-edited `kubectl apply` for exploration only.
- **Namespaces** per tenant / environment / team. Not one monolithic `default`.
- **Labels and annotations**: standard ones on everything (`app.kubernetes.io/name`, `app.kubernetes.io/instance`, `app.kubernetes.io/version`, `app.kubernetes.io/managed-by`). Consistent labels make every selector sane.
- **Resource limits on everything.** Requests = baseline; limits = ceiling. No-limits pods will eventually starve a node.
- **Liveness + readiness probes** on every container. Wrong probes are worse than no probes — get them right.
- **No `latest` tag.** Always pin to a digest (`image@sha256:...`) or specific version. `latest` = undefined rollback behavior.
- **No secrets in manifests.** Use Sealed Secrets, SOPS, External Secrets Operator, or Vault integration. Plaintext in git is a vuln.
- **PodSecurityStandards** (restricted or baseline) on every namespace; legacy PSP is removed.

## Manifest structure — one pattern that scales

```
deploy/
├── base/                     # common resources; no env-specific values
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   ├── ingress.yaml
│   └── kustomization.yaml
├── overlays/
│   ├── dev/
│   │   ├── patches.yaml      # dev-specific resource caps, replicas
│   │   └── kustomization.yaml
│   ├── staging/
│   │   └── kustomization.yaml
│   └── prod/
│       ├── patches.yaml      # prod-specific resource caps, replicas, PDB
│       └── kustomization.yaml
└── charts/                   # Helm charts if/when Kustomize doesn't fit
```

Kustomize or Helm, pick one. Hybrid works but multiplies cognitive load. Default recommendation: Kustomize for most cases; Helm when you're consuming upstream charts or publishing yours to a registry.

## Requests, limits, QoS

Three QoS classes based on how requests/limits are set:

- **Guaranteed**: requests == limits on every container. First in line for CPU, last to OOM-kill. Use for DBs, stateful services, anything where latency or availability matters.
- **Burstable**: requests < limits. Normal case for most workloads. Can use up to limit when cluster has capacity; OOM-kill ordering is middle.
- **BestEffort**: no requests/limits. First to OOM-kill when node pressure hits. Don't ship anything real as BestEffort.

**Sizing the request**: set requests to the P95 of observed usage (load-tested or measured). Too-low requests over-schedule the node → noisy neighbors. Too-high wastes capacity.

**Sizing the limit**: higher than the peak the app actually needs, with headroom. CPU limit throttles (no kill); memory limit OOM-kills (hard cutoff). For CPU, a limit 2-4× request is typical. For memory, limit close to request (or equal, for Guaranteed).

## Probes

Three kinds; different jobs:

- **Startup probe** — "is the container even up yet?" Disables liveness/readiness while running. Use for slow-starting apps (JVM, ML model loads). Probe passes once → disabled. Don't skip this on slow-starting workloads or liveness will kill them during boot.
- **Liveness probe** — "is the process alive and not wedged?" Fail → container restart. Keep it cheap; don't hit downstream services.
- **Readiness probe** — "is this pod ready for traffic?" Fail → removed from Service endpoints (no restart). Can check downstream dependencies (DB connection).

Common mistakes:

- Liveness probe hits downstream service → downstream blips cascade-restart your app. **Liveness should check only the process itself.**
- Readiness and liveness use the same endpoint → transient downstream failure restarts your app instead of just draining traffic.
- No startup probe on a 90-second boot → liveness kills the pod at 30 seconds, forever-restart loop.

Tuning: `initialDelaySeconds`, `periodSeconds`, `failureThreshold`. `timeoutSeconds` defaults to 1 — often too low for HTTP probes. Set it to ~2-5.

## Rollouts and PodDisruptionBudgets

- **RollingUpdate strategy** is the default and usually right. `maxSurge` + `maxUnavailable` control the pace.
- **For stateful / critical**: `Recreate` if rolling isn't safe, or use StatefulSet with `OrderedReady`.
- **PodDisruptionBudget** (PDB) for anything that matters: `minAvailable: 1` or `maxUnavailable: 0` (with `replicas >= 2`). Without a PDB, node drains during maintenance will take all replicas at once.

## Networking

### Service types

- **ClusterIP** — internal only. Default.
- **NodePort** — exposes on every node's IP. Almost never the right choice; use Ingress.
- **LoadBalancer** — cloud-provider LB; MetalLB on bare metal. Right for external APIs.
- **ExternalName** — DNS alias to something outside the cluster.

### Ingress controllers

Traefik, Nginx Ingress, Contour, Istio Gateway — pick one per cluster, don't run three. TLS via cert-manager (Let's Encrypt / ACME) almost always.

### NetworkPolicies

Default namespaces in Kubernetes are flat — any pod can talk to any pod. A NetworkPolicy per namespace enforcing "deny all, allow specific" is the right default:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: myapp
spec:
  podSelector: {}
  policyTypes: [Ingress]
```

Then layer allow rules on top. Cilium or Calico as CNI for full policy enforcement including egress.

## Storage

### Volumes

- **emptyDir**: ephemeral; gone on pod restart. Fine for scratch space, caches.
- **configMap / secret mounts**: config files; use `subPath` when mounting a single file into a directory of existing files (but beware — `subPath` breaks updates; plain mounts auto-update).
- **PersistentVolumeClaim** with a StorageClass: persistent. Right for databases, queues, stateful workloads.

### StorageClasses

- Default: whatever your platform provides (EBS gp3 on AWS, Azure Disk, GCE PD, Longhorn on-prem).
- `reclaimPolicy: Retain` for anything truly irreplaceable; `Delete` otherwise (and ensure you have backups).
- `WaitForFirstConsumer` for zone-aware scheduling in multi-AZ clusters.

## StatefulSets vs Deployments

- **Deployment**: stateless workloads, interchangeable pods, horizontal scaling trivial.
- **StatefulSet**: stable pod names + PVC templates + ordered rollouts. Databases, Kafka, Elasticsearch, anything where pod identity matters.
- **DaemonSet**: one pod per node. Log collectors, node-level monitoring.
- **Job** / **CronJob**: batch tasks, scheduled runs.

## ConfigMaps and Secrets

- **ConfigMaps** for non-secret config. Not "slightly secret" stuff — really just configuration.
- **Secrets** by default are base64-encoded, NOT encrypted at rest (unless you enabled etcd encryption). Base64 is not security.
- **ExternalSecrets / Sealed Secrets / SOPS** for secrets-in-git. Plaintext Secret manifests don't belong in repos.
- Avoid env-var-mounted secrets if possible (visible in `kubectl describe`, in crash dumps, in error messages). File mounts are safer.

## Observability

- **Logs**: write to stdout/stderr. Node-level collector (Fluent Bit, Vector) ships to wherever.
- **Metrics**: Prometheus, exposed at `/metrics`. ServiceMonitor / PodMonitor CRDs scrape them.
- **Traces**: OpenTelemetry; OTel collector DaemonSet; upload to Tempo / Jaeger / vendor.
- **Events**: `kubectl get events` — the first place to look when something's wrong.

## Common pitfalls

- **`kubectl edit` in production** — the change isn't in git; next GitOps sync reverts it silently.
- **Ignoring `spec.strategy`** on a Deployment — default RollingUpdate is fine, but explicit is better.
- **No `resources` block** on containers — BestEffort QoS; first to die under pressure.
- **Copying `liveness` to `readiness`** — different jobs; see probes section.
- **`hostPath` volumes** — couples the pod to a specific node; almost always wrong.
- **Running as root** — set `securityContext.runAsNonRoot: true`, `runAsUser: <nonroot>`. Use `securityContext.readOnlyRootFilesystem: true` where possible.
- **Capabilities defaults** — drop all, add only what you need: `capabilities: { drop: ["ALL"] }`.
- **Cluster-admin for service accounts** — if an app has cluster-admin, you've given up on RBAC. Least-privilege per-workload.
- **No resource quotas on namespaces** — a runaway workload can eat the whole cluster.

## Do not

- Do not run Kubernetes as your first choice for single-node workloads. Docker Compose is fine for those.
- Do not deploy anything without resource requests and limits.
- Do not store plaintext secrets in manifests or git.
- Do not use `latest` tags.
- Do not put cluster-admin on workload ServiceAccounts.
- Do not skip PodDisruptionBudgets on critical workloads.
- Do not use `hostNetwork: true` except for very specific infra workloads (CNI, ingress, kube-proxy analogs).
- Do not edit cluster state with `kubectl edit` / `kubectl patch` without a corresponding git change.
