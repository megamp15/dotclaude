# Incident response and postmortems

## Severity levels

Define in advance; never litigate severity during an incident.

| SEV | Customer impact | Response |
|---|---|---|
| SEV1 | Major outage, significant revenue loss, data integrity compromised | Immediate page; IC declared; all-hands if needed |
| SEV2 | Degraded experience for many users; feature unavailable | Page during business hours + nights; IC assigned |
| SEV3 | Minor / limited impact; workaround exists | Ticket, fixed next business day |
| SEV4 | No user impact; internal only | Tracked in backlog |

## Roles during an incident

Separate the roles, especially for SEV1/SEV2.

- **Incident Commander (IC)** — coordinates. Does NOT fix. Delegates.
  Decides severity, comms cadence, and when to resolve. Maintains the
  "cone of command".
- **Scribe** — keeps the timeline in the incident doc. Every new piece
  of information, every action, every decision. Timestamps in UTC.
- **Ops / Investigator** — the person (or people) actually diagnosing
  and mitigating. Reports to the IC.
- **Comms** — external communication: status page, customer support,
  executives. One voice, not ten.
- **Subject matter experts (SMEs)** — pulled in for specific areas.

For small teams one person can wear two hats — but never IC + Ops.
That's the fastest way to lose the thread.

## Incident doc template

Create a shared doc the moment the incident starts. Everyone sees and
edits it.

```
# INC-2026-04-17-001: <short title>

Severity: SEV2
Status: Investigating   (→ Mitigating → Monitoring → Resolved)

IC: @alice
Scribe: @bob
Ops: @charlie, @dana
Comms: @erin

Impact: <one-sentence customer impact, quantified>

War room: #inc-2026-04-17-001 (slack), Zoom <link>

## Timeline (UTC)
14:03  alerting fired: auth latency p99 > 2s
14:05  @alice acked; opened incident
14:06  @charlie confirmed in dashboard; traffic normal, DB CPU at 95%
14:09  @dana noticed slow queries on sessions table; adding index...
14:15  index created; latency back to normal
14:25  monitoring for 10 more minutes before resolving
14:35  resolved

## Current hypothesis
Slow query on sessions.last_seen during a high-traffic burst.

## Actions taken
- [14:09] @dana — add index on sessions.last_seen
- [14:15] @charlie — verify p99 dropped

## Open questions
- Why did this only happen now?
- Was the query recently introduced? Git blame...

## Customer comms
[14:10] status page posted: "Investigating auth latency"
[14:20] status page updated: "Identified root cause"
[14:40] status page posted: "Resolved"
```

## Communication cadence

| SEV | Internal update cadence | External update cadence |
|---|---|---|
| SEV1 | Every 15 min (or on state change) | Every 30 min |
| SEV2 | Every 30 min | Every hour |
| SEV3 | At state change | As needed |

Rules:

- Even "no new info" is an update — say "still investigating,
  next update in X minutes".
- Customers would rather hear silence broken by a useless update than
  wonder if anyone is working on it.

## Declaring resolution

Two criteria, both required:

1. **Impact ended** — customers are no longer feeling it.
2. **Confidence the fix holds** — some minutes of monitoring, or you
   understand the mechanism enough to know it's over.

Don't resolve just because you're tired. "Monitoring" is a valid state
for as long as you need.

## Postmortem — blameless, actionable

Timeline: draft within 48h, reviewed within 1 week, action items
tracked to completion.

Template:

```
# Postmortem: INC-2026-04-17-001 — Auth latency spike

**Authors:** @alice, @charlie
**Date of incident:** 2026-04-17
**Severity:** SEV2
**Duration:** 14:03 UTC — 14:35 UTC (32 minutes)

## Summary
A missing index on sessions.last_seen caused slow queries during a
traffic burst, driving p99 auth latency from 200ms to 2.4s.

## Impact
- 32 minutes of degraded auth performance.
- ~18,000 sign-in attempts with >2s latency.
- Estimated ~1.2k users retried or abandoned.
- No data loss, no security incident.

## Timeline
(see incident doc)

## Root cause
Query added in commit abc123 (2026-04-10) scans sessions.last_seen
without an index. At normal traffic the Seq Scan finished in 30ms;
at peak it exceeded 1s, saturating the DB CPU and queue.

## Contributing factors
- No query review in the PR that introduced it.
- Staging traffic is < 5% of production, so the issue never
  surfaced pre-release.

## Detection
- Alerted via "auth p99 latency > 1s for 5m" burn-rate alert.
- Time from user impact to page: ~90 seconds.
- Time from page to IC ack: ~2 minutes.

## Mitigation
Created index with CONCURRENTLY; latency returned to normal within
6 minutes of index creation.

## Action items
| Action | Owner | Due | Ticket |
|---|---|---|---|
| Add query-plan regression tests to CI | @dana | 2026-04-24 | PLAT-1234 |
| Enforce EXPLAIN review in PR for new queries on large tables | @alice | 2026-05-01 | PLAT-1235 |
| Add synthetic load to staging to surface index gaps | @bob | 2026-05-08 | PLAT-1236 |

## What went well
- Burn-rate alert fired quickly.
- On-call ack was fast; IC assigned within 2 min.
- Diagnosis took 6 minutes once everyone was on the call.

## What we'd do differently
- Catch the missing index in pre-prod — the issue was detectable at
  commit time with EXPLAIN.
- Set up an alert on DB CPU > 80% sustained — would have paged
  earlier.

## Lessons learned
- Queries added to high-traffic paths need an EXPLAIN review.
- Staging traffic is insufficient to catch index-related regressions.
```

## Blameless, in practice

Blameless ≠ "nobody made a mistake". It means:

- Identify the *system* that let the mistake cause harm.
- Assume the person acted with the best available information.
- Focus actions on the system (review gates, alerts, automation), not
  people.

Bad: "Bob pushed an unindexed query."
Good: "A query without an EXPLAIN review reached production because our PR
process doesn't require one for DB-touching changes."

## Action item hygiene

- **Owner** — one name.
- **Due date** — realistic, specific.
- **Tracking** — a real ticket, not "in the doc".
- **Status reviewed** — weekly until closed. Overdue action items show
  up in the next postmortem.

More than ~5 action items usually means you're being generous. Prioritize
3 that'll prevent the class of incident; the rest are nice-to-have.

## Postmortem reviews

Read them out loud at an ops review once a quarter. The goal:

- Pattern-spot across incidents.
- Re-ask "did the action items actually happen?"
- Catch gaps (same class of incident appearing twice = system hasn't
  changed).

## Executive / customer summary

SEV1 / SEV2 often need a public-facing version. Rules:

- Plain language, no Kubernetes jargon.
- State what happened, what was affected, for how long.
- Say what you're doing to prevent recurrence.
- Don't over-promise ("This will never happen again" is a lie).
- Don't under-share ("A component had an issue" is not a postmortem).
