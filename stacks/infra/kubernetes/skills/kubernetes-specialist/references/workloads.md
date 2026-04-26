# Workloads, probes, autoscaling

## Picking a workload kind

| Kind | When |
|---|---|
| `Deployment` | Stateless, horizontally scaleable, interchangeable pods |
| `StatefulSet` | Stable network ID (`<name>-0`, `<name>-1`), ordered rollout, persistent per-pod storage |
| `DaemonSet` | One (or some) pods on every matching node (log shippers, monitoring agents, CSI drivers) |
| `Job` | Run to completion, retry on failure |
| `CronJob` | Schedule `Job`s on a cron expression |
| `ReplicaSet` directly | Almost never — wrapped by Deployments |

## Pod template essentials

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  labels:
    app.kubernetes.io/name: api
    app.kubernetes.io/component: web
spec:
  replicas: 3
  selector:
    matchLabels: { app.kubernetes.io/name: api }
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 25%
      maxSurge: 25%
  template:
    metadata:
      labels: { app.kubernetes.io/name: api }
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port:  "9090"
    spec:
      serviceAccountName: api
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        fsGroup:   10001
        seccompProfile: { type: RuntimeDefault }
      containers:
        - name: api
          image: ghcr.io/mycorp/api@sha256:abc...  # pin by digest
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
          env:
            - name: POD_NAME
              valueFrom: { fieldRef: { fieldPath: metadata.name } }
            - name: POD_IP
              valueFrom: { fieldRef: { fieldPath: status.podIP } }
          envFrom:
            - configMapRef: { name: api-config }
            - secretRef:    { name: api-secrets }
          resources:
            requests: { cpu: 200m, memory: 256Mi }
            limits:   { memory: 256Mi }          # no CPU limit
          startupProbe:
            httpGet: { path: /healthz, port: http }
            failureThreshold: 30
            periodSeconds: 2
          readinessProbe:
            httpGet: { path: /ready, port: http }
            initialDelaySeconds: 0
            periodSeconds: 5
            failureThreshold: 3
          livenessProbe:
            httpGet: { path: /live, port: http }
            periodSeconds: 20
            failureThreshold: 3
          lifecycle:
            preStop:
              exec: { command: ["/bin/sh", "-c", "sleep 10"] }
          volumeMounts:
            - name: cache
              mountPath: /cache
          securityContext:
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
            capabilities: { drop: ["ALL"] }
      terminationGracePeriodSeconds: 60
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels: { app.kubernetes.io/name: api }
      volumes:
        - name: cache
          emptyDir: { sizeLimit: 512Mi }
