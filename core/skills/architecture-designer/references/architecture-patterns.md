---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/architecture-designer/references/architecture-patterns.md
ported-at: 2026-04-17
adapted: true
---

# Architecture patterns

Pick the simplest pattern that meets the NFRs. Every step up the complexity
ladder costs operational maturity you may not have.

## Quick comparison

| Pattern | Best for | Team size | Main trade-off |
|---|---|---|---|
| Monolith | Simple domain, early product | 1–10 | Easy to build, hard to scale parts independently |
| Modular monolith | Growing complexity with clear domains | 5–30 | Good middle ground; requires module discipline |
| Microservices | Complex domain, multiple autonomous teams | 20+ | Independent scale + deploy; operational complexity |
| Serverless | Variable/unpredictable load, event-driven | Any | Auto-scale; cold starts, vendor lock-in |
| Event-driven | Async workflows, decoupled consumers | 10+ | Loose coupling; eventual consistency, harder debugging |
| CQRS | Read-heavy with different read/write shapes | 10+ | Specialized read models; two code paths to maintain |

## Monolith

```
┌─────────────────────────────────────┐
│            Application               │
│  ┌─────┐  ┌──────┐  ┌────────┐     │
│  │Users│  │Orders│  │Products│     │
│  └──┬──┘  └──┬───┘  └────┬───┘     │
│     └────────┼────────────┘         │
│              │                      │
│         ┌────▼────┐                 │
│         │Database │                 │
│         └─────────┘                 │
└─────────────────────────────────────┘
```

**Use when:** starting out, small team, unclear domain boundaries, rapid iteration.

**Pros:** one deploy, local calls, simple debugging, easy transactions.
**Cons:** scaling forces the whole app to scale, deploy risk, technology lock-in.

## Modular monolith

Like a monolith but with hard module boundaries — each module owns its data,
exposes an API, and cannot reach into another module's internals. Think of it
as microservices in-process.

**Use when:** you have ≥2 identifiable bounded contexts but aren't ready for
distributed-systems operational cost. This is the *right* default for most teams.

**Pros:** clean boundaries without the network, easy to extract to services
later if needed.
**Cons:** requires discipline — one shortcut across a boundary corrupts the
model.

## Microservices

```
┌──────────┐  ┌──────────┐  ┌──────────┐
│  Users   │  │  Orders  │  │ Products │
│ Service  │  │ Service  │  │ Service  │
└────┬─────┘  └────┬─────┘  └────┬─────┘
     │             │              │
┌────▼────┐   ┌────▼────┐    ┌────▼────┐
│ User DB │   │Order DB │    │ Prod DB │
└─────────┘   └─────────┘    └─────────┘
```

**Use when:** you have multiple autonomous teams, distinct scaling needs per
capability, and operational maturity (observability, CI/CD, on-call).

**Pros:** independent deploys, polyglot tech, team autonomy, fault isolation.
**Cons:** network is unreliable, distributed transactions are hard, ops burden
is real. See `core/skills/microservices-architect/`.

## Serverless

```
┌─────────┐   ┌─────────┐
│ Request │──▶│ Function│──▶ Result
└─────────┘   └────┬────┘
                   │
              ┌────▼────┐
              │ Backend │
              │ (DB/MQ) │
              └─────────┘
```

**Use when:** workload is event-driven, load is spiky, or infra should scale to
zero.

**Pros:** no server ops, scales to zero, pay per request.
**Cons:** cold-start latency, vendor lock-in, hard to run locally, limits on
execution time and memory.

## Event-driven

```
┌──────────┐    ┌────────────┐    ┌──────────┐
│ Producer │───▶│ Message Bus│───▶│ Consumer │
└──────────┘    │  (Kafka…)  │    └──────────┘
                └─────┬──────┘
                      │
                      └─▶┌──────────┐
                         │ Consumer │
                         └──────────┘
```

**Use when:** producers and consumers evolve independently, async is acceptable,
you need a durable log or fan-out.

**Pros:** loose coupling, elastic consumption, natural audit trail.
**Cons:** eventual consistency, harder to reason about end-to-end flows,
message ordering and delivery guarantees must be designed in.

## CQRS (Command Query Responsibility Segregation)

```
┌─────────┐        ┌─────────────┐
│ Commands│───────▶│ Write model │───┐
└─────────┘        └─────────────┘   │
                                     ▼
                               ┌──────────┐
                               │  Events  │
                               └────┬─────┘
                                    │
┌─────────┐        ┌─────────────┐  │
│ Queries │◀───────│ Read model  │◀─┘
└─────────┘        └─────────────┘
```

**Use when:** read and write loads have very different shapes, or the read
model needs to be denormalized for performance.

**Pros:** each side optimized independently, enables event sourcing.
**Cons:** two code paths, eventual consistency between write and read,
operational overhead.

## Quick chooser

| Requirement | Default pattern |
|---|---|
| New product, small team | Monolith |
| Growing startup, multiple domains | Modular monolith |
| Large org with autonomous teams | Microservices |
| Unpredictable event-driven load | Serverless |
| Async workflows, multiple consumers | Event-driven |
| 100× read vs. write, specialized views | CQRS |

## Anti-patterns

- **Microservices without observability.** You will not be able to debug it.
- **Distributed monolith** — services that must deploy together or share a DB.
  Worst of both worlds.
- **Event-driven without schema discipline** — event contracts rot fast,
  consumers break silently.
- **CQRS on a simple CRUD app** — the complexity buys you nothing.
- **Serverless for steady high-load workloads** — you pay a premium and get
  cold-start surprises.
