# Shapes and lifecycle

## Choosing the shape

| Shape | Direction | Protocol | When |
|---|---|---|---|
| **WebSocket** | Bidirectional | `ws://` / `wss://` (upgrade from HTTP) | Chat, collaborative editing, live games, bidirectional streams |
| **SSE** (Server-Sent Events) | Server → client only | Plain HTTP + `text/event-stream` | Dashboards, notifications, log tails, model-streamed LLM output |
| **WebRTC Data Channel** | Peer-to-peer | UDP + SCTP + DTLS | Low-latency P2P: voice/video, gaming, file share between peers |
| **gRPC streaming** | Server-, client-, bidi-streaming | HTTP/2 | Service-to-service; not browser-native (needs grpc-web) |
| **HTTP long-poll** | Legacy | HTTP | Last resort when proxies block WS/SSE |

### Default picks

- **User sees live updates** (order status, notifications, dashboard):
  **SSE**. Cheaper, survives more proxies, one-directional is
  enough.
- **User interacts both ways** (chat, collab, live cursor):
  **WebSocket**.
- **User-to-user real-time media**: **WebRTC**.
- **Machine-to-machine**: **gRPC** if you control both ends.

## WebSocket lifecycle

```
Client                              Server
  |                                   |
  |   HTTP GET /ws Upgrade request    |
  |---------------------------------->|
  |                                   |
  |   101 Switching Protocols         |
  |<----------------------------------|
  |                                   |
  |   [frames...]                     |
  |   PING → PONG every ~25s          |
  |                                   |
  |   Close (1000, "bye")             |
  |<----------------------------------|
  |   TCP FIN                          |
```

### Handshake

Client sends:

```
GET /ws HTTP/1.1
Host: api.example.com
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
Sec-WebSocket-Version: 13
Sec-WebSocket-Protocol: v1.chat, v1.notif
```

Server responds:

```
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
Sec-WebSocket-Protocol: v1.chat
```

### Framing

- Text frame: UTF-8.
- Binary frame: raw bytes.
- Control frames: PING, PONG, CLOSE.
- Fragmentation supported; most libraries hide it.

### Close codes

| Code | Meaning |
|---|---|
| 1000 | Normal closure |
| 1001 | Going away (client/server shutting down) |
| 1002 | Protocol error |
| 1008 | Policy violation |
| 1011 | Server error |
| 1012 | Service restart |
| 1013 | Try again later |
| 4xxx | Application-defined |

Always send a meaningful close code + short reason; "connection
closed by peer" with no code is an operability nightmare.

## Authentication

### WebSocket

Problem: browsers don't send custom headers on the WS handshake
easily. Options:

1. **Cookie-based** — if WS endpoint shares origin with auth
   cookie (`Secure`, `HttpOnly`, `SameSite`). Easiest for browsers.
2. **Subprotocol** — `Sec-WebSocket-Protocol: v1, Bearer.<jwt>`.
   Hacky but works around header issues.
3. **Query string token** — `wss://.../ws?token=...`. Logged in
   access logs. Avoid in production.
4. **First-message auth** — connect anonymously; send
   `{"type":"auth","token":"..."}` as first message; server holds
   the connection as un-authorized until then, with a short grace
   timeout (e.g., 5s).

### SSE

Server-Sent Events are pure HTTP. Use standard auth:

- Session cookie, or
- Bearer token in `Authorization` header (works with the
  `EventSource` polyfill / `@microsoft/fetch-event-source`, not
  native `EventSource`).

### Token freshness

JWTs expire. For a long-lived WS connection:

- Client refreshes the token via a separate HTTP endpoint.
- Sends `{"type":"refresh","token":"..."}` over WS.
- Server re-validates; if expired / invalid → close with 4401.

Re-auth for privileged operations:

```
Client: {"type":"delete_all","confirm":"<fresh token>"}
Server: verifies fresh-token timestamp is within 60s of delete intent.
```

## Heartbeat

### Why

- Detects half-open connections (network partition, NAT timeout,
  laptop slept).
- Keeps middleboxes from closing idle TCP.
- Gives you fast-fail detection for user-visible "offline" UI.

### Pattern

- Server sends PING every 20–30s.
- Client replies PONG.
- If server misses 2 consecutive PONGs, close (1011).
- Client auto-reconnects with backoff.

