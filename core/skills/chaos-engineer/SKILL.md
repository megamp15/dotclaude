---
name: chaos-engineer
description: Deliberate failure injection to verify system resilience — hypothesis-driven experiments, steady-state metrics, blast-radius control, fault injection (latency, packet loss, pod kills, dependency failure, region outage), GameDay planning, and tools (Chaos Mesh, Litmus, AWS FIS, Gremlin, Toxiproxy). A discipline, not a hobby.
source: core
triggers: /chaos, chaos engineering, GameDay, fault injection, Chaos Monkey, Chaos Mesh, Litmus, Gremlin, AWS FIS, Toxiproxy, pumba, pod kill, network partition, packet loss, latency injection, resilience test, failure scenario
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/chaos-engineer
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# chaos-engineer

Hypothesis-driven failure injection. Activates when the question
is about deliberately breaking things to prove the system is as
resilient as we claim.

> **See also:**
>
> - `core/skills/sre-engineer/` — SLOs, incidents, readiness —
>   chaos engineering feeds PRR
> - `core/skills/monitoring-expert/` — you need observability to
>   measure steady state
> - `stacks/kubernetes/skills/kubernetes-specialist/` — K8s fault
>   tools

## When to use this skill

- Planning your first GameDay.
- A service claims "five nines" availability and you want evidence.
- Before / after major architectural changes (region migration,
  DB failover, cell architecture).
- Validating runbooks work when real pages go off.
- Periodic resilience audits.

## When *not* to use this skill

- Unstable system with active incidents. Fix the fires first.
- No observability. You can't measure steady state; chaos is a
  stunt.
- No blast-radius controls. You'll cause a real outage.
- Political unwillingness to support the experiment. Without
  leadership buy-in, one "chaos caused outage" event kills the
  program.

## References (load on demand)

- [`references/hypotheses-and-experiments.md`](references/hypotheses-and-experiments.md)
  — Principles of Chaos; hypothesis template; steady-state
  metrics; blast-radius; abort conditions; GameDay facilitation;
  post-experiment write-up.
- [`references/fault-catalog.md`](references/fault-catalog.md) —
  standard faults (latency, packet loss, CPU/memory hog, disk
  full, pod kill, node kill, DNS failure, dependency down, clock
  skew, region partition) with tool mappings (Chaos Mesh, Litmus,
  AWS FIS, Gremlin, Toxiproxy, pumba, tc, stress-ng).

## Core workflow

1. **Start with observability.** If you can't graph steady-state
   metrics, don't inject anything.
2. **Write a hypothesis.** "When we kill a random pod of service
   X, error rate remains < 0.1% over 5 min."
3. **Control the blast radius.** Staging first. Production with a
   small % of traffic / single AZ. Explicit abort conditions.
4. **Inject the smallest effective fault.** Start with latency;
   escalate to packet loss; escalate to kill.
5. **Observe steady state.** Did metrics stay within SLO? Did
   runbooks work? Did paging fire appropriately?
6. **Abort on real impact.** Any user-facing SLO breach → stop
   immediately.
7. **Write it up.** Experiment report with hypothesis,
   observations, findings, action items.
8. **Automate the proven ones.** Ones that have passed multiple
   times run unattended in a lower-stakes env.

## Defaults

| Question | Default |
|---|---|
| First experiment | Pod kill in staging |
| Progression | staging → prod canary % → full prod → scheduled |
| Abort threshold | Any user SLO breach; page fires |
| Duration | 5–15 min first time; longer as confidence grows |
| Observability stack | Must be live for chaos; alerts tested |
| Notification | Announce the GameDay to stakeholders; surprise drills only when mature |
| Tool for K8s | Chaos Mesh (OSS) or Litmus |
| Tool for AWS | AWS Fault Injection Simulator |
| Tool for network | Toxiproxy (app-level) or `tc netem` (node) |
| Tool for process stress | stress-ng on the node |
| Frequency | Monthly manual GameDays; automated kills daily in staging |
| Sign-off to run in prod | Leadership + on-call + SRE approval |
| Post-experiment | 5-pager: goal, hypothesis, observation, findings, actions |

## Anti-patterns

