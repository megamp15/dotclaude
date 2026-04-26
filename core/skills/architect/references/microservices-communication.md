---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/microservices-architect/references/communication.md
ported-at: 2026-04-17
adapted: true
---

# Communication patterns

Choose sync or async per interaction, not per service.

## Sync vs. async decision

| Interaction | Default | Why |
|---|---|---|
| User is waiting for the answer | Sync | You can't make them wait for an event loop |
| Mutation that must be atomic with caller | Sync or saga | Saga if it spans services |
| Cross-aggregate write across services | Async event | Loose coupling, survives partial failure |
| Fan-out to multiple consumers | Async pub/sub | One producer, many consumers |
| Work that can run seconds-to-hours later | Queue + background | Decoupled throughput |
| High-throughput streams | Streaming log (Kafka, Pub/Sub) | Replay, partitioning |

## Sync: REST vs. gRPC

| Dimension | REST (HTTP/JSON) | gRPC |
|---|---|---|
| Performance | Good | Excellent (HTTP/2 + Protobuf) |
| Schema | OpenAPI (optional discipline) | Protobuf (strict, code-gen) |
| Browser support | Native | Needs grpc-web proxy |
| Streaming | SSE or WebSocket | Built-in (client/server/bidi) |
| Tooling | Universal | Strong in polyglot Go/Java/Python/.NET |
| Best for | Public APIs, browser clients | Internal service-to-service |

**Default:** REST for anything a browser or external partner touches.
gRPC for internal high-traffic paths where schema discipline and performance
matter.

### REST baseline

- HTTPS always.
- JSON with a consistent naming convention (snake_case or camelCase — pick one).
- Error bodies follow RFC 7807 (`application/problem+json`).
- Versioning strategy decided upfront (URI, header, or date-based). See `core/skills/architect/references/rest-versioning.md`.
- Pagination strategy decided upfront (cursor for large/real-time, offset for small/static).
- Idempotency keys on `POST` that mutate.

### gRPC baseline

- Proto files in a central repo with CI validation.
- Backward-compatible field evolution (never renumber, never reuse tags).
- Deadlines on every call (no "infinite"); carry them through downstream calls.
- Interceptors for tracing, auth, correlation IDs.
- gRPC-Gateway or grpc-web when browsers need access.

## Async: queues vs. pub/sub vs. streams

| Pattern | Examples | Use when |
|---|---|---|
| Queue (point-to-point) | SQS, RabbitMQ, Service Bus | One worker consumes each message, load-level work |
| Pub/sub (fan-out) | SNS, EventBridge, Pub/Sub, Event Grid | Many consumers need the same event |
| Streaming log | Kafka, Kinesis, Pub/Sub with ordering | Replay, partitioning, exactly-once-ish, high throughput |

**Guidelines:**

- **Queues** — work to be done. One consumer wins per message.
- **Pub/sub** — facts that happened. Many consumers independently subscribe.
- **Streams** — time-ordered fact log. Consumers replay, maintain their own cursor.

## Event design

### Event naming

```
DomainObject.Action    → Order.Placed, Payment.Succeeded, User.Registered
```

Past tense. The event is a fact that has happened.

### Event payload

```json
{
  "event_type": "Order.Placed",
  "event_id": "evt_01HBX...",
  "event_version": 1,
  "occurred_at": "2026-04-17T12:00:00Z",
  "correlation_id": "cor_01HBY...",
  "payload": {
    "order_id": "ord_01HBZ...",
    "customer_id": "cus_01HC0...",
    "total_cents": 12345,
    "currency": "USD",
    "items": [ { "sku": "sku-1", "qty": 2 } ]
  }
}
```

Fields to always include: `event_type`, `event_id`, `event_version`,
`occurred_at`, `correlation_id`, `payload`.

### Schema evolution

- **Never remove a field** in a given version. Stop populating it, mark deprecated.
- **Never change a field's type.** Add a new field, deprecate old.
- **Always add new optional fields** with a default that matches prior semantics.
- For breaking changes: publish `v2` in parallel with `v1`, migrate consumers, retire `v1`.

Use a schema registry (Confluent Schema Registry, EventBridge Schema Registry, etc.) to enforce.

## Messaging semantics

| Guarantee | Reality |
|---|---|
| "Exactly-once" delivery | Doesn't exist in the network. Design consumers to be idempotent. |
| "At-least-once" | Typical. Consumer must deduplicate or be idempotent. |
| "At-most-once" | Rare and usually wrong — you lose messages on failure. |
| Ordering | Partition-local in Kafka/Kinesis; no global ordering. |

**Make consumers idempotent:**
- Use `event_id` as a dedup key.
- Upsert, not insert.
- Tolerate replay.

## Contract testing

Services evolve independently; contracts break silently without tests.

- **Consumer-driven contracts** (Pact, Spring Cloud Contract) — consumers publish
  expectations; producer CI fails when it breaks them.
- **Schema registry checks** — producer CI validates every change is
  backward-compatible with deployed consumers.

## Timeouts + deadlines

Parent timeout > sum of child timeouts. Always.

```
Client (30 s)
  → API Gateway (28 s)
    → Service A (10 s)
      → Service B (5 s)
        → DB (2 s)
```

Without this discipline, slow calls pile up and waste capacity on doomed
requests.

## Anti-patterns

- **Chatty sync chains** — `A → B → C → D`, each with a 100 ms timeout, produces
  a user-facing 400 ms floor and N× the failure probability. Coalesce or make async.
- **Async + polling** — "emit event, then poll the DB" — you've built sync
  the hard way. Use a callback or await-on-event.
- **Sync broadcast** — calling many services sequentially from one request.
  Fan out async, aggregate results; or don't broadcast at all.
- **No deadlines** — requests that never time out pin threads forever.
- **Ignoring dead-letter queues** — messages that repeatedly fail need a DLQ
  and an alert, not infinite retries.
