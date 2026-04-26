---
name: monitoring-expert
description: Observability plumbing — metrics (Prometheus, OpenTelemetry), logs (Loki, Elasticsearch), traces (Tempo, Jaeger, Honeycomb), dashboards (Grafana), alerting (PromQL, Alertmanager, PagerDuty), and correlation via trace/request IDs. Distinct from `sre-engineer` (SLO policy, incident response) and `core/rules/observability.md` (baseline conventions).
source: core
triggers: /monitoring, observability, OpenTelemetry, OTel, prometheus, grafana, loki, tempo, jaeger, honeycomb, datadog, alertmanager, PromQL, logQL, trace id, span, cardinality explosion, golden signals, RED method, USE method
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/monitoring-expert
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# monitoring-expert

Deep expertise on the telemetry side of reliability — the plumbing the
SRE skill consumes. Activates when the question is about instrumentation,
metric design, trace context, log shape, dashboards, or alert queries.

> **See also:**
>
> - `core/rules/observability.md` — baseline conventions
> - `core/skills/sre-engineer/` — SLOs, incidents, policy
> - `core/skills/debugging/` — tactical debugging using observability
> - `stacks/infra/kubernetes/skills/kubernetes-specialist/` — K8s-native
>   observability (Prom operator, OTel collector deployment)

## When to use this skill

- Designing what metrics a new service should expose.
- Choosing between metric, log, and trace for a given signal.
- Writing a PromQL / LogQL / TraceQL query that actually works.
- Avoiding cardinality explosions that kill Prometheus.
- Wiring OpenTelemetry end-to-end (SDK → collector → backend).
- Making dashboards that answer "is it healthy?" in < 30 seconds.
- Picking a vendor stack (OSS vs. Datadog vs. Honeycomb vs. New Relic).

## References (load on demand)

- [`references/metrics.md`](references/metrics.md) — metric types
  (counter / gauge / histogram / summary), naming conventions
  (OTel semconv), RED / USE methods, label design, cardinality
  discipline, Prometheus / OTLP specifics.
- [`references/logs-and-traces.md`](references/logs-and-traces.md) —
  structured logs, correlation IDs, sampling, trace context
  propagation (W3C), OTel collectors, tail-based sampling,
  high-cardinality trace analysis.
- [`references/promql-and-alerts.md`](references/promql-and-alerts.md)
  — PromQL reading guide (`rate`, `sum by`, `histogram_quantile`,
  subqueries), recording rules, alerting rules, burn-rate alert
  patterns, Alertmanager routing.

## Core workflow

1. **Pick the signal type deliberately.**
   - **Metrics** — aggregate trends at scale. Cheap, low resolution.
   - **Logs** — detailed per-event record. High volume, high cost at
     scale.
   - **Traces** — causal relationship between spans across services.
     Sample them.
2. **Instrument once, correlate everywhere.** Same request/trace ID
   stamped on every log, metric exemplar, and span.
3. **Keep cardinality sane.** Low-cardinality labels on metrics (method,
   status); high-cardinality fields belong on logs/traces.
4. **Design the alert first**, then the metric. If you can't write the
   query, the metric shape is wrong.
5. **OTel is the portability story.** Instrument with OpenTelemetry so
   you can swap backends without re-instrumenting.

## Defaults

| Question | Default |
|---|---|
| Instrumentation SDK | OpenTelemetry (OTel) |
| Metrics backend | Prometheus (pull) + OTLP receiver for OTel-native apps |
| Logs backend | Loki for OSS / Grafana stack; Elasticsearch if already in house |
| Trace backend | Tempo (OSS) or Honeycomb (managed) |
| Dashboards | Grafana |
| Alerting | Alertmanager → PagerDuty / Opsgenie |
| Collector | OTel Collector (contrib), deployed as DaemonSet + Deployment |
| Sampling strategy | Head-based 100% in dev, tail-based production (keep errors + slow) |
| Log format | JSON with ISO-8601 timestamps in UTC |
| Log level (prod) | `info`; `debug` behind a feature flag |

## Anti-patterns

- **Raw threshold alerts on machine metrics.** "CPU > 80%" doesn't map
  to user pain. Alert on SLOs.
- **High-cardinality metric labels.** `user_id`, `request_id`, `trace_id`
  as Prometheus labels kills the TSDB. Use them in logs/traces.
- **Un-sampled traces at scale.** 100% sampling in prod = observability
  system becomes your biggest infra cost.
- **Unstructured log text.** `log.info("user %s did %s", name, action)`
  is not queryable. Structured fields.
- **Mixing measurement systems.** App uses StatsD, K8s uses Prometheus,
  cloud uses CloudWatch, traces go to Jaeger — no one can answer a
  question that spans them.
- **Metrics named after implementation.** `pg_connection_pool_size`
  instead of `http_request_duration_seconds`. Name by observable
  behavior.
- **Dashboards that require tribal knowledge.** A new on-call should
  answer "is it healthy?" in 30s from the main dashboard.

## Output format

For instrumentation:

```
Signal type:     metric | log | trace
Name:            <conventional name>
Labels / tags:   <low-cardinality>
Example query:   <PromQL / LogQL / trace filter>
Dashboards:      <panel name>
Alert (if any):  <the condition>
```

For dashboard / alert design:

```
Panel:    <what it shows>
Question: <"is X healthy?" — which question the panel answers>
Query:    <PromQL / LogQL>
Threshold (if any): <line / color>
Drill-down: <where to click through>
```
