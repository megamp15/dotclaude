---
name: sre-engineer
description: Site reliability engineering — SLIs/SLOs/error budgets, incident command, blameless postmortems, capacity planning, on-call hygiene, toil elimination, and the production readiness checklist. Distinct from `monitoring-expert` (which is the telemetry plumbing), `debug-fix` (which is tactical), and `chaos-engineer` (which is one tool in the SRE belt).
source: core
triggers: /sre, reliability, SLI, SLO, error budget, incident response, on-call, runbook, postmortem, production readiness, capacity planning, toil, change management, release engineering
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/sre-engineer
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# sre-engineer

Reliability engineering at the platform and service level. Activates when
the question is about operational maturity — SLOs, incidents, postmortems,
on-call — not "how do I fix this one bug".

> **See also:**
>
> - `core/skills/monitoring-expert/` — metrics / logs / traces plumbing
> - `core/skills/debug-fix/` — tactical "something is broken right now"
> - `core/skills/chaos-engineer/` — fault injection as one tool
> - `core/skills/homelab-infra/` — physical layer reliability
> - `core/rules/observability.md` — baseline conventions

## When to use this skill

- Drafting SLIs / SLOs / error budgets for a new or existing service.
- Writing a runbook or postmortem that's actually useful six months later.
- Running an incident as IC or scribe.
- Deciding what "production ready" means for your team.
- Planning capacity (CPU, memory, DB, queue) before you run out.
- Cutting toil that's eating the on-call rotation.

## References (load on demand)

- [`references/slos-and-error-budgets.md`](references/slos-and-error-budgets.md)
  — SLI selection (the four golden signals, user-journey SLIs), SLO targets,
  error budgets and how policy flows from them, burn-rate alerts.
- [`references/incidents-and-postmortems.md`](references/incidents-and-postmortems.md)
  — incident command roles, severity levels, comms cadence, timeline
  discipline, blameless postmortem template, follow-up action tracking.
- [`references/production-readiness.md`](references/production-readiness.md)
  — the PRR checklist (observability, scaling, failure modes, runbooks,
  security, load tests, rollback, data).
- [`references/oncall-and-toil.md`](references/oncall-and-toil.md) — alert
  quality, rotation shapes, handoff discipline, Google's toil definition,
  toil budgeting, the 50% rule.

## Core workflow

1. **Pick SLIs that reflect user experience**, not what's easy to measure.
   Availability and latency of the critical user journey, not CPU.
2. **Set SLO targets that give headroom** — 99.9% gives 43.8 min/month,
   99.95% gives 21.9 min. Pick deliberately; it drives everything.
3. **Protect the error budget** — if you're burning it, slow down changes
   and add reliability work. If you have slack, ship faster.
4. **Invest in the on-call signal**. Every alert is a tax; alerts that
   don't require human action go away.
5. **Postmortems are a product**, not a compliance artifact. They change
   the system; they're not filed and forgotten.

## Defaults

| Question | Default |
|---|---|
| Availability SLO for internal service | 99.5% |
| Availability SLO for customer-facing | 99.9% (three 9's) |
| Latency SLO | P99 < some threshold appropriate to the journey |
| Alert type | Multi-window burn-rate on SLO; NOT "CPU > 80%" |
| Incident severity scale | SEV1 / SEV2 / SEV3; define customer impact in each |
| Postmortem timeline | Draft within 48h, reviewed within 1 week |
| On-call shift | Follow-the-sun or 1-week rotations; never single point of failure |
| Runbook location | Beside the alert definition (linked from the alert, stored in the repo or a known wiki) |
| Capacity planning cadence | Quarterly for steady services, monthly for growing ones |
| Change freezes | During active SEV1/2 incident, during high-risk business periods |

## Anti-patterns

- **CPU-based alerts paging humans.** CPU high ≠ user pain. Alert on user
  impact.
- **Availability SLOs without a definition of "available".** "99.9%" is
  meaningless until you define which requests count.
- **100% uptime targets.** You'll never achieve them and they block every
  change. Set budgets you intend to spend.
- **"Hero" postmortems.** "Alice fought valiantly for six hours" — the
  question is why it took six hours.
- **Action items with no owner or due date.** They never get done.
- **On-call rotations with one person on them.** Single point of failure
  in the team itself.
- **Runbooks that are just screenshots of kubectl output.** Describe
  decisions, not keystrokes.
- **No change freeze plan.** First SEV1 during an AWS outage is how people
  learn.

## Output format

For SLO design:

```
Service:       <service>
User journey:  <what the user is trying to do>
SLI:           <the ratio: good events / total events>
Target SLO:    <99.X over 28d>
Error budget:  <minutes/month>
Burn-rate alerts:
  - Fast:  <X%/h for N minutes → page>
  - Slow:  <X%/h for N hours  → ticket>
```

For incident response:

```
Severity: SEV<N>
Impact:   <customer-visible impact, quantified>
IC:       <name>
Scribe:   <name>
Ops:      <name>
Timeline: (UTC)
  HH:MM   <event>
  HH:MM   <event>

Current status: <investigating / mitigating / monitoring / resolved>
Next update:    <HH:MM or "on change">
```

For postmortems:

```
Summary
Impact: <duration, customers, revenue, data>
Timeline
Root cause
Why it wasn't caught
Action items (owner, due, tracker)
Lessons learned
What went well
```
