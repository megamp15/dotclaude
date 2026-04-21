# Scaling and operations

## The scaling problem

With HTTP, each request is routable to any instance. With
WebSocket, **the client is tied to one instance** for the
duration. This shapes everything else.

## Backplane: pub/sub

To broadcast a message to clients connected across multiple
nodes, nodes need a shared message bus.

### Redis Pub/Sub

- **Pros**: ubiquitous; simple; fast.
- **Cons**: fire-and-forget (no replay); single node scales
  modestly.
- **When**: small/mid scale; short-lived messages.

### Redis Streams

- **Pros**: durable; consumer groups; replay; ordered.
- **Cons**: more complex client code.
- **When**: need replay / resume.

### NATS

- **Pros**: purpose-built for pub/sub; millions of msgs/s;
  JetStream for durability.
- **Cons**: another piece of infra.
- **When**: medium to large scale; many topics.

### Kafka

- **Pros**: durable log; replay forever; strong ordering.
- **Cons**: heavy; latency higher than Redis/NATS.
- **When**: events are durable product data; analytics pipeline
  attached.

### Cloud provider

- AWS EventBridge, SNS/SQS, MSK.
- GCP Pub/Sub.
- Azure Service Bus / Event Grid.

Use whatever you already have for the "connection-backplane"
role, unless it's a bad fit (e.g., SQS's polling latency is too
high).

## Routing pattern

```
[client A] ── node 1 ──┐
                       ├── Redis channel "room:42" ──┐
[client B] ── node 2 ──┘                             │
                                                     │
        a publish to "room:42" is received          │
        by both nodes; each forwards to its         │
        local connections in the room              ─┘
```

### Implementation sketch

```python
async def on_connect(ws, user):
    room = user.room_id
    rooms[room].add(ws)
    await pubsub.subscribe(f"room:{room}")

async def on_pubsub(channel, payload):
    room = channel.split(":")[1]
    for ws in rooms[room]:
        await ws.send_json(payload)

async def publish(room, payload):
    await pubsub.publish(f"room:{room}", payload)
```

Channels per room keep fan-out narrow.

## Sticky sessions

Most LBs route a given TCP connection to a single backend; for a
long-lived WS this is automatic. Problems arise with:

- Client reconnect — can land on a different node.
- Session state tied to node.

Mitigations:

- Keep per-connection state in the connection handler only (not
  shared); reconnection replays from the backplane.
- If state must be sticky, use LB-level cookie sticky sessions
  (AWS ALB, nginx `ip_hash`). Usually avoidable.

## Connection limits

Node limits per instance:

- **File descriptors** — raise `ulimit -n` to 1M+.
- **Ephemeral ports** (outbound) — usually not an issue for servers.
- **Memory per connection** — 10–50 KB typical for idle; depends on
  per-connection buffers and library. Plan ~20k–100k connections
  per node.
- **CPU for broadcast** — linear in recipients; batch where you
  can.

### Go / Rust / Erlang / Node.js

Single-box capacity:

- **Go** — 100k+ connections per node common.
- **Rust (tokio)** — similar.
- **Erlang/Elixir (Phoenix)** — famous for 2M+ per node with
  tuning.
- **Node.js (uWebSockets.js)** — 100k+ feasible.
- **Python (FastAPI + uvicorn, aiohttp)** — lower (20k–50k);
  consider Starlette / ASGI with tuning.
- **Java / C#** — solid with Netty / Kestrel.

Rule: **pick a runtime comfortable with long-lived connections**.
Blocking runtimes (synchronous Python WSGI, Rails classic) won't
scale here.

## Backpressure

Fast producers + slow clients = memory bloat.

### Symptoms

- Memory grows unbounded.
- Other clients see latency spike.
- Node gets OOMKilled.

### Strategies

1. **Drop** — if client write buffer > N, drop oldest messages.
   Apt for real-time feeds (stock ticks, dashboards).
2. **Disconnect** — if client lagging by > N messages, close.
   Client reconnects and gets the latest. Apt for presence,
   heartbeats.
3. **Throttle** — slow down the producer. Hard to do in broadcast
   scenarios.
4. **Queue with cap** — per-client bounded queue; drop overflow.

### Implementation

```python
async def send_with_backpressure(ws, msg, timeout=1.0):
    try:
        await asyncio.wait_for(ws.send_json(msg), timeout=timeout)
    except asyncio.TimeoutError:
        await ws.close(code=1008, reason="slow client")
```

Or per-client queue:

```python
class Client:
    def __init__(self, ws):
        self.queue = asyncio.Queue(maxsize=100)
        self.ws = ws

    async def sender_loop(self):
        while msg := await self.queue.get():
            try:
                await asyncio.wait_for(self.ws.send_json(msg), timeout=5)
            except Exception:
                await self.ws.close(code=1011)
                return

    async def enqueue(self, msg):
        try:
            self.queue.put_nowait(msg)
        except asyncio.QueueFull:
            await self.ws.close(code=1008, reason="slow client")
```

