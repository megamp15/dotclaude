# Hypotheses and experiments

## The Principles of Chaos (summary)

From [principlesofchaos.org](https://principlesofchaos.org):

1. **Build a hypothesis around steady-state behavior.** Define
   what "normal" looks like quantitatively.
2. **Vary real-world events.** Injected faults should mirror real
   failures: dependency death, latency, CPU spikes, host loss.
3. **Run experiments in production.** Staging doesn't catch what
   production does. (Start in staging; graduate to prod.)
4. **Automate experiments to run continuously.** Manual GameDays
   don't scale; automation catches regressions.
5. **Minimize blast radius.** Contain experiments to the smallest
   scope that still tests the hypothesis.

## Hypothesis template

```
When <fault> is injected into <component> for <duration>,
the <steady-state metric> remains within <bounds>
because <reasoning about the system's defense>.
```

### Good examples

- "When 1 of 3 replicas of `api-service` is killed for 2 min,
  error rate stays below 0.1% because the LB removes unhealthy
  targets within 30s and the remaining replicas have headroom."
- "When DB connection latency increases by 500ms for 5 min,
  checkout success rate stays above 98% because we have circuit
  breakers + a 2s per-query timeout."

### Bad examples

- "We kill a pod and see what happens." — no hypothesis, no
  success criterion.
- "The system should be resilient." — not measurable.
- "Error rate stays below X" — no fault specified, no target
  specified.

## Steady-state definition

Choose the **smallest number of business-level metrics**. Lead
indicators, not lagging.

- **Availability SLI** — successful requests / total.
- **User-visible latency p99**.
- **Core business funnel step conversion** (if checkout is the
  journey).

Not:

- Individual pod metrics.
- System-level saturation.

Those are valuable during the experiment to understand *why*; they
don't define steady state.

## Scoping the experiment

### Blast radius controls

- **Environment** — staging, pre-prod, prod-canary, prod-full.
- **Traffic slice** — via feature flag: 1%, 5%, 25%, 100%.
- **Geographic** — one AZ, one region, all regions.
- **Customer** — internal only, beta tier, all.
- **Duration** — 5 min, 30 min, indefinite (automated).
- **Concurrency** — one fault at a time; don't combine initially.

### Increase gradually

```
week 1: staging, 5 min, observed live.
week 2: staging, 1 hour, automated.
week 3: prod-canary (1% traffic), 5 min, announced.
week 4: prod full, 15 min, announced GameDay.
month 3: prod, automated, off-hours, unannounced.
```

## Abort conditions

Before starting:

- What metric triggers abort?
- Who calls the abort?
- How is abort executed?

Example:

```
Abort if:
  - External uptime probe fails for 30s.
  - Checkout error rate > 2% for 1 min.
  - Pager fires for a different incident.

Abort method:
  chaos-mesh delete experiment/api-pod-kill
  OR: toxiproxy-cli toxic remove api_delay

Decider: facilitator (SRE on-call at the table).
```

Keep the abort tested — run it first, confirm it undoes.

## Experiment phases

1. **Baseline (pre)**: 5 min of normal traffic; record steady-state.
2. **Inject**: fault on.
3. **Observe**: watch metrics; take notes.
4. **Recover**: fault off; measure recovery time.
5. **Debrief**: within 30 min while memory is fresh.

## Runbooks and response

Chaos validates runbooks. Design the experiment to trigger an
alert → verify:

- Did the alert fire at the right threshold?
- Did it reach on-call?
- Could on-call find the runbook?
- Did the runbook steps resolve the issue?
- Any automation that should kick in? Did it?

"Runbook is wrong" is a valid, valuable outcome.

## Common classes of experiments

### Dependency failure

- Kill a pod in a downstream service.
- Introduce latency/packet loss to a dependency.
- Full "black hole" of a dependency.

### Infrastructure failure

- Kill a node.
- Disconnect a node's network.
- Simulate AZ outage.
- Simulate region outage (DR drill).

### Resource exhaustion

- Fill a disk.
- CPU starvation.
- Memory pressure.
- File descriptor exhaustion.

### Misbehavior

- DNS returning stale records.
- Clock skew.
- Corrupt config pushed.
- Slow response vs. timeout.

### Data / state

- Corrupted message on a queue.
- Duplicate messages.
- Out-of-order delivery.
- Stale cache.

## GameDay facilitation

### Roles

- **Facilitator** — drives the agenda, calls injection/abort.
- **Observer** — watches dashboards, calls out anomalies.
- **Scribe** — timestamps every event.
- **Support** — on-call + domain experts.

### Agenda

- 0:00 — Welcome, review hypothesis, review abort criteria.
- 0:05 — Pre-inject: verify steady state.
- 0:10 — Inject fault.
- 0:10–0:25 — Observe, take notes, don't intervene unless abort
  triggers.
- 0:25 — Recover. Observe recovery.
- 0:35 — Debrief: findings, surprises.
- 0:50 — Action items.

Total ~1 hour. Don't try 3 experiments in one session early on.

## Write-up template

```markdown
# Experiment: <title>
Date: 2026-04-17
Facilitator: <name>
Scribe: <name>

## Hypothesis
When <fault> is injected into <component> for <duration>,
<metric> remains within <bounds>.

## Environment
<staging / prod; traffic slice; AZ; duration>

## Steady state
| Metric | Pre | During | Post |
|---|---|---|---|
| error rate | 0.05% | 0.08% | 0.05% |
| p99 latency | 120ms | 145ms | 125ms |
| conversion | 38.4% | 38.1% | 38.3% |

## Timeline
- 10:00 — pre-inject check OK
- 10:05 — fault injected (kill 1/3 api-svc pods)
- 10:05:32 — LB marked pod unhealthy
- 10:06:04 — new pod in ready state
- 10:15 — fault ended
- 10:16 — fully recovered

## Observations
- <what we saw>
- <surprises>

## Findings
- <where the system was as designed>
- <gaps>

## Action items
1. Owner / deadline — <concrete change>
2. ...
```

## Automation pipeline

Progressing from manual to automated:

1. **Scheduled manual** — GameDay cadence monthly.
2. **Automated in staging** — kill / latency experiments nightly;
   alert if steady state breaks.
3. **Automated in prod off-peak** — once staging results stable
   for 3 months.
4. **Continuous** — small-scope experiments run 24/7 in prod.

Auto-abort on SLO breach is mandatory for automated runs.

## Measuring program success

- **Resilience findings per quarter** — experiments should yield
  action items; zero findings = experiments too shallow.
- **MTTR trend** — incidents post-chaos-program vs. pre.
- **Runbook quality** — runbooks updated based on chaos findings.
- **Drill fidelity** — does a practice drill look like a real
  incident?

Don't measure "number of experiments run" — a Goodhart's law
trap.

## When to not do chaos

Defer if:

- Active major incident or release freeze.
- Critical business event (Black Friday, product launch week).
- Observability stack broken — you can't see what happens.
- Team staffing thin (holiday weekend with one on-call).

Better to delay than to run a sloppy chaos exercise.
