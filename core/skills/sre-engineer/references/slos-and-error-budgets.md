# SLIs, SLOs, error budgets

## The four golden signals

Every service should measure:

1. **Latency** — time to serve a successful request.
2. **Traffic** — requests per second (or equivalent work rate).
3. **Errors** — rate of failed requests.
4. **Saturation** — how full the service is (queue depth, connection
   pool, memory pressure).

These are the floor. SLIs build on top.

## SLI — Service Level Indicator

An SLI is a **ratio** of good events to total events over a window:

```
SLI = good_events / total_events
```

Examples:

- **Availability**: `successful_requests / total_requests`.
- **Latency**: `requests_under_200ms / total_requests`.
- **Freshness**: `rows_under_5min_stale / total_rows`.
- **Correctness**: `checksum_matches / total_verifications`.

The winning pattern: **journey-based SLIs.** Don't measure the API layer
— measure the user journey.

- "User successfully signs in within 2 seconds" — one SLI covers auth
  service, rate limiting, DB, cache, DNS, CDN.
- "Order placed and confirmed within 10 seconds" — one SLI covers the
  whole checkout pipeline.

A journey SLI fails when **any** component on the path fails, which is
exactly what the user cares about.

## SLO — Service Level Objective

An SLO is the **target SLI over a rolling window**:

```
99.9% of auth requests in any rolling 28-day window complete within 2 seconds
```

Components:

- **SLI**: what ratio you're measuring.
- **Target**: the percentage you commit to.
- **Window**: typically 28 days (rolling). 30 days works too; 28 divides
  evenly into weeks.

## Picking a target

| Target | Allowed downtime / month | When |
|---|---|---|
| 99% | 7.2 h | Internal tools, best effort |
| 99.5% | 3.6 h | Non-critical internal |
| 99.9% | 43.8 min | Standard customer-facing |
| 99.95% | 21.9 min | Important / paid customer-facing |
| 99.99% | 4.38 min | Financial, life-critical (very expensive) |
| 99.999% | 26.3 sec | Regulatory / telecom; realistically unachievable for most |

**Don't pick 100%.** It has four problems: unachievable, pins you from
making any change, makes the error budget zero (no headroom for
experiments), and there's always a dependency below you (DNS, TLS, the
internet) that's less reliable.

Typical sequence:

1. Measure current performance over 28 days.
2. Round down to the nearest 9. That's your initial SLO.
3. Run it for a quarter. Tighten if you have surplus; relax if the
   budget is always red.

## Error budget

If SLO is 99.9%, error budget is **0.1% of events**.

```
budget = (1 - slo) * total_events
```

- **Budget remaining**: treat as a resource.
- **Green** (>50% budget): ship fast, experiment, chaos-test.
- **Yellow** (10–50%): normal caution.
- **Red** (<10%): change freeze, dedicate cycles to reliability.

This is the mechanism: the SLO is how "reliable enough" gets quantified,
and the budget is how that decision drives engineering priorities.

## Burn-rate alerts

Alerting on "SLI below 99.9% for 5 minutes" is too tight for small
services (normal noise) and too loose for big ones (you burn the whole
budget in 5 min).

**Multi-window burn rate**: alert when the current burn rate would
exhaust the budget in less than some fraction of the SLO window.

Google SRE's recommendation:

| Burn rate | Long window | Short window | Budget consumed if alert triggers | Severity |
|---|---|---|---|---|
| 14.4 | 1h | 5m | 2% in 1h | Page |
| 6 | 6h | 30m | 5% in 6h | Page |
| 3 | 1d | 2h | 10% in 1d | Ticket |
| 1 | 3d | 6h | 10% in 3d | Ticket |

Two windows: the **long window** makes the alert stable; the **short
window** ensures you don't wait hours to confirm a real issue.

Prometheus example:

```promql
# 1h burn rate for a 99.9% SLO (multiply 1h-error-rate by 1000 = budget-fraction/h)
(
  sum(rate(http_requests_total{status=~"5.."}[1h]))
  /
  sum(rate(http_requests_total[1h]))
) > 14.4 * (1 - 0.999)
AND
(
  sum(rate(http_requests_total{status=~"5.."}[5m]))
  /
  sum(rate(http_requests_total[5m]))
) > 14.4 * (1 - 0.999)
```

Combine the two conditions so a brief blip doesn't page, but a
sustained burn does.

## Error budget policy

Write it down, agree it as a team, post it visibly.

Template:

```
When error budget is:
  Green (>50%):
    - Normal release cadence.
    - Routine chaos experiments allowed.
    - New features prioritized.

  Yellow (10–50%):
    - Increased change scrutiny; larger changes need extra review.
    - Monitor burn rate closely.

  Red (<10%):
    - Change freeze except for reliability work.
    - SREs + eng leads jointly prioritize fixes.
    - Postmortem-driven backlog takes priority.
    - Communicate status to stakeholders weekly.

Policy reviewed quarterly; SLO targets reviewed annually.
```

## SLA vs SLO

- **SLA** — contractual commitment to a customer, often with financial
  penalties.
- **SLO** — internal target, usually tighter than the SLA.

Rule of thumb: **SLO should be at least 10× tighter than SLA**. If SLA
is 99%, aim for an SLO of 99.9% so you have runway before breach.

Don't expose your SLO to customers unless it *is* the SLA. You want
room to miss without telling anyone.

## SLIs that don't work

- **"Internal service reliability"** with no user connection. Reliable
  internal service, broken user flow = green dashboard, red customers.
- **Counting heartbeats instead of journeys.** Uptime checks are a
  liveness probe, not an SLI.
- **SLIs on things you can't move.** If DNS is 99.99% and you're chasing
  99.999% of your own service, you're overfitting.
- **Too-coarse SLIs.** "API availability" across 300 endpoints hides
  the fact that the critical 5 endpoints are red while the rest are
  green.

## Operational recipes

- **SLO dashboard** — for each journey: current SLI, budget remaining,
  burn rate, state of exploited alerts.
- **Weekly review** — 15-min team check: SLOs trending, incidents,
  budget, action items.
- **Quarterly review** — recalibrate SLOs, retire SLIs that are no
  longer representative.

## Starter set for a new service

- 1 **availability** SLO.
- 1 **latency** SLO (P99 or P95).
- (Optional) 1 **data freshness / correctness** SLO if applicable.

Three SLIs is enough. Don't start with twelve.
