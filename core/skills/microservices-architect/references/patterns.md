---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/microservices-architect/references/patterns.md
ported-at: 2026-04-17
adapted: true
---

# Resilience & distributed-transaction patterns

## The resilience stack (always layered)

1. **Timeout** — nothing waits forever
2. **Retry with backoff + jitter** — transient errors only
3. **Circuit breaker** — fail fast when a dep is hot
4. **Bulkhead** — isolate resource pools
5. **Graceful degradation** — fallback path
6. **Health / readiness** — auto-healing input

Apply all, not some.

## Circuit breaker

Three states: CLOSED → OPEN → HALF_OPEN.

```
CLOSED  — requests flow, track failure rate
         → OPEN if failure rate breaches threshold in window

OPEN    — immediately fail (or fall back); no real requests
         → HALF_OPEN after cooldown

HALF_OPEN — allow small probe traffic
         → CLOSED if probes succeed
         → OPEN if any probe fails
```

### Tuning

| Dependency profile | Timeout | Circuit-open window |
|---|---|---|
| Fast internal service (p99 < 100 ms) | 5 s | 10–30 s |
| Medium external (p99 < 1 s) | 10 s | 30–60 s |
| Slow/batch (p99 > 1 s) | 30 s | 60–120 s |

### Apply to

- Every external HTTP call
- Every DB pool that can be saturated
- Third-party APIs (always)
- Cross-service RPC

## Retry with backoff + jitter

### Rules

- Retry **only transient errors**: timeouts, 429, 502, 503, 504, connection resets.
- Never retry 4xx (except 408 request timeout and 429 with Retry-After).
- Exponential backoff: `delay = base * 2^attempt + jitter`.
- Cap attempts (3–5). Bound total wait time, don't just count tries.
- Prefer **decorrelated jitter** over full jitter in high-contention environments.

### Idempotency key (required for retries on mutating calls)

```http
POST /payments
Idempotency-Key: cust-987-order-456-v1
Content-Type: application/json

{ "amount_cents": 12345, "currency": "USD" }
```

Server stores the key + canonical response for 24 h. Replays return the
cached response — no double-charge.

## Bulkhead

Isolate resource pools so one bad dependency doesn't starve others.

### Thread / task pools

```python
# Separate pools per dependency
payment_sem = asyncio.Semaphore(20)
inventory_sem = asyncio.Semaphore(20)
notification_sem = asyncio.Semaphore(10)

async def call_payment(data):
    async with payment_sem:
        return await payment_client.call(data)
```

If payments is slow, it pins 20 tasks — not all your tasks.

### Connection pools

```
Read-only pool:   50 connections
Write pool:       20 connections
Reporting pool:   10 connections
```

A slow reporting query can't drown real transactions.

### Per-tenant rate limits

In multi-tenant SaaS, rate-limit per tenant so one bad tenant can't DoS the
rest.

## Timeouts

Three kinds — always set explicitly:

- **Connect timeout** (2–5 s) — establishing a socket
- **Read timeout** (varies by dep) — waiting for response
- **Total timeout** (request-level budget)

Rule: parent timeout > sum of child timeouts. Budget deadlines down the call chain.

## Graceful degradation

Have a fallback for every critical dep:

| Dependency | Fallback |
|---|---|
| Recommendation service | Cached popular items |
| Feature-flag service | Local cache / defaults |
| Preferences service | Sensible defaults |
| Price calculation | Last-known-good price + stale marker |
| Notification service | Queue locally, deliver later |

No silent failures — user sees reduced functionality, not a broken page.

## Distributed transactions: the saga

2PC doesn't work across autonomous services. Use a saga with compensating
actions.

### Orchestration-based (simpler, clearer flow)

Central orchestrator holds state, calls each step, compensates in reverse
on failure.

```python
# Pseudo-code
async def place_order(order):
    try:
        await reserve_inventory(order)
        try:
            payment = await charge_payment(order)
            try:
                await schedule_shipment(order)
                return {"status": "placed"}
            except Exception:
                await refund_payment(payment)
                raise
        except Exception:
            await release_inventory(order)
            raise
    except Exception as e:
        await cancel_order(order)
        raise
```

For real use, persist saga state so you can resume after crash (see below).

### Choreography-based (decentralized events)

No orchestrator. Each service listens for events and reacts:

```
OrderService    emits  Order.Placed
InventoryService reacts, emits  Inventory.Reserved  OR  Inventory.Failed
PaymentService  on Inventory.Reserved, charges, emits  Payment.Succeeded
...
On failure at any step, a compensating event triggers the reverse chain.
```

Scales well when services are already event-first, but harder to trace.

### Saga state (durable)

```sql
CREATE TABLE saga_instances (
  saga_id        UUID PRIMARY KEY,
  saga_type      TEXT,
  current_step   TEXT,
  status         TEXT,  -- running / compensating / completed / failed
  payload        JSONB,
  created_at     TIMESTAMPTZ,
  updated_at     TIMESTAMPTZ
);
```

On orchestrator restart: load incomplete sagas, resume or compensate.

## Event sourcing

Store every state change as an event; current state = replay.

```
Traditional:    UPDATE orders SET status = 'shipped' WHERE id = 123;
Event-sourced:  append OrderShipped { order_id, tracking, carrier, at }
```

**Event store:**

```sql
CREATE TABLE events (
  event_id       UUID PRIMARY KEY,
  aggregate_id   UUID,
  aggregate_type TEXT,
  event_type     TEXT,
  event_data     JSONB,
  version        INT,
  occurred_at    TIMESTAMPTZ,
  correlation_id UUID,
  UNIQUE (aggregate_id, version)  -- optimistic locking
);
```

**Benefits:** full audit trail, time-travel, replay for debugging, multiple
read models from one source of truth.

**Costs:** eventual consistency, schema evolution discipline, snapshotting
for performance, larger storage footprint.

Use when the audit trail is required (finance, healthcare, regulated) or
when replay into new read models is a core capability. Don't use for simple
CRUD.

## CQRS (Command Query Responsibility Segregation)

Split write and read models:

```
Command side:   validates rules, writes to store (often event-sourced)
                emits events
Read side:      projects events into query-optimized models
                serves reads (denormalized, fast)
```

Different models optimize independently. Cost: two code paths, eventual
consistency.

Pairs naturally with event sourcing, but doesn't require it.

## Health checks

- **Liveness** — process is responsive. Kubernetes restarts on failure.
- **Readiness** — process can serve traffic (deps reachable). Pulled from LB on failure.
- **Startup** — boot finished. Gates the other probes.

```python
@app.get("/health/ready")
async def ready():
    checks = {
        "db": await check_db(),
        "cache": await check_cache(),
        "payments": await check_payments(),  # optional — readiness can be optimistic
    }
    ok = all(checks.values())
    return JSONResponse(
        content={"status": "ready" if ok else "degraded", "checks": checks},
        status_code=200 if ok else 503,
    )
```

Readiness should **not** cascade failures: if a *non-critical* dep is down,
still serve traffic (in degraded mode). Otherwise one bad downstream takes
your whole fleet out of the LB.

## Anti-patterns

- Retrying 4xx errors — won't work, just wastes budget.
- Infinite retries — eventually pins threads and cascades failure.
- Circuit breaker without fallback — fails fast into a 500.
- Timeouts only at the edge — internal calls still hang.
- Event handlers that aren't idempotent — every redelivery corrupts state.
- Saga steps without compensation — partial success that can't be rolled back.
- Event sourcing applied to CRUD — cost with no benefit.
