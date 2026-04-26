---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/microservices-architect/references/decomposition.md
ported-at: 2026-04-17
adapted: true
---

# Service decomposition and boundaries

Domain-driven design, bounded contexts, and how to split (or not) a monolith.

## Bounded-context indicators

**Strong signals a real boundary exists:**

- Different teams want to evolve different parts independently
- Different release cadences (marketing pages vs. billing)
- Different scaling shapes (read-heavy search vs. write-heavy orders)
- A term means different things in different parts of the product
  ("customer" in billing vs. "customer" in support)

**Weak signals / anti-signals:**

- "This code is getting big" → that's a refactoring concern, not a split
- "We want to try a new language" → bad reason to introduce a network boundary
- "Management wants microservices" → not a design criterion

## Decomposition techniques

### 1. Bounded contexts (DDD)

Identify the ubiquitous language of each domain. Where the language diverges,
that's a context boundary.

Run an event-storming session: business events on a wall, find clusters.
Each cluster is a candidate context.

### 2. Business capabilities

Group by capability, not by technical layer:

```
✗ Wrong: UserService, OrderService, ProductService  (entity services)
✓ Right: AccountManagement, OrderFulfillment, ProductCatalog  (capabilities)
```

Entity services tend to be anemic CRUD wrappers. Capability services own
real business logic.

### 3. Strangler-fig (for monolith migration)

```
1. Put a facade/router in front of the monolith.
2. Identify one leaf-level capability (few outbound deps).
3. Build a new service with its own data store.
4. Dual-write OR migrate data carefully.
5. Route that capability's traffic through the new service.
6. Verify metrics and SLOs match or improve.
7. Decommission the old code path.
8. Repeat for the next capability.
```

Order of extraction:
1. Leaf capabilities with no downstream calls (notifications, reporting).
2. Supporting capabilities (identity, file storage).
3. Core business capabilities (orders, payments) — last.

## Right-sizing

### A right-sized service

- A "2-pizza team" (5–9 people) can own it end-to-end.
- Can be rewritten by one person in 2–4 weeks.
- Independent deploy pipeline and on-call rotation.
- 5–20 public endpoints.
- 1–5 primary tables.
- Startup time < 30 s (ideally < 10 s).

### Too small (nano-service smell)

- 1–2 endpoints, no real state.
- More YAML than business logic.
- Higher latency than value-add.
- Hard to trace because there are 40 of them.

### Too large (distributed monolith smell)

- Multiple teams fighting over the same service.
- Conflicting scale requirements forced together.
- Can't be understood in a single reading.
- Deploys coordinate with other services.

## Conway's Law alignment

Service boundaries tend to match team boundaries whether you want them to
or not. Design for the org you have, not the org you wish you had:

- **Stream-aligned team** — owns a slice end-to-end (frontend → DB).
- **Platform team** — provides self-service capability (CI/CD, observability, secrets).
- **Enabling team** — temporary coaching on new capability.
- **Complicated-subsystem team** — ML, search, payments — deep expertise with clean interface.

## Pre-decomposition readiness check

| Capability | If absent, fix before splitting |
|---|---|
| CI/CD automated | Yes — every service needs independent deploy |
| Observability (logs, metrics, traces) | Yes — debugging without it is impossible |
| Distributed tracing | Yes — correlation IDs + trace propagation |
| Container orchestration | Yes, if going container-native |
| Team experience with distributed systems | Yes — hire, coach, or contract |
| Clear ownership model | Yes — unowned services rot |

If any of these are missing, **fix them first**. Splitting without them
just distributes your existing problems.

## Decomposition steps

1. **Identify bounded contexts** — event storming; draw boundaries on the
   domain model.
2. **Define service contracts** — API spec, event schemas, SLAs, versioning
   strategy, data ownership.
3. **Plan data migration** — shared data, consistency model, synchronization
   mechanism, rollback paths.
4. **Extract** — skeleton → implement → observe → deploy → dual-write →
   switch reads → decommission old path.

## Anti-patterns

### Distributed monolith

**Symptoms:**
- Services deploy together
- Shared database
- Every call is synchronous
- Changes require version lock-step
- One failure cascades across services

**Fix:**
- Enforce database-per-service
- Move cross-aggregate writes to events
- Version APIs independently
- Add circuit breakers
- Measure: can you redeploy service X without touching Y? If no, you're still a monolith.

### Entity services

Services named after nouns (User, Order, Product) with generic CRUD. Business
logic ends up nowhere — or worse, duplicated in every caller.

**Fix:** think in capabilities. `OrderFulfillment` owns order workflow,
inventory reservation, payment orchestration — all of it. Not just `GET /orders/:id`.

### Shared libraries with domain logic

A `common-lib` that every service depends on, containing business rules.

**Result:** services redeploy in lock-step whenever `common-lib` changes.

**Fix:** shared libraries are for technical concerns only (logging, HTTP
clients, serialization). Business logic belongs to one owning service and
is accessed via API or events.

### Big-bang migration

Trying to decompose the entire monolith in a single project.

**Fix:** strangler-fig, one capability at a time, each with its own
success criteria. Measure each extraction against the monolith baseline
before moving on.

## Boundary-quality checklist

Before declaring a service boundary "done":

- [ ] Can deploy without coordination
- [ ] Owns its data completely (no shared tables)
- [ ] Can function in degraded mode if dependencies are down
- [ ] API is explicit; no "just reach into its DB"
- [ ] Events it emits have documented schemas + consumer list
- [ ] Team ownership is clear and staffed
- [ ] Runbook for common issues exists
- [ ] Metrics and alerts have owners
