# Production readiness review (PRR)

The checklist new services run before shipping to customers. Also the
checklist existing services should periodically rerun against.

## The short version

A service is production-ready when:

1. It has defined SLIs/SLOs.
2. Alerts page on user impact, not machine state.
3. Each alert has a linked runbook.
4. It has a rollback plan that's been tested.
5. Capacity is known and load-tested.
6. Secrets and config are injected, not embedded.
7. It gracefully handles dependency failures.
8. Its telemetry (logs, metrics, traces) is correlated.
9. It's covered by on-call rotation.

If you can't check all nine, pick which to defer explicitly — not by
accident.

## Full checklist

### 1. Observability

- [ ] Structured logs with correlation ID (request/trace ID) on every log line.
- [ ] Metrics for the four golden signals (latency, traffic, errors, saturation).
- [ ] Distributed tracing enabled and sampled (at least edge-triggered).
- [ ] One dashboard per service answering "is it healthy?" in < 30 seconds.
- [ ] Logs retained at least 7 days (30 days for regulated workloads).

### 2. SLOs and alerts

- [ ] SLIs defined in terms of user journey, not internal metric.
- [ ] SLO target agreed (not 100%).
- [ ] Error budget policy documented.
- [ ] Multi-window burn-rate alerts (not raw threshold alerts).
- [ ] Every page-severity alert has a runbook linked from the alert
      definition.
- [ ] Alert fatigue check: is this alert expected to page > once/week?
      Tune or remove.

### 3. Reliability patterns

- [ ] Timeouts set on every outbound call (no unbounded waits).
- [ ] Retry policy with exponential backoff + jitter; retries bounded.
- [ ] Circuit breaker on any dependency that can fail (database, external
      API).
- [ ] Graceful degradation — what does the service do when dependency X
      is down? Documented.
- [ ] Idempotency keys on mutating endpoints that retries can hit.

### 4. Capacity

- [ ] Load test run at 2× expected peak; reports known P99 / error rate.
- [ ] Saturation alerts at 70% of capacity (not 100%).
- [ ] Autoscaling configured, tested to actually scale under load.
- [ ] Peak-hour limits reviewed against account quotas (DB connections,
      API rate limits, cloud service quotas).

### 5. Failure modes

- [ ] "What happens if this service dies?" — tested via drill or chaos
      experiment.
- [ ] "What happens if each dependency dies?" — graceful response or
      circuit-breaker.
- [ ] "What happens if the DB is behind on replication?" — read-your-
      writes strategy documented.
- [ ] Restart safety — kill -9 leaves no corrupted state.

### 6. Release and rollback

- [ ] Blue/green or rolling deploy configured.
- [ ] Rollback command tested in staging in the last 30 days.
- [ ] Feature flags for any risky new code path.
- [ ] Canary deploy to a % of traffic before full rollout, for
      non-trivial changes.

### 7. Data

- [ ] Backups configured with known RPO/RTO.
- [ ] Backup restore tested end-to-end in the last quarter.
- [ ] Schema migrations are backward-compatible (old code can still run
      during rollout).
- [ ] Destructive operations (DELETE, DROP, TRUNCATE) require approval.
- [ ] PII flagged; encryption at rest; retention policy defined.

### 8. Security

- [ ] Secrets injected from a managed store (Vault, AWS Secrets Manager,
      ESO); no secrets in env vars at rest or committed config.
- [ ] Workload identity (IRSA / Workload Identity) — no long-lived cloud
      keys.
- [ ] TLS enforced for external traffic; mTLS for service-to-service
      where feasible.
- [ ] Least-privilege IAM / RBAC; audited.
- [ ] Dependencies scanned for CVEs in CI; auto-PR for upgrades
      (Dependabot / Renovate).
- [ ] Container images scanned; signed with cosign.

### 9. On-call and docs

- [ ] Service has a named on-call rotation with ≥ 2 people.
- [ ] Runbooks exist for every page-severity alert.
- [ ] Architecture / ownership doc lives somewhere findable (one-pager,
      not a novel).
- [ ] "Getting started" doc lets a new teammate trace a request in < 1h.
- [ ] Debugging guide for common failure modes.

### 10. Dependencies and contracts

- [ ] Upstream services known; their SLOs mapped to this service's SLO
      needs.
- [ ] Downstream consumers known; breaking changes follow a deprecation
      policy.
- [ ] APIs versioned (URL / header / accept-version).
- [ ] OpenAPI / protobuf / schema published and consumed.

## Runbook template

```
# Runbook: <alert or scenario name>

## When this fires
<The condition; copy from the alert definition>

## Customer impact
<What a user sees — latency, 5xx, stale data, unable to sign in, etc.>

## Severity default
<SEV2 unless it's affecting > X%>

## Dashboards
- <link to service dashboard>
- <link to dependency dashboard>

## First 5 minutes
1. Acknowledge the page.
2. Check the service dashboard — are all the golden signals red, or just
   one?
3. Check recent deploys (`kubectl rollout history ...` / Argo UI).
4. Check recent infra changes (Terraform applies in last 24h).
5. Check upstream providers' status pages.

## Common causes and fixes
| Symptom | Likely cause | Fix |
|---|---|---|
| p99 spikes, CPU normal | DB slow query | Check pg_stat_statements, add index |
| 5xx burst, traces show timeouts to <dep> | Dep down | Cut traffic / fallback |
| Memory creeping up | Leak | Roll the service, file ticket |

## Escalation
If not mitigated in 15 min, page <next tier> / post in <channel>.

## Related
- Postmortem INC-2025-11-04-02 (same symptom, different cause).
- Architecture doc: <link>
```

## Runbook rules

- Linked from the alert. If you're on-call and can't find the runbook in
  10 seconds, it doesn't exist.
- Version-controlled (repo or wiki with history).
- Updated after each incident that revealed a gap.
- Dated — a runbook last touched 3 years ago is a lie.

## "Done" definition for a new service

A service is done with PRR when:

1. Checklist is complete (or each deferred item has a ticket + date).
2. A PRR review meeting happened with at least one SRE (or senior
   engineer outside the team).
3. The team owns the on-call, not the SRE team.

Handing operations to SRE without meeting the checklist is how SRE teams
burn out.