Most WS libraries have built-in ping/pong; enable.

For SSE, the server emits a comment line periodically:

```
: keepalive

```

Every 15s. Browsers reconnect `EventSource` automatically on
close.

## Reconnection

### Client

Exponential backoff + jitter:

```typescript
let delay = 500;
const MAX_DELAY = 30_000;

function connect() {
  const ws = new WebSocket(url);
  ws.onopen = () => { delay = 500; };
  ws.onclose = (e) => {
    if (e.code === 1000) return;    // normal close, don't reconnect
    const jitter = Math.random() * delay * 0.3;
    setTimeout(connect, Math.min(MAX_DELAY, delay + jitter));
    delay = Math.min(MAX_DELAY, delay * 2);
  };
}
```

### Server-side resumability

If reconnection dropped messages:

- Assign each broadcast a monotonic ID.
- Client sends `last_message_id` on reconnect.
- Server replays missing messages from a buffer (Redis / in-memory
  ring) or a durable log (Kafka).

Bound buffer size; drop oldest; tell client "gap" so it can do a
full refresh.

## Message protocol

### Schema with discriminator

```json
{"type": "message.new", "id": "m-1", "payload": { ... }}
{"type": "presence.update", "payload": { ... }}
{"type": "error", "code": "RATE_LIMITED", "message": "..."}
```

Required fields:

- **`type`** — discriminator. Handlers dispatch on this.
- **`id`** — monotonic message ID per connection or per room.
- **`payload`** — shape per type.

### Versioning

Include a major version in the subprotocol or first handshake:

```
Sec-WebSocket-Protocol: v2.app
```

Or include a `schema_version` in the first server message. Clients
validate; fall back / error if mismatch.

### Client library

Use a library that handles reconnect + message buffering:

- **Pusher / Ably / Centrifugo clients** — managed.
- **Socket.IO** — de-facto OSS; reconnection, rooms, acks. Requires
  Socket.IO server.
- **Phoenix Channels** — Elixir ecosystem; excellent semantics.
- **graphql-ws** — GraphQL subscriptions over WS.
- **Custom** — thin wrapper over native `WebSocket` is fine if you
  don't need rooms/acks.

## Graceful shutdown

- Server receives SIGTERM.
- Stop accepting new connections.
- Broadcast `"type":"server_restart"` with expected resume window.
- Close each WS with 1012 or 1013 so clients reconnect intelligently.
- Wait N seconds for flushes before SIGKILL.

In K8s: `preStop` hook that sleeps while LB drains + broadcasts
restart message.

## Ordering and delivery

WebSocket over TCP guarantees **ordered delivery within a single
connection**. Across reconnects:

- Use message IDs so clients can detect gaps.
- Choose semantics explicitly:
  - **At-most-once** — OK for ephemeral notifications.
  - **At-least-once** — durable buffer + client idempotency.
  - **Exactly-once** — message ID + idempotency key + server
    dedup.

## Browser limits

- **Connection limit per origin** — browsers cap typically 6 WS
  per tab, 200 per browser. Consolidate into a single multiplexed
  socket where possible.
- **CORS** doesn't apply to WS, but the `Origin` header is sent;
  check it server-side to prevent CSRF-like attacks from other
  origins.
- **Firewall / proxy hostility** — some corporate proxies strip
  `Upgrade`. Fallback to SSE or long-poll; Socket.IO / SockJS do
  this automatically.

## SSE specifics

Server:

```
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive
X-Accel-Buffering: no          # nginx; prevent buffering

event: message
id: 42
data: {"foo": "bar"}

```

Client:

```javascript
const es = new EventSource("/events", { withCredentials: true });
es.onmessage = (e) => console.log(JSON.parse(e.data));
es.addEventListener("message", ...);
es.onerror = (e) => /* EventSource auto-reconnects */;
```

Features:

- **Automatic reconnection** with `Last-Event-ID` header on reconnect.
- **UTF-8 only**; base64-encode binary if needed.
- **No request body**; purely server→client.

## WebRTC data channel

Only for:

- P2P real-time data (games, collaborative low-latency tools).
- Reducing server bandwidth when peers can talk directly.

Complexity: ICE, STUN, TURN, signaling server. Use a library
(Peer.js, Twilio, LiveKit, Daily.co) unless you really want to
own it.
