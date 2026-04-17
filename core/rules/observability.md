---
name: observability
description: Universal logging, metrics, and tracing. What to emit, what not to, and why.
source: core
alwaysApply: true
---

# Observability

Code you can't observe in production is code you can't debug in production.
These rules are language- and platform-agnostic.

## Logging

### Levels — use them correctly

- **ERROR** — something failed that requires human attention. An exception that wasn't handled, a dependency that's down, data corruption. ERROR = page me (or at least, someone will read this tomorrow). Don't use ERROR for expected failures (bad user input, 404s).
- **WARN** — something unexpected but recoverable. Retry succeeded on second attempt, deprecated path hit, degraded mode entered. Investigate in aggregate, not per-occurrence.
- **INFO** — significant business events. User signed up, job started, migration applied, service boot. Should read like a summary of what the system did.
- **DEBUG** — internal state useful during investigation. Off in production by default; flippable per-request, per-user, or per-component.
- **TRACE** — wire-level detail. Usually off. Most teams don't need this level.

A common mistake: everything is INFO. Then INFO is noise and nobody notices real events.

### What to log

- **One log line per meaningful event**, not per line of code.
- At boundaries: request received, request complete (with status + duration), external call started, external call returned.
- On errors: the error, its cause chain, and the inputs that triggered it (redacted).
- On state transitions that matter: job queued → running → complete → failed.

### What NOT to log

- **Secrets** — tokens, passwords, API keys, signed URLs with bearer tokens embedded. Ever.
- **PII without a reason** — emails, phone numbers, addresses. If you need them for debugging, hash or tokenize.
- **Full payloads** by default. Log IDs and sizes; log bodies only when triaging and only with PII redaction.
- **Noise in tight loops** — `log.debug("processing row")` inside a loop over a million rows destroys your log budget and signal.
- **Same error at multiple layers.** Log once, at the boundary that handled it.

### Structured logs

- **JSON or key-value**, not prose. `user_id=42 action=login result=success duration_ms=134` beats `"User 42 logged in successfully in 134ms"` every time for searching.
- **Stable field names** across services. `user_id` everywhere, not `userId` here and `uid` there.
- **Include a correlation id / trace id** on every log line that's part of a request.

## Metrics

### The four you almost always want

- **Rate** — requests/second, events/second.
- **Errors** — count of failures, broken out by type or code.
- **Duration** — latency distribution (p50/p95/p99, not average).
- **Saturation** — how full is the thing (queue depth, connection pool used, disk %, memory %).

"RED" (Rate, Errors, Duration) for request-driven services. "USE" (Utilization, Saturation, Errors) for resource-driven systems. Know which fits.

### What to measure

- **Business events**, not just technical ones. Signups, checkouts, failed payments — these are what a non-engineer needs to see first when something's wrong.
- **External dependencies** separately from your own work. If the DB is slow, you want to know it's the DB, not your handler.
- **Queue depth and age** for anything async. A queue growing faster than it drains is a slow-motion outage.

### Cardinality discipline

- **Never** use unbounded-cardinality fields as metric labels: user_id, request_id, full URL paths with variables, free-text.
- Route patterns, not actual paths (`/users/:id`, not `/users/42`).
- Error classes, not error messages.
- High-cardinality belongs in logs and traces, not metrics. Violating this blows up the metrics backend bill.

## Tracing

- **One trace per request/job.** Includes every external call and every async hop.
- **Propagate the trace id** — through HTTP headers, queue messages, scheduled job context. A trace broken in the middle is barely useful.
- **Span every external call** (DB, HTTP, cache, queue). Include target, operation, status.
- **Attributes, not messages.** `db.statement`, `http.status_code`, `queue.name` — stable attributes enable cross-request analysis.

## Health and readiness

- **Health** — is this process alive? Liveness probe. Fails → restart.
- **Readiness** — can this process serve traffic? Dependencies reachable, caches warmed, migrations applied. Fails → remove from load balancer, don't restart.
- Don't collapse the two. A DB blip should pull you from rotation, not kill every pod.

## Alerts

- **Alert on symptoms, not causes.** "p95 latency > 1s for 5min" matters; "CPU at 80%" rarely does.
- **Every alert has a runbook.** If you don't know what to do when it fires, it shouldn't page.
- **If an alert never fires, delete it.** If it fires constantly, fix or tune it. Noisy alerts train people to ignore real ones.

## Cost discipline

Observability bills can exceed compute bills. Budget per-service. Sample traces. Sample debug logs. Drop metrics with dead cardinality. Audit quarterly.
