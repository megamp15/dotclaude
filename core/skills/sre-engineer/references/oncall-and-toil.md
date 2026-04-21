# On-call and toil

## The on-call contract

What an on-call person owes:

- Answer pages within SLA (typically 5 min to ack).
- Either mitigate or escalate — don't silently try for an hour.
- File a handoff at the end of their shift (even if quiet).
- Follow up on action items from incidents on their shift.

What the org owes the on-call person:

- Alerts that are actionable.
- Compensation (time off, pay, whatever your org agrees).
- A working laptop + VPN + creds, tested before the shift.
- Not asking them to also ship features on a shift week.
- Psychological safety when things break.

## Rotation shapes

| Shape | When |
|---|---|
| **1-week rotation** | 4+ people; most common |
| **Follow-the-sun** | Global team; each region's daytime covers the clock |
| **Primary + secondary** | Primary pages first; secondary escalation after N min |
| **Pair on-call** | Onboarding / training; two people share a shift |

Rules:

- **Minimum 4 people** on a rotation. Fewer means burnout during
  vacation, illness, or attrition.
- **No back-to-back shifts** without a break week.
- **Handoff** in writing (chat or a doc). Outstanding issues,
  suspicious trends, any deferred actions.

## Alert quality

Alerts are a tax. Every page has a cost:

- Sleep disruption.
- Context switch.
- Fatigue → slower response next time.

The one question: **does a human need to do something in the next
hour?** If no, it's not a page.

### The alert ladder

| Signal | Destination |
|---|---|
| Must act now | Page (phone, SMS, app) |
| Act today | Ticket / email |
| Watch it | Dashboard, weekly review |

Demote aggressively. "CPU > 80%" is not a page — it's a dashboard. Page
when user impact is actual or imminent.

### Multi-window burn-rate is the default alert shape

See `slos-and-error-budgets.md`. Resist the urge to alert on the raw
metric — alert on the SLO.

### Alert hygiene metrics

Track:

- **Pages / week / person.** > 2 is suspicious, > 5 is burnout risk.
- **Noise ratio.** (Non-actionable pages / total). > 20% means your
  alerts are lying to you.
- **Time from page to mitigation.** If consistently > 30 min, your
  runbooks or dashboards need work.
- **Pages at 2am / month.** Nighttime pages cost more; special
  vigilance.

Review monthly. Prune 1–3 alerts each month.

## Handoff template

```
## On-call handoff — 2026-04-17 → 2026-04-24

Outgoing:  @alice
Incoming:  @bob

### Open items
- INC-2026-04-16-002: DB replication lag investigation still open.
  Suspect network, @charlie looking into it. Not currently impacting SLO.
- Alert "worker-queue-depth" has fired 3× this week; tuning proposed in
  PR #1234 — needs review.

### Trends to watch
- p99 latency on /api/search up 15% over 2 weeks; not alerting but
  may cross SLO soon.
- Release cadence was heavy; budget at 62% (was 85%).

### Notes
- Secondary is @charlie this week.
- Change freeze continues until Monday per incident of 04-14.

### Stable / low signal
<nothing>
```

## Toil

Toil (per Google SRE): work that is manual, repetitive, automatable,
tactical (no enduring value), interrupt-driven, and scaling linearly
with the service.

**Target**: < 50% of an SRE team's time on toil. More means the team
can't invest in reliability.

### Identifying toil

- "We do this manual thing every week because the system doesn't do
  it automatically."
- "New service onboarding takes 2 days of hand-holding."
- "Every deploy requires a human to restart X and verify Y."
- "We keep restarting that pod every Monday."

### Eliminating toil

1. **Measure.** Log every toil task — rough minutes + frequency.
2. **Rank by total time.** The 80/20 is usually obvious — one or two
   tasks eat most of the hours.
3. **Automate or eliminate.** Don't settle for "document it better"
   unless the frequency is genuinely rare.

Patterns:

- **Auto-remediation** — if the fix is deterministic, script it. A
  bot runs the script, humans get a summary.
- **Self-service** — give teams a CLI / portal for the ops that used
  to go through an SRE ticket.
- **Fix the root cause** — "restart every Monday" is a leak. Fix the
  leak, not the calendar.

## Sustainable on-call practices

- **Follow-up time** — block a morning after a busy shift to close
  tickets and catch up.
- **Postmortem action items** in a shared backlog that SREs + feature
  teams jointly prioritize.
- **Rotate the primary role**, including IC training — every senior
  engineer on the team should be able to run an incident.
- **On-call is a rotation, not a job.** SREs should also be building
  tools / automation / reliability work outside their shifts.

## Measuring on-call health

Once a quarter, ask:

- Is anyone dreading their shift week?
- Are we hitting the 50% toil ceiling?
- Is the alert noise ratio trending up or down?
- Are action items from postmortems closing or piling?
- Do new joiners feel safe taking primary within 3 months?

If the answer is wrong, something in the system is wrong — not
someone.
