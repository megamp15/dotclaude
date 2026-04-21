# Fault catalog

Faults organized by target, with tool mappings and example
invocations.

## Pod / container faults (Kubernetes)

### Kill pods (random)

**Chaos Mesh:**

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: pod-kill
  namespace: chaos
spec:
  action: pod-kill
  mode: one                    # kill 1; alternatives: all, fixed, fixed-percent, random-max-percent
  selector:
    namespaces: [api]
    labelSelectors:
      app: api-service
  duration: "30s"
```

**Litmus:**

```yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosEngine
metadata:
  name: api-pod-delete
  namespace: api
spec:
  appinfo:
    appns: api
    applabel: app=api-service
  chaosServiceAccount: litmus-admin
  experiments:
    - name: pod-delete
      spec:
        components:
          env:
            - name: TOTAL_CHAOS_DURATION
              value: "60"
            - name: CHAOS_INTERVAL
              value: "10"
```

### Container kill / OOM / exec

Chaos Mesh supports:

- `pod-kill` — kill the pod.
- `pod-failure` — make pod unavailable without killing.
- `container-kill` — kill specific container.

## Network faults

### Latency injection

**Chaos Mesh NetworkChaos:**

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: api-db-latency
spec:
  action: delay
  mode: all
  selector:
    namespaces: [api]
    labelSelectors:
      app: api-service
  delay:
    latency: "500ms"
    correlation: "25"
    jitter: "50ms"
  target:
    mode: all
    selector:
      namespaces: [db]
      labelSelectors:
        app: postgres
  direction: to
  duration: "5m"
```

**Toxiproxy** (for app-level proxies):

```bash
toxiproxy-cli create -l localhost:5433 -u postgres:5432 pg
toxiproxy-cli toxic add -t latency -a latency=500 -a jitter=50 pg
# ... experiment ...
toxiproxy-cli toxic remove -n latency_downstream pg
```

**`tc netem`** on a node (Linux):

```bash
tc qdisc add dev eth0 root netem delay 500ms 50ms 25%
# ... experiment ...
tc qdisc del dev eth0 root
```

### Packet loss

```yaml
# Chaos Mesh
action: loss
loss:
  loss: "30"
  correlation: "25"
```

```bash
# tc netem
tc qdisc add dev eth0 root netem loss 30%
```

### Corruption / duplication / reorder

```yaml
action: corrupt
corrupt:
  corrupt: "5"
  correlation: "10"
```

### Bandwidth limit

```yaml
action: bandwidth
bandwidth:
  rate: "1mbps"
  limit: 20971520
  buffer: 10000
```

### Partition (network black hole)

```yaml
action: partition
direction: to
```

Good for simulating dependency outages or AZ isolation.

## DNS faults

**Chaos Mesh DNSChaos:**

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: DNSChaos
metadata:
  name: dns-random
spec:
  action: random                # or 'error'
  mode: all
  selector:
    namespaces: [api]
  patterns:
    - "payments.*"
  duration: "5m"
```

Simulates DNS giving stale / bad answers. Tests retries and
connection re-establishment.

## Stress faults

### CPU

**Chaos Mesh StressChaos:**

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: cpu-stress
spec:
  mode: one
  selector:
    namespaces: [api]
    labelSelectors:
      app: api-service
  stressors:
    cpu:
      workers: 4
      load: 80
  duration: "5m"
```

**stress-ng** directly:

```bash
stress-ng --cpu 4 --cpu-load 80 --timeout 300s
```

### Memory

```yaml
stressors:
  memory:
    workers: 2
    size: "512MB"
```

### I/O / disk

**Chaos Mesh IOChaos:**

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: IOChaos
metadata:
  name: disk-latency
spec:
  action: latency
  mode: one
  selector:
    namespaces: [db]
    labelSelectors:
      app: postgres
  volumePath: /var/lib/postgresql
  path: "/var/lib/postgresql/data"
  delay: "100ms"
  percent: 50
  duration: "10m"
```

### Disk full

```bash
# Inside a container
dd if=/dev/zero of=/tmp/fill bs=1M count=10000
```

Or a DaemonSet that drains a specified disk path.

## Node faults

### Drain node

```bash
kubectl cordon node-1
kubectl drain node-1 --ignore-daemonsets --delete-emptydir-data
# ...
kubectl uncordon node-1
```

### Delete node (simulate loss)

AWS FIS action or cloud console; validates pod rescheduling.

### Node-level network down

```bash
# via SSH
iptables -A INPUT -i eth0 -j DROP
iptables -A OUTPUT -o eth0 -j DROP
# ... experiment ...
iptables -F
```

Warning: you lose access to the node. Plan console access.

## Clock skew

**Chaos Mesh TimeChaos:**

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: TimeChaos
metadata:
  name: time-skew
spec:
  mode: one
  selector:
    namespaces: [api]
    labelSelectors:
      app: api-service
  timeOffset: "5m"
  duration: "3m"
```