- **Chaos Monkey in prod with no observability.** "See what
  breaks" is not an experiment.
- **No abort criteria.** If all hell breaks loose, what do we do?
- **Running during business-critical events.** Black Friday =
  postpone.
- **Assuming "the system is fine"** when the chaos tool says no
  error. Validate against independent signals (user reports,
  support tickets, external probes).
- **Only injecting what you already know fails.** Real value comes
  from inventing scenarios you're uncertain about.
- **Testing failure of critical dependencies you have no fallback
  for.** "DB goes down" with no replica = you learn you need a
  replica; that's fine — but do it in staging first.
- **GameDay with no learnings.** If nothing was wrong, bar was too
  low. Scale up.
- **Blame.** Chaos reveals gaps; fix systems, not people.

## Output format

For an experiment proposal:

```
Title:          <short>
Hypothesis:     <"When X happens, Y stays within Z">
Variables:
  Target:       <service / component>
  Fault:        <kind + magnitude + duration>
  Scope:        <staging / X% prod / 1 AZ>
Steady state:   <metric + acceptable range>
Abort when:     <specific SLO breach>
Duration:       <N minutes>
Runbook:        <expected response steps>
Rollback:       <undo command>
Observers:      <names; on-call>
Comms:          <channel; stakeholders>
```

For an experiment report:

```
Hypothesis:     <what we expected>
Execution:      <what we did, when>
Steady state:
  metric A:     before <x>, during <y>
  metric B:     before <x>, during <y>
  user impact:  <none / measured>
Findings:       <system behaved as / not as expected>
Action items:
  1. <fix or enhancement>
  2. ...
Next experiment: <what to try next>
```

## The progression model

```
 Level 1: staging, single service, small fault
 Level 2: staging, multi-service, multi-fault
 Level 3: prod canary (1% traffic), single fault, announced
 Level 4: prod full, single fault, announced GameDay
 Level 5: prod, automated, unannounced
```

Move up only after multiple successful runs at the current level.

## GameDay checklist

Pre:

- [ ] Hypothesis written and reviewed.
- [ ] Observability dashboards curated.
- [ ] Abort criteria explicit.
- [ ] Runbook for expected response.
- [ ] On-call briefed (or explicitly not, if testing paging).
- [ ] Stakeholder comms sent (time, scope, expected impact).
- [ ] Rollback tested.
- [ ] Experiment doc in Confluence / Notion / Drive.

During:

- [ ] Scribe captures events with timestamps.
- [ ] Facilitator controls pace.
- [ ] Abort if criteria triggered — no hero mode.
- [ ] Observations per stage.

Post:

- [ ] Immediate retrospective with participants.
- [ ] Write-up within 48h.
- [ ] Action items tracked with owners + dates.
- [ ] Share findings broadly.

## Defining "steady state"

Choose metrics that users notice:

- Error rate (per route / journey).
- Latency p95 / p99.
- Throughput.
- Queue depth.
- Availability SLI.

Not:

- Node CPU.
- Pod count.
- Memory utilization.

Those are internal; they shift under chaos by design.

## Tool selection

| Target | Tool |
|---|---|
| K8s pods / nodes / DNS / network | **Chaos Mesh** or **Litmus** |
| AWS infra | **AWS Fault Injection Simulator** |
| GCP / Azure | Chaos Mesh on K8s; cloud-specific probes |
| Service-to-service HTTP / TCP | **Toxiproxy** |
| Linux processes / network | `tc netem`, `stress-ng`, `pumba` |
| Managed / org-wide | **Gremlin** (commercial), **Steadybit** |
| App-layer JVM | **ChaosToolkit** + Byteman |
| Simulated region outage | DNS-level cutoff + firewall rules |

Start OSS. Invest in Gremlin/Steadybit when the program matures
and justifies cost.

## Cultural prerequisites

Chaos engineering needs:

- A blameless culture (see `sre-engineer/references/incidents-and-postmortems.md`).
- Observability (`monitoring-expert`).
- Runbooks (`sre-engineer/references/production-readiness.md`).
- Leadership willing to say "we value resilience enough to
  deliberately break things".

If any of these is missing, build those first. Chaos without
them causes damage without learning.
