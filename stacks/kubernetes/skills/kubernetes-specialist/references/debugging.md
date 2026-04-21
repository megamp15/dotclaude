# Debugging

## The kubectl triage kit

```bash
# What's going on with this workload?
kubectl -n <ns> get deploy,rs,pod,svc,ingress -l app=<name>
kubectl -n <ns> describe deployment <name>
kubectl -n <ns> describe pod <pod>
kubectl -n <ns> logs <pod> -c <container> --previous
kubectl -n <ns> get events --sort-by='.lastTimestamp' | tail -30
kubectl -n <ns> top pod <pod>

# Endpoints match the Service selector?
kubectl -n <ns> get endpoints <svc>

# Per-pod conditions and container states
kubectl -n <ns> get pod <pod> -o yaml | less

# Ephemeral container (no need to rebuild image)
kubectl debug -n <ns> <pod> -it --image=nicolaka/netshoot --target=<container>

# Node-level
kubectl get nodes
kubectl describe node <node>
kubectl top node
```

Install [`kubectx` / `kubens`](https://github.com/ahmetb/kubectx) and
[`k9s`](https://k9scli.io/). They pay for themselves within a week.

## Pod phase → what's happening

| Phase | Likely cause | First check |
|---|---|---|
| `Pending` | Scheduling failed | `kubectl describe pod` events |
| `Pending` + "FailedScheduling" | No node fits | Requests too high / tolerations missing / PVC pending |
| `ContainerCreating` | Image pulling, volume mounting | Events — `ImagePullBackOff`, `FailedMount` |
| `ImagePullBackOff` | Bad image ref, private registry, missing pull secret | `kubectl describe`; try `kubectl create secret docker-registry` |
| `CrashLoopBackOff` | Container exits immediately | `logs --previous`; look at exit code |
| `Running` + not ready | readiness probe failing | `describe pod`; hit `/ready` manually via `port-forward` |
| `Terminating` (stuck) | finalizer / PVC unmount hang | `kubectl get pod <pod> -o yaml` and check `finalizers` |
| `OOMKilled` | Memory limit too low | logs (last Go / JVM dump) + bump memory |
| `Error` | App exited nonzero | `logs --previous`; treat exit code 137 = SIGKILL, 143 = SIGTERM |

## Rollout stuck

```bash
kubectl -n <ns> rollout status deployment/<name> --timeout=5m
kubectl -n <ns> rollout history deployment/<name>
kubectl -n <ns> rollout undo deployment/<name>              # revert to previous
kubectl -n <ns> rollout undo deployment/<name> --to-revision=N
```

Common causes:

- **New image never ready** — readiness probe broken or app misconfigured.
- **maxUnavailable + PDB combination** blocks progress — check PDB status:
  `kubectl get pdb -n <ns>`.
- **New pods Pending** — node pool out of room; HPA won't help if
  cluster-autoscaler is off.

## CrashLoopBackOff triage

```bash
# Exit code tells you a lot
kubectl -n <ns> describe pod <pod> | grep -A 3 "Last State"

# 0   — exited cleanly (readiness issue? process finished?)
# 1   — generic error
# 127 — command not found (bad ENTRYPOINT)
# 139 — SIGSEGV
# 137 — SIGKILL / OOMKill
# 143 — SIGTERM
```

```bash
kubectl -n <ns> logs <pod> --previous
kubectl -n <ns> logs <pod> -c <init-container> --previous
```

If logs are empty, the app might be dying before it logs — try:

```bash
kubectl -n <ns> debug <pod> --image=<same image> --copy-to=<name>-debug \
    --share-processes -- sleep 3600
kubectl -n <ns> exec -it <name>-debug -- sh
# then run the ENTRYPOINT manually, inspect
```

## ImagePullBackOff

- Typo in image ref → `kubectl describe pod`.
- Private registry, no pull secret:
  ```bash
  kubectl -n <ns> create secret docker-registry ghcr-pull \
      --docker-server=ghcr.io --docker-username=... --docker-password=...
  ```
  Then reference `imagePullSecrets: [{ name: ghcr-pull }]` on the pod
  spec or SA.
- Rate-limited (Docker Hub, especially). Move to a pull-through cache
  or your own registry.
- Arch mismatch — image built for amd64, node is arm64 (Talos / Apple
  Silicon clusters). Build multi-arch.

## FailedMount / FailedAttachVolume

```bash
kubectl -n <ns> describe pod <pod>
```

Look at the event message:

- "timed out waiting for the condition" → CSI driver stuck. Restart the
  CSI node pod.
- "already mounted" → the PV is mounted on another node still (previous
  pod didn't clean up). Cordon the old node, force-detach via cloud API
  if needed.
- "no such device" → underlying disk was deleted out from under K8s.

## Service has no endpoints

```bash
kubectl -n <ns> get endpoints <svc>
# NAME   ENDPOINTS   AGE
# api    <none>      10m
```

Causes:

1. **Selector mismatch** — Service selector doesn't match pod labels.
2. **Pods not ready** — readiness probe failing. Endpoints only include
   ready pods.
3. **Wrong port** — `targetPort` doesn't match a container port.

## Node pressure / eviction

```bash
kubectl describe node <node> | grep -A 5 Conditions
# MemoryPressure True → kubelet evicting pods
# DiskPressure True  → containers getting OOM-GC'd / images pruned
# PIDPressure        → too many processes
```

Fix:

- Short-term: drain + reboot.
- Long-term: scale node pool, raise kubelet eviction thresholds, tune
  log retention on nodes.

## DNS failures inside pods

```bash
kubectl -n <ns> exec -it <pod> -- nslookup kubernetes.default.svc.cluster.local

# If that fails:
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system logs -l k8s-app=kube-dns
```

Common:

- CoreDNS pods not running / crashing (ConfigMap error).
- NetworkPolicy blocking UDP 53 to kube-dns → add egress rule.
- Slow DNS due to `ndots: 5` — set a pod DNS config:
  ```yaml
  dnsConfig:
    options:
      - { name: ndots, value: "2" }
  ```

## Control-plane / API server issues

Signs:

- `kubectl` very slow, `i/o timeout`.
- `kube-apiserver` logs show `unable to connect to etcd` or
  `webhook ... timed out`.

Typical:

- **Admission webhook down** — a ValidatingAdmissionWebhook targeting
  all pods / deployments times out → every API call slow. Fix: make
  webhooks have `failurePolicy: Ignore` for non-critical checks.
- **etcd disk full / slow** — compact + defrag; provision faster disks.
- **Too many secrets / CRs** — large etcd; consider splitting.

## "kubectl apply says no diff but the pod isn't changing"

- Secret or ConfigMap referenced via `envFrom` changed, but Deployment
  doesn't notice. Roll it:
  ```bash
  kubectl rollout restart deployment/<name>
  ```
  Or set a checksum annotation on the pod template:
  ```yaml
  annotations:
    checksum/config: "{{ include (print $.Template.BasePath \"/configmap.yaml\") . | sha256sum }}"
  ```

## Getting a shell into a running pod

```bash
kubectl exec -it <pod> -c <container> -- sh
```

If `sh` isn't in the image (distroless, scratch):

```bash
kubectl debug <pod> -it --image=busybox --target=<container>
```

`--target` shares the target container's process namespace — you can
see its PID tree.

## When to page a cluster admin

Things you shouldn't debug alone:

- Node that's repeatedly `NotReady` after reboot.
- etcd errors in control-plane logs.
- Widespread `PLEG is not healthy` on kubelet.
- CSI or CNI pod restart storms.
- Anything affecting > 1 namespace simultaneously.

These are cluster-level concerns — get the platform team involved,
bring the `kubectl describe node`, `kubectl get events -A`, and the
cluster-component logs with you.