Tests: TOTP / time-sensitive auth, cache expirations, token
validation, log order.

## HTTP / gRPC fault injection

Service mesh (Istio) fault injection:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api
spec:
  hosts: [api]
  http:
    - fault:
        delay:
          percentage: { value: 10.0 }
          fixedDelay: 5s
        abort:
          percentage: { value: 5.0 }
          httpStatus: 500
      route:
        - destination:
            host: api
```

Injects 10% 5s delay + 5% 500 errors. Clean way to test client-
side retries.

Linkerd has similar via ServiceProfiles.

## Application-level faults

### Toxiproxy

Language-agnostic TCP proxy with fault injection:

```bash
toxiproxy-cli create -l :6380 -u redis:6379 redis_proxy
toxiproxy-cli toxic add -t latency -a latency=200 redis_proxy
toxiproxy-cli toxic add -t slow_close redis_proxy
```

Point your app at `localhost:6380` instead of `redis:6379` in
test environments.

### In-code fault injection

For tests / dev environments, add a feature flag:

```python
if settings.FAULT_INJECT_DB:
    if random.random() < settings.FAULT_INJECT_DB_RATE:
        raise DatabaseTimeout
```

Gate behind env. Remove once you have real chaos tooling.

## AWS Fault Injection Simulator (FIS)

Actions (via AWS Console / Terraform):

- `aws:ec2:stop-instances`
- `aws:ec2:terminate-instances`
- `aws:ec2:send-spot-instance-interruptions`
- `aws:ecs:stop-task`
- `aws:rds:failover-db-cluster`
- `aws:rds:reboot-db-instances`
- `aws:eks:pod-network-latency`
- `aws:ssm:send-command` (arbitrary OS-level via SSM)
- `aws:elasticache:replicationgroup-interrupt-az-power`
- `aws:network:disrupt-connectivity` (simulate AZ outage)

FIS supports stop conditions (CloudWatch alarms) for auto-abort.

## Cloud-level / regional

### AWS region outage simulation

Via FIS `aws:network:disrupt-connectivity` scope=all-traffic on
an AZ. Or route-53 health-check-driven failover drill.

### Cross-region failover drill

- Announce DR drill.
- Set traffic to 100% in secondary region.
- Measure: did failover trigger? Did DNS propagate? Did data read
  from replica? How stale?

### GCP

- **Pre-emptible VMs** — 24-hour lifetime; test fleet resilience.
- **Instance Group rolling restart** — scheduled chaos.
- Compute API actions via Chaos Toolkit driver.

## Database faults

### Postgres

- Force failover: `pg_ctl promote` on standby.
- Connection pool exhaustion: `pgbench` to consume all.
- Slow queries via `pg_sleep(...)` inserted into triggers.
- Restart primary; watch replica promotion.

### Redis

- `DEBUG SLEEP 2` — blocks connections.
- Kill Redis sentinel leader.
- Fill memory to test eviction / OOM policy.

## Message-queue faults

### Kafka

- Stop a broker; verify rebalance.
- Partition leader move; test client reconnect.
- Lag injection: consumer pause without commit.
- Duplicate publish; test idempotency.

### RabbitMQ

- Stop a node in a cluster.
- Kill connections via management API.
- Force HA queue failover.

## Chaos scenarios (composite)

Real failures rarely come alone. Composite scenarios:

- **AZ outage** — latency + partition to one AZ for 30 min.
- **Stampede** — 5× traffic spike + one dep in other region down.
- **Rolling deploy bug** — deploy a "bad" canary, observe
  containment.
- **Cold start** — scale to zero then 1k req/s in 30s.
- **Post-incident thrash** — simulate recovery after 10 min
  outage; test client reconnect storms.

Run these only at higher maturity levels.

## Tool quick-reference

| Target | Tool |
|---|---|
| K8s pods | Chaos Mesh PodChaos / Litmus |
| K8s network | Chaos Mesh NetworkChaos / Cilium / Istio |
| K8s DNS | Chaos Mesh DNSChaos |
| K8s stress | Chaos Mesh StressChaos |
| K8s time | Chaos Mesh TimeChaos |
| K8s I/O | Chaos Mesh IOChaos |
| TCP proxies (any env) | Toxiproxy |
| Linux node network | `tc netem`, `iptables` |
| Linux process stress | stress-ng |
| Docker / non-K8s | pumba |
| AWS | AWS FIS |
| JVM | ChaosToolkit + Byteman |
| Service mesh faults | Istio / Linkerd fault injection |
| Commercial | Gremlin, Steadybit, Harness CE |
| Toolkit | ChaosToolkit (drivers for many) |