## Metrics

Per node:

- **active_connections** (gauge).
- **connections_opened_total** / **connections_closed_total** (counters, by close code).
- **connection_duration_seconds** (histogram).
- **messages_sent_total** / **messages_received_total** (counters, by type).
- **broadcast_fanout_latency_seconds** (histogram).
- **queue_depth** (histogram, per-client backpressure).
- **auth_failures_total** (counter).

Cluster-wide aggregates from Prometheus.

### PromQL examples

```promql
# Active connections per node
sum by (instance) (websocket_active_connections)

# Connection close rate by code
sum by (close_code) (rate(websocket_connections_closed_total[5m]))

# Average connection lifetime
rate(websocket_connection_duration_seconds_sum[10m]) /
rate(websocket_connection_duration_seconds_count[10m])
```

## Logging

Per connection:

- Open: user ID, session ID, remote IP, user agent.
- Close: code, reason, duration, messages sent/received.
- Auth failures.
- Rate limit hits.
- Backpressure disconnects.

Sample non-essential message-level logs; full logs overflow.

## Load testing

Tools:

- **k6** — scriptable, good WebSocket support.
- **artillery** — YAML-configured, WS + SSE.
- **websocket-bench** (Node.js).
- **tsung** — Erlang, mature, heavy-duty.
- **Gatling** — Scala, WS support.

### k6 WebSocket example

```javascript
import ws from "k6/ws";
import { check } from "k6";

export const options = {
  scenarios: {
    ramp: {
      executor: "ramping-vus",
      stages: [
        { duration: "1m", target: 1000 },
        { duration: "5m", target: 10000 },
      ],
    },
  },
};

export default function () {
  const url = "wss://api.example.com/ws";
  const res = ws.connect(url, { headers: { Authorization: "Bearer X" } }, (socket) => {
    socket.on("open", () => socket.send(JSON.stringify({ type: "hello" })));
    socket.on("message", (msg) => { /* ... */ });
    socket.setTimeout(() => socket.close(), 60_000);
  });
  check(res, { "status is 101": (r) => r && r.status === 101 });
}
```

Load test goals:

- **Max steady-state connections** per node.
- **Broadcast fanout latency** at target concurrency.
- **Connection churn** (simulate mobile users reconnecting).

## Load balancer configuration

### AWS ALB

- Listener on 443, default action forward to target group.
- Target group HTTP / HTTPS with keep-alive.
- **Idle timeout** ≥ 3600s (default 60s is too short).
- **Stickiness** — off by default, fine.

### Nginx

```nginx
upstream ws_backend {
  least_conn;
  server 10.0.1.10:8080;
  server 10.0.1.11:8080;
}

server {
  listen 443 ssl http2;
  location /ws {
    proxy_pass http://ws_backend;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }
}
```

### Kubernetes Ingress (nginx)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ws
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/affinity: "cookie"
    nginx.ingress.kubernetes.io/session-cookie-name: "ws-sticky"
```

## Managed options

If ops is too heavy for your team:

- **Pusher / Ably** — hosted pub/sub + WS; generous free tier;
  vendor lock-in.
- **Centrifugo** — OSS, self-host; highly tunable; WS + SSE.
- **LiveKit** — OSS WebRTC + WS for media + data.
- **AWS AppSync / API Gateway WebSockets** — managed WS; pay-per-
  message; 2h connection cap.

Managed = trading $ for reliability and less operational overhead.

## Rollout / rollback

- **Canary**: route a small % via a secondary path (`/ws-v2`) that
  points to new nodes.
- **Broadcast "please-reconnect"** on rollout so clients land on
  new version.
- **Rolling restart**: stagger so not all clients reconnect at
  once; thundering herd protection on the backplane.
- **Blue/green**: keep old fleet warm for rollback; drain before
  tearing down.

## Common failures

| Symptom | Likely cause |
|---|---|
| Connections silently dropped after 60s | LB idle timeout default |
| "1006 abnormal closure" in logs | Network drop; no close handshake |
| OOM on a single node | Backpressure not enforced |
| Load uneven across nodes | LB sticky sessions over-aggregate |
| Messages lost on reconnect | No resume / replay; fix with ID-based resume |
| Browser stops after ~6 tabs | Per-origin WS limit; consolidate |
| Intermittent 401 mid-session | JWT expired; implement re-auth |
| CPU spike on broadcast | N² fanout; batch or shard rooms |
| Heartbeat false positives | Timeouts tight vs. variable network latency |

Run through these on any incident triage.