```

Key points:

- **Labels**: Kubernetes recommends the `app.kubernetes.io/*` set
  (`name`, `instance`, `version`, `component`, `part-of`, `managed-by`).
- **Digest-pinned images** — immune to tag rewrites.
- **Non-root + read-only FS** are free wins.
- **Topology spread** distributes replicas across nodes so a node
  outage ≠ outage.
- **`preStop: sleep 10`** gives time for the Service endpoints to
  remove this pod before SIGTERM hits — dramatically reduces 502s on
  rollouts.

## Probes that behave

```yaml
startupProbe:   # only while the app is booting
  httpGet: { path: /healthz, port: http }
  failureThreshold: 30
  periodSeconds: 2                            # 60s total startup budget

readinessProbe: # should we route traffic?
  httpGet: { path: /ready, port: http }
  periodSeconds: 5
  failureThreshold: 3                         # 15s to drop from LB

livenessProbe:  # should the container be killed?
  httpGet: { path: /live, port: http }
  periodSeconds: 20
  failureThreshold: 3                         # 60s before restart
```

Rules:

- **Readiness** always. It's how rollouts and load balancers decide
  who gets traffic.
- **Startup** when cold start > 30s. Prevents liveness from killing
  mid-boot.
- **Liveness** only when "restart fixes a real wedge state". Otherwise
  skip — a misconfigured liveness probe is worse than none.
- Separate endpoints for `live` and `ready`. `live` should return
  200 as long as the event loop is responsive; `ready` should return
  503 when dependencies (DB, cache) are unhealthy.
- Use `httpGet` over `exec` when possible; `exec` probes are slow and
  can mask the real state.

## Resources: requests, limits, and QoS

```yaml
resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    memory: 256Mi
```

- **Requests** = scheduling reservation. Sum of requests must fit on a
  node for the pod to schedule.
- **Limits** = hard cap. Memory over limit → OOMKill. CPU over limit →
  throttled.
- **No CPU limit** is usually best for web workloads — throttling is
  less predictable than "use what's available". Set CPU requests as
  what you want the scheduler to reserve.
- **Memory limit = memory request** — guaranteed QoS class, best
  eviction behavior.
- **Guaranteed QoS** (requests = limits for CPU + memory) evicts last;
  BestEffort evicts first.

Tools that help: `vertical-pod-autoscaler` in recommendation mode,
Goldilocks, or manual trending via Prometheus (P95 of actual usage).

## PodDisruptionBudget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: api }
spec:
  minAvailable: 2
  selector:
    matchLabels: { app.kubernetes.io/name: api }
```

Or:

```yaml
spec: { maxUnavailable: 1 }
```

A PDB blocks **voluntary** disruptions (drain, upgrade, HPA scale-in)
from dropping below the floor. Does not protect against node crash or
hardware failure.

Every Deployment with > 1 replica should have a PDB.

## HorizontalPodAutoscaler

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: api }
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 3
  maxReplicas: 30
  metrics:
    - type: Resource
      resource:
        name: cpu
        target: { type: Utilization, averageUtilization: 60 }
    - type: Resource
      resource:
        name: memory
        target: { type: Utilization, averageUtilization: 75 }
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Percent
          value: 25
          periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
        - type: Percent
          value: 100
          periodSeconds: 30
```

Notes:

- **CPU-based autoscaling** needs `metrics-server` installed.
- **Custom metrics** (requests per second, queue depth): use
  `prometheus-adapter` or **KEDA** for event-driven scaling
  (Kafka lag, SQS depth, Redis list length).
- **`behavior`** prevents flapping: aggressive up, conservative
  down.

KEDA example:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
spec:
  scaleTargetRef: { name: worker }
  minReplicaCount: 0                    # scale to zero if idle
  maxReplicaCount: 50
  triggers:
    - type: kafka
      metadata:
        bootstrapServers: kafka:9092
        consumerGroup: workers
        topic: jobs
        lagThreshold: "100"
```

## StatefulSet particulars

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: postgres }
spec:
  serviceName: postgres-headless
  replicas: 3
  selector:
    matchLabels: { app: postgres }
  template:
    metadata:
      labels: { app: postgres }
    spec:
      containers:
        - name: postgres
          image: postgres:16
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
    - metadata: { name: data }
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: gp3
        resources: { requests: { storage: 100Gi } }
```

Key mechanics:

- **Headless Service** (`clusterIP: None`) gives per-pod DNS:
  `postgres-0.postgres-headless.ns.svc.cluster.local`.
- **`volumeClaimTemplates`** stamps out one PVC per replica,
  sticky to the pod ordinal.
- **Rollouts are ordered** (pod-0 → pod-1 → pod-2), from highest
  ordinal first (configurable).
- **Scaling down does NOT delete PVCs** — preserves data. Delete
  manually if you really want to.

## initContainers

Run before app containers; block until done:

```yaml
spec:
  initContainers:
    - name: wait-for-db
      image: busybox:1.36
      command: ["sh", "-c", "until nc -z db 5432; do sleep 1; done"]
    - name: migrate
      image: ghcr.io/mycorp/migrator:v1.2
      command: ["./migrate", "up"]
  containers: [...]
```

Use for: schema migrations, secret provisioning, config rendering, DNS
waits.

## Rolling update mechanics

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 25%          # how many can be down during rollout
    maxSurge: 25%                # how many extra can exist transiently
```

Common tuning:

- `maxUnavailable: 0, maxSurge: 1` — zero-downtime with conservative
  resource use; rollouts take longer.
- `maxUnavailable: 25%, maxSurge: 25%` — default, balances speed and
  safety.

Force a rollout without a manifest change (to pick up updated Secret
/ ConfigMap via `envFrom`):

```bash
kubectl rollout restart deployment/api
```

## Node affinity, taints, tolerations

```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: workload-type
                operator: In
                values: ["web"]
  tolerations:
    - key: "spot-instance"
      operator: "Exists"
      effect: "NoSchedule"
```

Use for:

- Pinning workloads to specific node pools (web vs. worker vs. GPU).
- Tolerating taints on spot / preemptible nodes.

Pod affinity / anti-affinity exist but `topologySpreadConstraints` is
usually the more sustainable choice.
