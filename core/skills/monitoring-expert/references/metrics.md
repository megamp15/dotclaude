# Metrics design

## Metric types

| Type | Example | Use |
|---|---|---|
| **Counter** | `http_requests_total` | Monotonically increasing; rate via `rate()` |
| **Gauge** | `queue_depth`, `memory_bytes` | Current value; can go up and down |
| **Histogram** | `http_request_duration_seconds` | Time/size distributions; quantiles via `histogram_quantile()` |
| **Summary** | Deprecated in favor of histograms | Pre-calculated quantiles at source |

Default to histogram for latency. Summaries don't aggregate across
replicas.

## RED method (for services)

- **Rate** — requests per second.
- **Errors** — rate of failed requests.
- **Duration** — latency distribution (histogram).

Three metrics cover 80% of service-level monitoring:

```
http_requests_total{method, route, status}
http_request_duration_seconds_bucket{method, route, status, le}
http_request_duration_seconds_count
http_request_duration_seconds_sum
```

## USE method (for resources)

- **Utilization** — percent busy.
- **Saturation** — queue depth, waiting.
- **Errors** — error count.

For nodes, disks, queues, thread pools — anything with capacity.

## Four golden signals (SRE book)

- **Latency** — duration histograms.
- **Traffic** — request rate.
- **Errors** — error rate.
- **Saturation** — resource exhaustion.

Same idea as RED/USE, slightly different framing.

## Naming

Follow [OpenTelemetry semantic conventions](https://opentelemetry.io/docs/specs/semconv/):

- Snake-case.
- Name describes the observable, not the implementation.
- Unit in the name: `_seconds`, `_bytes`, `_total` (for counters).
- Namespace: `<domain>_<subject>_<measurement>_<unit>`.

Examples:

- `http_server_request_duration_seconds` (histogram)
- `http_server_active_requests` (gauge)
- `http_client_request_duration_seconds`
- `db_client_operation_duration_seconds`
- `messaging_publish_duration_seconds`

## Labels / attributes

Metrics have labels; traces have attributes; logs have fields. Same
rule everywhere: **low cardinality on metrics, high cardinality on
traces/logs**.

### Good metric labels (low cardinality)

- `method` (GET, POST, …) — < 10 values.
- `route` (`/users/:id`) — template, not literal; < 100 values.
- `status_code` or `status_class` (2xx/3xx/4xx/5xx) — small set.
- `service`, `deployment`, `region` — environment-level.

### Bad metric labels (high cardinality)

- `user_id`, `request_id`, `trace_id` — unbounded.
- Full URL with query string.
- User-supplied free text.

Cardinality = product of unique values across all labels. 5 routes × 4
methods × 5 status classes × 3 services = 300 time series. That's
fine. Add `user_id` (10k users) and you've got 3M — and Prometheus is
dying.

### Cardinality triage

```promql
# How many series per metric
topk(10, count by (__name__)({__name__=~".+"}))

# High-cardinality labels
topk(10, count by (label_name)(metric_name))
```

## Histogram design

Bucket boundaries matter. Defaults (`[.005, .01, ..., 10]`) are too
coarse for fast services, too fine for slow ones.

For a service expecting 10ms — 2s responses:

```
[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
```

Rules:

- Include the `+Inf` bucket (Prometheus adds automatically).
- Quantile accuracy is best near bucket boundaries; know what
  percentiles you need.
- Too many buckets = cardinality explosion (buckets × labels).

Newer: **exponential (sparse) histograms** (OTel / Prometheus native
histograms) auto-scale. If your stack supports them, use them.

## Counters, not rates at source

Expose `requests_total` as a counter. Let PromQL compute the rate:

```
rate(http_requests_total[5m])
```

Don't expose `requests_per_second` as a gauge — you lose monotonicity
guarantees, and downsampling / restarts produce bad data.

## Process / runtime metrics

Most SDKs expose them automatically; make sure they're on:

- Go: `go_gc_duration_seconds`, `go_goroutines`, `go_memstats_*`.
- Python: `process_resident_memory_bytes`, `process_cpu_seconds_total`.
- Node: `nodejs_eventloop_lag_seconds`, `nodejs_heap_size_used_bytes`.
- JVM: `jvm_memory_used_bytes`, `jvm_gc_pause_seconds`.

These are your "is the process healthy" signal. Put them on every
service dashboard.

## OpenTelemetry basics

```python
# Python example
from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader

reader = PeriodicExportingMetricReader(OTLPMetricExporter(endpoint="http://collector:4317"))
metrics.set_meter_provider(MeterProvider(metric_readers=[reader]))

meter = metrics.get_meter("myapp")
request_counter = meter.create_counter(
    "http.server.request.count",
    description="Total HTTP requests",
    unit="1",
)
request_counter.add(1, {"http.method": "GET", "http.route": "/users/:id"})
```

## The OTel Collector

Deploy the collector as a sidecar / DaemonSet / Deployment that:

1. Receives OTLP from apps.
2. Processes (batch, filter, sample, attribute enrichment).
3. Exports to one or more backends (Prometheus, Tempo, Loki,
   vendor-specific).

Pipelines typically look like:

```yaml
receivers:
  otlp:
    protocols:
      grpc: { endpoint: 0.0.0.0:4317 }
      http: { endpoint: 0.0.0.0:4318 }

processors:
  batch: {}
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80

exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"
  otlphttp/tempo:
    endpoint: "http://tempo:4318"
  loki:
    endpoint: "http://loki:3100/loki/api/v1/push"

service:
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [prometheus]
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlphttp/tempo]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [loki]
```

## Pull (Prometheus) vs. push (OTLP)

- **Prometheus-native**: app exposes `/metrics`; Prometheus scrapes.
- **OTel-native**: app pushes OTLP to collector; collector exposes to
  Prometheus or pushes to the backend.

Prefer OTel SDK + collector in Prometheus-scrape mode for the best of
both worlds: vendor-agnostic instrumentation, Prometheus's
pull-based reliability.

## Dashboards

A service dashboard answers "is it healthy?" in 30 seconds. Rows,
top to bottom:

1. **SLOs at a glance** — each SLO's budget remaining, burn rate.
2. **RED** — request rate, error rate, p50/p95/p99 latency.
3. **Dependencies** — DB, cache, upstream services.
4. **Resources** — CPU, memory, goroutines/threads, queue depth.
5. **Deploys & changes** — annotations from CI for correlation.

Link from each alert to the dashboard. Link from each dashboard panel
to the log/trace query that drills into it.
