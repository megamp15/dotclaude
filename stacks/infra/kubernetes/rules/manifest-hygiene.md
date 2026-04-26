---
source: stacks/kubernetes
name: manifest-hygiene
description: Minimum bar for every Kubernetes manifest — labels, probes, resources, security context, image pinning. Review any deployment against this before apply.
triggers: deployment, statefulset, daemonset, job, cronjob, pod, service, ingress, configmap, secret, kustomization, helm chart, k8s manifest
globs: ["**/*.yaml", "**/*.yml", "**/kustomization.yaml", "**/Chart.yaml", "**/values*.yaml"]
---

# Manifest hygiene checklist

Apply to every manifest before apply. If you can't say "yes" to each
line, the manifest isn't done.

## Every `Deployment` / `StatefulSet` / `DaemonSet`

- [ ] **Labels**: `app.kubernetes.io/name`, `app.kubernetes.io/instance`, `app.kubernetes.io/version`, `app.kubernetes.io/managed-by`.
- [ ] **`spec.strategy`** explicit (RollingUpdate with tuned `maxSurge`/`maxUnavailable`, or Recreate if intentional).
- [ ] **`spec.replicas`** set (not relying on implicit 1). Replicas ≥ 2 if availability matters.
- [ ] **`spec.template.metadata.labels`** matches `spec.selector.matchLabels`.
- [ ] **Container `image`** pinned to a digest (`image@sha256:...`) or a specific tag (`:v1.2.3`); never `:latest` or unversioned.
- [ ] **`imagePullPolicy`** explicit. For pinned tags, `IfNotPresent`.
- [ ] **`resources.requests`** set for cpu and memory.
- [ ] **`resources.limits`** set for memory (always) and cpu (usually; omit only if you know why).
- [ ] **`livenessProbe`** set; doesn't hit downstream services.
- [ ] **`readinessProbe`** set; reflects ability to serve traffic.
- [ ] **`startupProbe`** set if startup is slow (JVM, ML, big migrations).
- [ ] **`securityContext`**: `runAsNonRoot: true`, `runAsUser` / `runAsGroup` set, `readOnlyRootFilesystem: true` (use `emptyDir` for writable paths), `allowPrivilegeEscalation: false`, `capabilities: { drop: ["ALL"] }`.
- [ ] **`serviceAccountName`** explicit. Don't use the namespace's `default` SA for real workloads.
- [ ] **`terminationGracePeriodSeconds`** set if 30s (default) isn't right for your app.
- [ ] **Secrets mounted as files**, not env vars, when practical.

## For anything with ≥ 2 replicas

- [ ] **PodDisruptionBudget** (`minAvailable` or `maxUnavailable`). Without this, node drain takes them all.
- [ ] **Pod anti-affinity** or **topology spread constraints** so replicas don't all land on one node / zone.
- [ ] **HorizontalPodAutoscaler** if load varies; explicit min/max, not "scale to infinity."

## Every `Service`

- [ ] **`type`** explicit (`ClusterIP` is fine, just be explicit).
- [ ] **`selector`** matches deployment labels.
- [ ] **`ports.targetPort`** named, not hard-coded to a port number (so container port changes don't break the service).
- [ ] **`sessionAffinity`** set if the app needs it (usually not).

## Every `Ingress` / `HTTPRoute`

- [ ] **`ingressClassName`** (or Gateway reference) explicit.
- [ ] **TLS** configured; cert-manager annotation present; secret name predictable.
- [ ] **Host** not `*` or a placeholder; hostname from a real DNS zone you own.
- [ ] **`backend.service.port`** matches Service.
- [ ] **Path type** (`Prefix`, `Exact`, `ImplementationSpecific`) explicit.
- [ ] Rate limiting, if relevant — annotation or external.

## Every `ConfigMap` / `Secret`

- [ ] **No plaintext secrets in git.** SealedSecrets, SOPS, or ExternalSecrets.
- [ ] **Namespace explicit** (don't inherit from apply-time).
- [ ] **Mounted as files** when the app allows; env vars leak.
- [ ] For ConfigMaps with frequent updates: deployment has a checksum annotation (`checksum/config`) so pods restart when config changes.

## Every `PersistentVolumeClaim`

- [ ] **`storageClassName`** explicit.
- [ ] **`accessModes`** matches StorageClass support (most cloud block is `ReadWriteOnce` only).
- [ ] **`resources.requests.storage`** sized realistically; resizing isn't always online.
- [ ] **Reclaim policy** on the StorageClass you're using is understood — `Delete` or `Retain`?

## Every `NetworkPolicy`

- [ ] **`podSelector`** correctly scoped.
- [ ] **`policyTypes`** explicit (`Ingress`, `Egress`, or both).
- [ ] If enforcing egress, allow DNS (`kube-dns`:53) — otherwise DNS breaks.
- [ ] Documented — why does this rule exist? NetworkPolicies acquired piecemeal become a debugging nightmare.

## Every `Job` / `CronJob`

- [ ] **`backoffLimit`** set. Default is 6 retries.
- [ ] **`activeDeadlineSeconds`** for jobs that shouldn't run forever.
- [ ] **`ttlSecondsAfterFinished`** so completed jobs clean up.
- [ ] For CronJob: **`concurrencyPolicy`** (`Forbid` or `Replace` for most cases, not `Allow`).
- [ ] **`startingDeadlineSeconds`** if you care about missed runs.
- [ ] **`successfulJobsHistoryLimit` / `failedJobsHistoryLimit`** so history doesn't balloon.

## Helm-specific

- [ ] Chart has `values.schema.json` for documented defaults + validation.
- [ ] No `values.yaml` commits with real secrets. Use separate unencrypted defaults + encrypted overrides.
- [ ] `helm template` in CI to catch rendering errors before deploy.
- [ ] `helm lint` and `kubeconform` / `kubeval` against rendered output.

## Kustomize-specific

- [ ] Base is environment-agnostic; overlays supply env differences.
- [ ] No `kustomize edit set image` used outside a CI flow — it mutates files; hard to reason about.
- [ ] `namePrefix` / `nameSuffix` used per-overlay if the same cluster hosts multiple environments of the same app.
- [ ] `commonLabels` / `commonAnnotations` for env tagging.

## Security scan before apply

- [ ] `kubectl diff -f manifest.yaml` — actually see what's changing.
- [ ] Run manifests through **`kubesec`**, **`kube-score`**, or **`kube-linter`** — fast feedback.
- [ ] Run images through a scanner (Trivy, Grype) as part of CI before they get deployed.

## Anti-checklist — things that shouldn't be in any manifest

- `hostPath` volumes (unless you know why)
- `hostNetwork: true` (unless infra workload)
- `privileged: true`
- `capabilities.add: [SYS_ADMIN]` and friends
- `serviceAccountName: default` for anything real
- Hard-coded cluster-specific values (node names, pod IPs, specific PVCs)
- Secrets in environment variables when files would work
- `latest` tags
- Manifests that don't specify a namespace

If a manifest has any of these, the review stops until they're justified in writing or removed.
