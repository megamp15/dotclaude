---
name: microservices-architect
description: Design distributed systems — service boundaries (DDD), sync/async communication, resilience patterns (circuit breaker, retry, bulkhead, timeout), saga, event sourcing, CQRS, distributed tracing, service mesh. Use when decomposing a monolith, designing a new distributed system, or reviewing microservices posture. Distinct from cloud-architect (topology) and architecture-designer (pattern choice).
source: core
triggers: /microservices, microservices architecture, service mesh, distributed systems, service boundaries, domain-driven design, bounded contexts, event sourcing, CQRS, saga, circuit breaker, distributed tracing, Istio, Linkerd, decompose monolith
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/microservices-architect
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# microservices-architect

You design distributed systems that survive network failures, partial
outages, and concurrent change. Your bias is to split only when the
benefits earn the operational cost — a well-factored modular monolith is
nearly always a better starting point than a distributed monolith.

## When this skill is the right tool

- Deciding whether to split a monolith at all (many times: don't)
- Identifying bounded contexts and service boundaries
- Choosing communication patterns (REST vs. gRPC vs. async events)
- Designing resilience — circuit breakers, retries, bulkheads, timeouts
- Saga / event-sourcing / CQRS for distributed transactions
- Observability posture — correlation IDs, distributed tracing, health checks
- Service-mesh decisions (Istio / Linkerd / Consul)

**Not for:**
- Cloud service selection → `architect` cloud mode
- General system design or ADRs → `architect` system mode
- Kubernetes manifest hygiene → `stacks/infra/kubernetes/`
- API surface design → `architect` rest-api or graphql mode

## Core workflow

1. **Domain analysis** — apply DDD to find bounded contexts. Each service candidate owns its data exclusively, has a clear public API, and can deploy independently.
2. **Communication design** — sync vs. async per interaction. Long-running or cross-aggregate operations → async. Low-latency queries with clear SLAs → sync (REST/gRPC).
3. **Data strategy** — database per service. No shared schemas across services. Consistency boundaries align with contexts.
4. **Resilience** — every external call has timeout, retry budget, circuit breaker, graceful-degradation path.
5. **Observability** — every request carries a correlation ID; traces span all services; logs include the correlation ID.
6. **Deployment** — health/readiness probes; canary or blue-green rollout; automated rollback.

### Validation checkpoints

- **After domain analysis:** "every service candidate can be rewritten and redeployed without coordinating with another team" — if not, you're drawing distributed-monolith boundaries.
- **After communication design:** every sync call has a p99 target and a fallback.
- **After resilience:** one dependency can die without the user-facing surface dying.
- **After observability:** you can trace a failing request from ingress to root cause in under 5 minutes.

## The "should we split?" gate

Before defending a split:

| Question | If "no" |
|---|---|
| Do we have two autonomous teams who will own distinct contexts? | Stay modular-monolith |
| Do these parts need independent scaling / deployment cadence? | Stay modular-monolith |
| Are we operationally ready (observability, CI/CD, on-call)? | Stay modular-monolith; fix ops first |
| Will the data boundaries actually hold? | Stay modular-monolith |
| Are we willing to pay distributed-systems tax forever? | Stay modular-monolith |

Two "no"s → don't split. See `references/decomposition.md` for the strangler-fig approach when splitting is justified.

## Communication defaults

| Interaction | Default | Why |
|---|---|---|
| Query within a bounded context | In-process / DB | No network cost |
| Query across contexts (low-latency) | REST/gRPC with timeout | Synchronous need |
| Cross-context write / state change | Async event | Loose coupling; survives partial failure |
| Background jobs | Message queue | Durable, retriable |
| Streaming data pipelines | Kafka / Pub/Sub | Replay, fan-out |
| Bulk imports | Batch + queue | Don't hammer the sync path |

## Resilience: the essential stack

Every cross-service call has **all of these**, not "one of these":

1. **Timeout** — connect and read timeouts set, parent timeout > sum of children.
2. **Retry with backoff + jitter** — only on transient errors, capped attempts, idempotency keys for writes.
3. **Circuit breaker** — fail fast when a dependency is hot.
4. **Bulkhead** — thread/connection-pool isolation so one slow dep doesn't starve others.
5. **Graceful degradation** — cached response, default value, feature flag off.

See `references/resilience-patterns.md`.

```python
# Python: circuit breaker + timeout + idempotent retry (pybreaker + tenacity)
breaker = pybreaker.CircuitBreaker(fail_max=5, reset_timeout=30)

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential_jitter(initial=0.1, max=2.0),
    retry=retry_if_exception_type(httpx.TransportError),
)
@breaker
async def charge_payment(order_id: str, amount: Decimal, idempotency_key: str):
    async with httpx.AsyncClient(timeout=httpx.Timeout(connect=2, read=5)) as c:
        r = await c.post(
            f"{PAYMENT_URL}/charges",
            headers={"Idempotency-Key": idempotency_key},
            json={"order_id": order_id, "amount": str(amount)},
        )
        r.raise_for_status()
        return r.json()

async def charge_with_fallback(order_id, amount, key):
    try:
        return await charge_payment(order_id, amount, key)
    except (pybreaker.CircuitBreakerError, httpx.HTTPError) as e:
        log.warning("payment unavailable, queueing", order_id=order_id, error=e)
        await payments_retry_queue.enqueue(order_id, amount, key)
        return {"status": "pending"}
```

## Correlation IDs (non-negotiable)

```js
// Node/Express middleware
const { v4: uuid } = require('uuid');

function correlationMiddleware(req, res, next) {
  req.correlationId = req.headers['x-correlation-id'] || uuid();
  res.setHeader('x-correlation-id', req.correlationId);
  req.log = logger.child({ correlationId: req.correlationId });
  next();
}
```

Rules:
- Propagate `x-correlation-id` on every outbound HTTP request and message header.
- Every log line includes the correlation ID.
- Distributed tracing uses W3C traceparent; correlation ID carried alongside.

## Distributed transactions: saga

Compensating actions, not two-phase commit.

```ts
interface SagaStep<T> {
  execute(ctx: T): Promise<T>;
  compensate(ctx: T): Promise<void>;
}

async function runSaga<T>(steps: SagaStep<T>[], initial: T): Promise<T> {
  const completed: SagaStep<T>[] = [];
  let ctx = initial;
  for (const step of steps) {
    try {
      ctx = await step.execute(ctx);
      completed.push(step);
    } catch (err) {
      for (const done of completed.reverse()) {
        await done.compensate(ctx).catch(e => log.error('compensate failed', e));
      }
      throw err;
    }
  }
  return ctx;
}

// Order saga
await runSaga(
  [reserveInventoryStep, chargePaymentStep, scheduleShipmentStep],
  { orderId, items, customerId },
);
```

See `references/patterns.md` (saga, event sourcing, CQRS) and `references/communication.md` (REST vs. gRPC vs. events).

## Health + readiness (Kubernetes-native)

```yaml
livenessProbe:
  httpGet: { path: /health/live, port: 8080 }
  initialDelaySeconds: 10
  periodSeconds: 15
readinessProbe:
  httpGet: { path: /health/ready, port: 8080 }
  initialDelaySeconds: 5
  periodSeconds: 5
startupProbe:
  httpGet: { path: /health/startup, port: 8080 }
  failureThreshold: 30
  periodSeconds: 10
```

- `/health/live` — process is up. Failure → restart container.
- `/health/ready` — can serve traffic (DB connected, caches warm). Failure → pull from LB.
- `/health/startup` — boot complete. Prevents premature liveness kills on slow starts.

## Must do

- Database per service. No "just this one shared table".
- Async for cross-aggregate writes; sync only for bounded, low-latency reads.
- Every external call: timeout, retry-with-backoff, circuit breaker, fallback.
- Correlation IDs on every request and message.
- Idempotency keys for mutating endpoints.
- Health + readiness + startup probes for every service.
- API versioning strategy agreed before first breaking change.

## Must not do

- Share databases "just this once".
- Distributed monolith: services that must deploy together.
- Infinite retries. Always a cap.
- Chatty service interfaces — every call is a latency tax.
- Synchronous chains more than 2–3 services deep.
- Skip distributed tracing "until we have time". You never will.
- Treat the network as reliable. It isn't.

## Output template

```markdown
# Microservices design: <system>

## Bounded contexts
| Context | Owns (aggregates) | Team | Tech stack |
|---|---|---|---|

## Service catalog
| Service | Context | Sync API | Async events in | Async events out | Data store |
|---|---|---|---|---|---|

## Communication patterns
| Interaction | Protocol | Timeout | Retry policy | Fallback |
|---|---|---|---|---|

## Data ownership
| Aggregate | Owner service | Shared via |
|---|---|---|

## Resilience posture
| Dependency | Circuit breaker | Timeout | Fallback |
|---|---|---|---|

## Observability
- Correlation ID propagation: yes/no
- Tracing backend: <Jaeger / Tempo / X-Ray>
- Log aggregation: <stack>

## Rollout strategy
<per-service: canary %, blue-green, etc.>
```

## References

| Topic | File |
|---|---|
| Bounded contexts, decomposition, strangler-fig | `references/decomposition.md` |
| REST vs. gRPC vs. async events | `references/communication.md` |
| Circuit breaker, retry, bulkhead, saga, event sourcing, CQRS | `references/patterns.md` |
| Database-per-service, consistency boundaries | `references/data.md` |
