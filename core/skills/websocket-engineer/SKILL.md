---
name: websocket-engineer
description: Real-time bidirectional communication — WebSocket, SSE, WebRTC, and long-polling — with connection lifecycle, backpressure, reconnection with exponential backoff, heartbeats, horizontal scaling (pub/sub, sticky sessions), auth, and load testing. Distinct from plain HTTP APIs and messaging queues.
source: core
triggers: /websocket, socket.io, SSE, server-sent events, real-time, pub/sub, Redis streams, WebRTC, connection backpressure, heartbeat, sticky session, Centrifugo, Phoenix channels, gRPC streaming, long polling
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/websocket-engineer
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# websocket-engineer

Expertise on designing and operating real-time bidirectional
systems. Activates when the question is about WebSocket, SSE,
WebRTC data channels, or long-polling — the shapes and the
operational realities.

> **See also:**
>
> - `core/skills/sre-engineer/` — SLO, incident response
> - `core/skills/monitoring-expert/` — observability
> - `stacks/kubernetes/skills/kubernetes-specialist/` — horizontal
>   scaling + Ingress for websockets
> - `core/rules/security.md` — auth + CSRF equivalent for WS

## When to use this skill

- Choosing between WebSocket / SSE / WebRTC / long-polling for a
  real-time feature.
- Designing connection lifecycle: connect, auth, heartbeat,
  graceful close.
- Scaling: pub/sub backplane, sticky sessions, horizontal fanout.
- Debugging stuck / silently dead connections.
- Load testing sockets (`artillery`, `k6`, `websocket-bench`).
- Authenticating WebSocket connections securely.
- Handling backpressure (slow clients, fast producers).

## References (load on demand)

- [`references/shapes-and-lifecycle.md`](references/shapes-and-lifecycle.md)
  — WebSocket vs. SSE vs. WebRTC data channel vs. long-poll;
  connection lifecycle; auth patterns; heartbeats; graceful
  shutdown.
- [`references/scaling-and-ops.md`](references/scaling-and-ops.md)
  — horizontal scaling with pub/sub (Redis, NATS, Kafka), sticky
  sessions vs. connection routers, backpressure strategies,
  metrics, load testing, rollout/rollback.

## Core workflow

1. **Pick the simplest shape that works.** SSE for server-to-
   client unidirectional; WebSocket when you genuinely need
   bidirectional low-latency; WebRTC only for media/P2P; long-poll
   only when everything else is blocked by an enterprise proxy.
2. **Authenticate at connect, re-check on privileged ops.** Tokens
   via header (for SSE), subprotocol or first-message auth (for
   WS).
3. **Heartbeat.** TCP can hang for minutes silently. Heartbeats
   expose deadness in seconds.
4. **Plan for reconnect.** Client side: exponential backoff +
   jitter. Server side: resume / replay semantics as needed.
5. **Backpressure is mandatory.** A slow client can OOM your
   server; drop, disconnect, or queue with caps.
6. **Horizontal from day one.** Even if you start single-node,
   architect so a pub/sub broker sits between nodes and sockets.
7. **Observe connections as a first-class metric.** Active, new,
   closed, duration, per-endpoint.

## Defaults

| Question | Default |
|---|---|
| Shape | WebSocket for full duplex; SSE for server-push only |
| Path | `/ws` or `/events` — stable, versionless path |
| Subprotocol | `wss://` always (never plain `ws://` in prod) |
| Auth | Short-lived JWT / session cookie; validated on connect |
| Re-auth | On privileged operation within the socket |
| Heartbeat | PING / PONG every 20–30s; disconnect after 2 missed |
| Client reconnect | Exponential backoff from 500ms to 30s + jitter |
| Message framing | JSON with a discriminator (`type` field) |
| Compression | permessage-deflate only if messages are large text |
| Scaling | Redis pub/sub backplane or NATS; sticky sessions at LB |
| Rate limit | Per-connection + per-user + per-message-type |
| Max message size | Set explicitly, e.g., 256 KB |
| Max frame rate | Rate-limit inbound messages per second |
| Close codes | Use proper status codes (1000, 1008, 1011, 4xxx custom) |
| Metrics | active_conns, opens, closes, duration, errors, broadcast latency |
| Tests | Integration tests with real client; load test before launch |
| Load balancer | AWS ALB / nginx with `proxy_http_version 1.1` + `Upgrade` headers |
| Ingress (K8s) | `nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"` |

## Anti-patterns

- **WebSocket where SSE suffices.** Bidirectional when you only
  push one way complicates everything.
- **Long-polling in 2026.** Only if a proxy truly blocks WS/SSE.
- **No heartbeats.** TCP keepalives don't catch application-layer
  hangs.
- **Auth in query string.** Tokens in URLs end up in logs.
- **Unbounded client send buffer.** One slow client OOMs node.
- **Single-node state.** In-memory room membership that dies on
  pod restart = "logins randomly drop" complaints.
- **Reconnect without backoff.** Herd storms hit the server when
  it recovers.
- **No close code / no reason.** Operators can't diagnose why
  clients are dropping.
- **Message protocol ad-hoc.** Versionless payloads break on
  first evolution.
- **Assuming ordering.** WebSocket over TCP is ordered *per
  connection*; across reconnects, you need message IDs / sequence
  numbers.

## Output format

For a system design:

```
Shape:            WS | SSE | WebRTC DC | long-poll
Direction:        bidirectional | server-push
Latency target:   <ms>
Message rate:     <per client per sec>
Client count:     <concurrent>
Auth:             <mechanism>
Heartbeat:        <interval>
Reconnect:        <client policy>
Scaling:          <backplane, sticky/routing>
Message model:    <schema + versioning>
Ordering:         <per-conn | per-room | none>
Durability:       <at-most-once | at-least-once | exactly-once>
Backpressure:     <strategy + caps>
Rate limits:      <per-conn, per-user, per-message>
Observability:    <metrics + log shape>
```

For a debugging narrative:

```
Symptom:          <user-visible>
Observations:     <server-side + client-side logs>
Hypothesis:       <likely cause>
Diagnostic:       <how to confirm>
Fix:              <smallest change + rollout>
Prevention:       <metric or alert added>
```
