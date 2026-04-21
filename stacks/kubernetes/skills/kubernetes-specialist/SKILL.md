---
name: kubernetes-specialist
description: Deep Kubernetes expertise — workload design (Deployment/StatefulSet/Job/DaemonSet), probes and lifecycle, resource requests/limits, PDBs + HPAs, StorageClasses + PVs, networking (Service types, Ingress, NetworkPolicy), RBAC, secrets, manifests hygiene, and debugging. Covers both managed (EKS/GKE/AKS) and bare-metal (Talos/k3s/kubeadm). Extends the rules in `stacks/kubernetes/` baseline.
source: stacks/kubernetes
triggers: /k8s-specialist, kubernetes, kubectl, Deployment, StatefulSet, DaemonSet, Job, CronJob, HPA, PDB, readiness probe, liveness probe, startup probe, PersistentVolume, StorageClass, Service, Ingress, NetworkPolicy, RBAC, helm, kustomize, operator, CRD, talos, k3s, EKS, GKE, AKS
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/kubernetes-specialist
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# kubernetes-specialist

Deep Kubernetes expertise. Activates when the question is about workload
shape, reliability, networking, or debugging — beyond basic `kubectl apply`.

> **See also:**
>
> - `stacks/kubernetes/` — baseline stack with manifest rules
> - `core/skills/homelab-infra/` — for Proxmox / Talos / k3s topology
>   questions
> - `core/skills/sre-engineer/` — reliability engineering at the
>   platform level
> - `core/skills/cloud-architect/` — when the question is really about
>   the managed control plane (EKS/GKE/AKS) or networking outside
>   cluster

## When to use this skill

- Choosing between `Deployment`, `StatefulSet`, `DaemonSet`, `Job`,
  `CronJob`.
- Setting probes, resource requests/limits, PDBs, and HPAs that don't
  fight each other.
- Debugging `CrashLoopBackOff`, `ImagePullBackOff`, pending pods, stuck
  rollouts.
- Designing `StorageClass` / `PersistentVolume` layouts.
- Wiring `Service`, `Ingress`, `NetworkPolicy`, and ingress controllers.
- Adopting operators and CRDs (when, when not).
- Designing RBAC and multi-tenancy.

## References (load on demand)

- [`references/workloads.md`](references/workloads.md) — choosing workload
  kinds, pod template anatomy, `initContainers`, probes, lifecycle hooks,
  topology spread, PodDisruptionBudgets, HPA/KEDA.
- [`references/networking.md`](references/networking.md) — Services
  (ClusterIP / NodePort / LoadBalancer / ExternalName / headless),
  Ingress controllers (NGINX, Traefik, Gateway API), NetworkPolicies,
  CoreDNS, service meshes briefly.
- [`references/storage.md`](references/storage.md) — PV/PVC lifecycle,
  StorageClasses, CSI drivers, volume modes, access modes, StatefulSet
  storage, backup strategies.
- [`references/security.md`](references/security.md) — RBAC
  (Role/ClusterRole bindings), ServiceAccounts + workload identity, Pod
  Security Standards, NetworkPolicy defaults, Secrets + external secret
  managers, image policy, OPA/Kyverno.
- [`references/debugging.md`](references/debugging.md) — the `kubectl`
  triage kit, reading events, `ephemeral containers` / `kubectl debug`,
  pods stuck in every state, node pressure, control-plane failures.

## Core workflow

1. **Know the cluster.** Managed (EKS/GKE/AKS) vs. self-managed (Talos,
   kubeadm, k3s) changes a lot — upgrade path, node lifecycle, default
   networking plugin, CSI drivers available.
2. **Reason about a single pod first**, then a workload controller
   (ReplicaSet, StatefulSet, etc.), then networking, then policy.
3. **Probes are the contract**: readiness for "should receive traffic",
   liveness for "should be restarted", startup for "give me time before
   liveness kicks in".
4. **Resource requests drive scheduling.** Without them, the scheduler
   packs pods poorly and limits are meaningless.
5. **Treat manifests like code** — Kustomize overlays or a Helm chart,
   review in PR, apply via GitOps (Argo CD, Flux).

## Defaults

| Question | Default |
|---|---|
| Stateless web / worker | `Deployment` + `HPA` |
| Stateful singleton (or sharded) | `StatefulSet` + headless `Service` |
| One pod per node (log shipper, node exporter) | `DaemonSet` |
| Run once / batch | `Job` / `CronJob` |
| Rollout strategy | `RollingUpdate` (default); `Recreate` only for singletons |
| Resource requests | Always set CPU + memory `requests`; set memory `limit` ≈ `requests`; CPU limit typically unset or generous |
| Probes | `readinessProbe` always; `livenessProbe` only with a proven restart-helps story; `startupProbe` for apps that boot > 30s |
| Pod disruption | `PodDisruptionBudget minAvailable: <N-1>` for every multi-replica Deployment |
| Storage | Managed cluster: the provider's default CSI (EBS / PD / Azure Disk). Homelab: Longhorn, OpenEBS, or NFS for RWX |
| Ingress | NGINX Ingress for simplicity; Gateway API where team is ready |
| Secrets | External Secrets Operator pulling from AWS Secrets Manager / Vault, not raw K8s Secrets |
| Policy | Kyverno for most teams; OPA Gatekeeper if already invested |
| Observability | Prometheus + Grafana + Loki + Tempo (or vendor equivalent) |

## Anti-patterns

- **No `resources.requests`.** The scheduler defaults to 0; your cluster
  will be packed until it collapses.
- **`livenessProbe` without a reason.** A misconfigured liveness probe
  restarts healthy pods and destabilizes rollouts.
- **Running as root, no `securityContext`.** Set `runAsNonRoot: true`,
  `readOnlyRootFilesystem: true`, drop all Linux capabilities unless
  needed.
- **`latest` tag in production images.** Pin by digest or immutable tag.
- **One `Deployment`, `replicas: 1`, no PDB.** One node drain = outage.
- **`hostNetwork: true` or `hostPath` mounts** outside a small set of
  audited system workloads.
- **Big `ConfigMap` changes without rolling the workload.**
  Deployments don't restart automatically on CM change — use a
  checksum annotation or sealed configs.
- **Operators for everything.** An operator for a 3-pod in-house service
  is almost certainly a Deployment + PDB + HPA in disguise.

## Output format

For manifest design:

```yaml
# Kind selection: <Deployment / StatefulSet / Job / ...>
# Why: <one line>
```

Followed by the full manifest with:

- Requests/limits.
- Probes.
- PDB.
- Labels/selectors.
- Security context.
- Key environment variables (with notes on secrets).

For debugging:

```
Symptom:
  <what the user sees>

What kubectl shows:
  <relevant commands + expected output fields>

Root cause hypothesis:
  <likely cause, in order>

Fix:
  <specific action>

Prevention:
  <policy / CI check / alert that catches this next time>
```
