# PromQL and alerting

## PromQL mental model

- Every expression returns a **vector** (set of time series with one
  value each) or a **range vector** (each with a window of values).
- `rate()` / `increase()` / `histogram_quantile()` are the three
  building blocks you use daily.

## Rate and increase

For counters:

```promql
# Per-second rate over last 5m
rate(http_requests_total[5m])

# Total increase over last 1h
increase(http_requests_total[1h])
```

Rules:

- `rate` needs a counter; on a gauge it produces nonsense.
- Window should be ~4× scrape interval. 15s scrape → 1m window floor;
  use 5m for smoothness.
- `irate()` for instantaneous rate (last two samples) — volatile; use
  only for zoomed-in short-range plots.

## Aggregation

```promql
# Total QPS across all pods
sum(rate(http_requests_total[5m]))

# QPS by route
sum by (route) (rate(http_requests_total[5m]))

# QPS by route + status class
sum by (route, status_class) (rate(http_requests_total{status_class=~"[45]xx"}[5m]))
```

Grouping rule: everything after `sum by ( ... )` is what you keep;
everything else collapses.

## Error rate (the service SLI)

```promql
sum(rate(http_requests_total{status=~"5.."}[5m]))
/
sum(rate(http_requests_total[5m]))
```

Availability is `1 - error_rate`.

## Latency percentiles

```promql
histogram_quantile(0.99,
  sum by (le, route) (rate(http_request_duration_seconds_bucket[5m]))
)
```

Critical rules:

- **Keep `le` in the `by` clause** — `histogram_quantile` needs
  buckets.
- **Don't average percentiles across services** — it's mathematically
  wrong. Aggregate buckets first, then `histogram_quantile`.
- **Quantile accuracy ≤ bucket resolution.** p99 across coarse
  buckets is a rough estimate.

## Ratio / SLO queries

Good events over total events:

```promql
sum(rate(http_requests_total{status!~"5.."}[5m]))
/
sum(rate(http_requests_total[5m]))
```

SLO remainder (for burn-rate alerting):

```promql
(
  1 -
  sum(rate(http_requests_total{status!~"5.."}[5m]))
  /
  sum(rate(http_requests_total[5m]))
) /
0.001   # 99.9% → 0.1% error budget
```

Value > 1 means burning faster than the budget allows.

## Join / compare across metrics

```promql
# Nodes with high CPU AND pressure
node_cpu_seconds_total{mode="user"}
and
node_memory_pressure > 0
```

`on`, `ignoring`, `group_left`, `group_right` control how labels
merge — read [PromQL docs](https://prometheus.io/docs/prometheus/latest/querying/operators/#vector-matching)
carefully. Most alerts don't need them.

## Recording rules

Pre-compute expensive queries:

```yaml
groups:
  - name: http
    interval: 30s
    rules:
      - record: http:request_rate:rate5m
        expr: sum by (route) (rate(http_requests_total[5m]))

      - record: http:error_rate:rate5m
        expr: |
          sum by (route) (rate(http_requests_total{status=~"5.."}[5m]))
          /
          sum by (route) (rate(http_requests_total[5m]))
```

Dashboards reference the recorded series, not the raw calc. Cheaper
to render, faster on load.

Naming convention: `<level>:<metric>:<operations>`.

## Alerting rules

```yaml
groups:
  - name: api-slo
    rules:
      - alert: ApiErrorBudgetBurningFast
        expr: |
          (
            (1 - (
              sum(rate(http_requests_total{service="api",status!~"5.."}[1h]))
              /
              sum(rate(http_requests_total{service="api"}[1h]))
            )) / 0.001
          ) > 14.4
          and
          (
            (1 - (
              sum(rate(http_requests_total{service="api",status!~"5.."}[5m]))
              /
              sum(rate(http_requests_total{service="api"}[5m]))
            )) / 0.001
          ) > 14.4
        for: 2m
        labels:
          severity: page
          service: api
        annotations:
          summary: "API error budget burning at {{ $value | printf \"%.1f\" }}× normal"
          runbook: "https://runbooks.example.com/api-error-budget"
          dashboard: "https://grafana.example.com/d/api-slo"
```

Rules:

- **Both windows** must fire (`and`) — long-window noise reduction +
  short-window confirmation.
- **`for:`** duration should match the short window; avoids blips.
- **`severity` label** drives Alertmanager routing.
- **Annotations always include runbook + dashboard URLs.**

## Multi-window, multi-burn-rate bundle

Four alerts, different severity:

```yaml
- alert: SLOBurn1h
  # 14.4x burn-rate, long=1h, short=5m
  severity: page
- alert: SLOBurn6h
  # 6x burn-rate, long=6h, short=30m
  severity: page
- alert: SLOBurn1d
  # 3x, long=1d, short=2h
  severity: ticket
- alert: SLOBurn3d
  # 1x, long=3d, short=6h
  severity: ticket
```

See `sre-engineer/references/slos-and-error-budgets.md` for the
derivation.

## Alertmanager routing

```yaml
route:
  receiver: default
  group_by: [alertname, service]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  routes:
    - matchers: [severity="page"]
      receiver: pagerduty
      continue: true
    - matchers: [severity="ticket"]
      receiver: email-tickets
    - matchers: [service="auth", severity="page"]
      receiver: pagerduty-auth

receivers:
  - name: pagerduty
    pagerduty_configs:
      - service_key_file: /etc/alertmanager/pd-key
  - name: pagerduty-auth
    pagerduty_configs:
      - service_key_file: /etc/alertmanager/pd-auth-key
  - name: email-tickets
    email_configs:
      - to: oncall-tickets@example.com
```

Rules:

- **Group alerts** so one outage doesn't page you 50 times.
- **Silence** during planned maintenance via the Alertmanager UI /
  API.
- **Inhibition** (`inhibit_rules`) — suppress dependent alerts when
  the root alert is firing (e.g., "DB down" suppresses "every
  service returning 5xx").

## PromQL anti-patterns

- `rate(... [1m])` — too short; cardinality of rate spikes.
- `histogram_quantile` without `le` in the aggregation — returns
  wrong numbers silently.
- Using `sum` on a gauge that shouldn't be summed (e.g., `sum(memory_free)` makes no sense across nodes).
- Alerts with no `for:` duration — any blip fires.
- Alert expressions repeated in multiple files — refactor to a
  recording rule.

## Debugging queries

- Start narrow (single label set), add aggregations incrementally.
- In Grafana, use "Explore" with table view to see each time series
  individually.
- If results are empty, check label names/values — `__name__` and
  label typos are the #1 bug.
- `count({...})` to check series count — helps spot cardinality issues.
