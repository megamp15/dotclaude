---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/microservices-architect/references/data.md
ported-at: 2026-04-17
adapted: true
---

# Data management in distributed systems

## Database per service (non-negotiable)

Each service owns its data store. No other service reads or writes those
tables directly — ever. If a service needs data from another service, it
asks via API or subscribes to events.

**Why this rule is strict:**

- Sharing a DB couples deploys. Schema change in service A breaks service B's
  query.
- Sharing a DB prevents independent scaling or technology choice.
- Sharing a DB hides domain boundaries — the schema becomes the interface.
- Debugging becomes a mystery: "who wrote this row?"

**"But we need the data"** → you need an API or an event. Not a direct DB.

## Consistency model per service

Each service picks the consistency it needs for its own domain:

| Domain | Typical fit |
|---|---|
| Money (ledger, payments) | Strong consistency, SERIALIZABLE where needed |
| Inventory reservation | Strong within a context; eventual across contexts |
| User preferences | Eventual consistency is fine |
| Analytics / reporting | Eventual, read from a projection |
| Search | Eventual; index updated from events |

## Cross-service data sharing

### API call (pull)

Service B calls service A synchronously for the data.

**Pro:** always fresh.
**Con:** coupling, latency, cascading failure.

Use for: tiny amounts of data that must be absolutely current and on the
critical path anyway.

### Event projection (push)

Service A emits domain events. Service B maintains its own copy/projection
by subscribing.

**Pro:** loose coupling, local reads, survives A being down.
**Con:** eventual consistency, duplicate storage, schema evolution discipline.

**Default choice** for cross-service data needs. Uses async messaging
(pub/sub or stream).

### Shared read replica — almost always wrong

"Just give us read-only access to your DB" → no. The schema becomes the
contract, and you've created a distributed monolith.

## Event schema ownership

Each service **owns** the events it emits. Consumers adapt.

- Events are versioned.
- Schema changes are backward-compatible by default (add fields, don't remove).
- Breaking changes publish a new event version alongside the old; consumers
  migrate; old version retires on a schedule.
- Use a schema registry so consumers can validate at build time, not at
  runtime.

## Data duplication is fine

In a distributed system, the same "fact" lives in multiple places with
different shapes. That's correct:

```
Order Service:         authoritative orders table
Billing Service:       billing_invoice (projected from orders)
Analytics Service:     daily_order_rollup (aggregated from events)
Search Service:        order index (projected for query shape)
```

Each is optimized for its read pattern. Each is eventually consistent with
the source.

## Handling drift

Projections go stale. Plan for it:

- **Rebuild from scratch** should work — replay the event stream into a
  new empty projection.
- **Reconciliation job** — periodically compare projection to source, log
  and alert on drift.
- **Idempotent consumers** — replay must be safe.
- **Projection versioning** — when schema of projection changes, rebuild
  is the migration.

## Transactions across services

Short answer: **don't**. Use sagas instead. See `references/patterns.md`.

If you absolutely need cross-service atomicity, you may be drawing the
service boundary wrong — those aggregates might need to live in the same
service.

## Outbox pattern

Problem: service writes to its DB and publishes an event; if one succeeds
and the other fails, state diverges.

Solution: atomically write the event to an `outbox` table in the same DB
transaction as the business write. A separate process drains `outbox` to
the broker.

```sql
BEGIN;
  INSERT INTO orders (id, ...) VALUES (...);
  INSERT INTO outbox (aggregate_id, event_type, payload)
    VALUES ('ord_...', 'Order.Placed', '{...}');
COMMIT;

-- Drainer (separate process)
-- SELECT ... FROM outbox WHERE published_at IS NULL ORDER BY id LIMIT 100;
-- Publish to broker, then UPDATE outbox SET published_at = now() WHERE id IN (...);
```

Many frameworks (Debezium with CDC, transactional outbox libraries) automate
this.

## Inbox pattern

Mirror of outbox on the consumer side: write incoming events into an
`inbox` table in the same transaction as the side-effect. Provides
idempotency (the event_id key prevents double-processing on redelivery).

## Data migration during service extraction

1. **Dual write** — monolith and new service both write on every change.
2. **Backfill** — one-time import from monolith to new service.
3. **Dual read + compare** — read from both; log discrepancies; alert on drift.
4. **Switch reads** to new service.
5. **Stop writing to monolith** side.
6. **Remove old code and schema.**

Each step can be rolled back. Never jump to step 5 before 3 is clean.

## Backups per service

- Each service's data store has its own backup schedule.
- Restore is tested, at least quarterly, with documented RTO/RPO.
- Cross-service backups are not a thing — rely on outbox/event replay for
  rebuilding projections.

## Anti-patterns

- Shared database with "ownership" columns (`owned_by_service = 'orders'`).
  You've built a shared DB with extra steps.
- Synchronous foreign-key joins across service APIs. Coupling + latency.
- Eventual consistency where strong was required (e.g. money). Either
  model more tightly or redraw boundaries.
- Projections you can't rebuild. Always keep the source of truth (events
  or the owning service) replayable.
- Schema migrations coordinated across services. If two services migrate
  together, they're one service.
