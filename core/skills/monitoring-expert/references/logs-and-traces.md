# Logs and traces

## Structured logs

Every log line is JSON with consistent fields:

```json
{
  "timestamp": "2026-04-17T14:35:21.123Z",
  "level": "info",
  "service": "api",
  "version": "v1.8.4",
  "env": "prod",
  "trace_id": "4f3b8a...",
  "span_id": "ab12...",
  "user_id": "u_123",
  "request_id": "r_9877",
  "message": "user signed in",
  "http.method": "POST",
  "http.route": "/auth/signin",
  "http.status_code": 200,
  "duration_ms": 185
}
```

Rules:

- **ISO-8601 UTC** for timestamps.
- **`level` from a closed set**: `trace | debug | info | warn | error | fatal`.
- **Correlation keys first**: `trace_id`, `span_id`, `request_id`,
  `user_id` on every line.
- **Field names follow OTel semconv**: `http.method`, `db.system`,
  `messaging.destination`, etc.
- **No PII in unprotected log fields.** Emails, names, tokens →
  redact at source.

## Levels, used right

- `error` — something failed that needs human attention.
- `warn` — something unusual but recoverable.
- `info` — lifecycle events (start, stop, accepted request, completed).
- `debug` — detailed internal state, off in prod by default.
- `trace` — very detailed; turned on for a specific diagnosis.

Logs are not free. A chatty `info` log at 10k rps is ~10 GB/hour.
Plan retention and cost.

## Log sampling

For high-volume endpoints, sample:

- Always log errors.
- Sample success at 1–10% for very chatty endpoints.
- Log slow requests (> p95 threshold) unsampled.

```python
if response.status >= 400 or duration > SLOW_THRESHOLD or random() < 0.05:
    log.info("request_completed", ...)
```

## Correlation

One trace ID connects:

- Every log line on every service involved in the request.
- Every span in the trace.
- (Optional) exemplar labels on the metric histogram.

How:

- **Incoming request**: read `traceparent` (W3C) or `X-Request-Id`
  header. Accept existing IDs; generate if missing.
- **Put in context**: language's context var / thread-local / async
  context so every log call picks it up.
- **Outgoing request**: inject back into the outgoing headers so
  downstreams can continue the trace.

Logging wiring example (Python):

```python
import structlog, contextvars

trace_id_var = contextvars.ContextVar("trace_id", default=None)

def trace_processor(logger, method, event):
    if (tid := trace_id_var.get()) is not None:
        event["trace_id"] = tid
    return event

structlog.configure(processors=[trace_processor, structlog.processors.JSONRenderer()])
```

## Distributed tracing

A trace is a tree of spans. A span is one unit of work (a function
call, an outbound HTTP call, a DB query) with:

- `trace_id`, `span_id`, `parent_span_id`.
- `name` — `GET /users/:id`, `db.query`, `cache.get`.
- `start_time`, `end_time`.
- `attributes` — arbitrary key/value (high cardinality is fine here!).
- `events` — point-in-time log-like entries within the span.
- `status` — ok or error.
- `kind` — server / client / internal / producer / consumer.

## W3C trace context

Standard headers:

- `traceparent: 00-<trace-id>-<span-id>-<flags>`
- `tracestate: key1=val1, key2=val2`

All OTel SDKs emit / consume these by default. Legacy systems may
send `X-B3-*` (Zipkin) or `X-Request-Id` — configure propagators
accordingly.

## Sampling strategies

Collecting every span everywhere is expensive. Three common
strategies:

- **Head-based probabilistic** — decide at the root span (e.g., keep
  10%). Simple; deterministic propagation to child spans.
- **Head-based rate-limited** — `N spans/second/service`.
- **Tail-based** — buffer the whole trace, decide at the end based on
  its contents. Keep every trace with an error or that's slow;
  probabilistic on the rest.

Tail-based needs the OTel Collector configured in one place (can't
decide per-service). Small buffer cost, huge insight upside.

```yaml
# tail_sampling processor in the collector
processors:
  tail_sampling:
    decision_wait: 10s
    num_traces: 100000
    policies:
      - name: errors
        type: status_code
        status_code: { status_codes: [ERROR] }
      - name: slow
        type: latency
        latency: { threshold_ms: 1000 }
      - name: baseline
        type: probabilistic
        probabilistic: { sampling_percentage: 5 }
```

## Exemplars

Connect a metric bucket to an example trace:

```promql
histogram_quantile(0.99,
  sum by (le, route) (rate(http_request_duration_seconds_bucket[5m]))
)
```

In Grafana, click a p99 latency spike → pivot to an actual trace in
that bucket. Requires exemplar support in the metrics pipeline
(Prometheus + OTel has it).

## Trace as debugging tool

When something is slow:

1. Find a slow trace (TraceQL, Honeycomb "BubbleUp", Tempo trace
   explorer).
2. Read the waterfall. What's the fattest bar?
3. Read its children. Repeat.
4. Attributes on the slow span often reveal the answer (bad SQL,
   network timeout, cache miss).

This replaces "add logs, redeploy, wait" for most performance work.

## Log aggregation shapes

| Backend | Strengths | Weaknesses |
|---|---|---|
| **Loki** | Cheap, label-based, Grafana-native, designed for K8s | LogQL more limited than Elasticsearch query |
| **Elasticsearch / OpenSearch** | Full-text, rich query, mature | Expensive at scale |
| **Splunk** | Mature, many integrations | License cost |
| **Datadog / New Relic logs** | Unified with traces/metrics | Vendor lock-in, cost |
| **CloudWatch Logs** | Native AWS | Slow query, limited analysis |

Start with Loki for self-hosted; go managed when your team's time is
worth more than the bill.

## Log shipping in Kubernetes

- **Fluent Bit** as a DaemonSet reads `/var/log/pods/...` and ships to
  Loki / ES / collector.
- **Promtail** (Loki's shipper) — simpler, Loki-specific.
- **OTel Collector as a log collector** — increasingly viable;
  unified pipeline.

Avoid shipping from within apps; let the node-local agent do it.
App just writes JSON to stdout.

## What to log, what to trace, what to meter

Rule of thumb:

- **Meter** all the numbers (rates, distributions, saturation).
- **Trace** all the structure (what called what, how long each part
  took).
- **Log** the unstructured context (user action, external event,
  anomaly details).

For a production request:

- 3–10 metric updates (rate + duration histogram + status counter per
  service hop).
- 5–50 spans (one per service + DB / cache / external call).
- 0–3 log lines (a start, a business event, an error if any).

More logs ≠ better observability. Better structure + correlation >
volume.
