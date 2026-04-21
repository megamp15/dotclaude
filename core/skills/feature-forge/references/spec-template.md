---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/feature-forge/references
ported-at: 2026-04-17
adapted: true
---

# Spec template + acceptance criteria

## Full spec template

```markdown
# Feature spec: <name>

**Status:** draft / in review / approved
**Owner:** <name/team>
**Stakeholders:** <PM, eng, design, ops, security, …>
**Target release:** <version or date window>

## Summary
<1–2 sentences: what this is, why it matters>

## Users and value
- **Primary user:** <persona>
- **Secondary users:** <persona>
- **Problem:** <what's broken or missing>
- **Value:** <user/business outcome>
- **Success metric:** <how we'll know this worked>

## Scope

### In scope
- <bullet>
- <bullet>

### Out of scope
- <bullet — explicit about what we are NOT doing>

### Future (nice-to-have, not this release)
- <bullet>

## User stories
- As a <persona>, I want <capability> so that <outcome>.
- As a <persona>, I want <capability> so that <outcome>.

## Functional requirements (EARS)

**FR-<AREA>-001 — <title>**
<EARS statement>

**FR-<AREA>-002 — <title>**
<EARS statement>

…

## Non-functional requirements

| NFR | Target | Notes |
|---|---|---|
| Response time | <e.g. p95 < 200 ms> | <how measured> |
| Availability | <e.g. 99.9 %> | <SLA scope> |
| Throughput | <e.g. 100 RPS> | <peak, steady> |
| Compliance | <GDPR, SOC 2> | <applies to this feature> |
| Accessibility | <WCAG 2.1 AA> | |

## Data model changes

| Entity | Change | Notes |
|---|---|---|
| `orders` | Add `export_id` column | Nullable, indexed |
| `exports` | New table | See below |

<optional: DDL snippet or entity diagram>

## API surface

| Method | Path | Purpose | Auth |
|---|---|---|---|
| POST | /exports | Create an export | user |
| GET | /exports/{id} | Check status | owner or admin |

## Edge cases

- Empty input → <behavior>
- Over rate limit → <behavior>
- Concurrent edit → <behavior>
- Partial failure → <behavior>
- Client disconnect mid-upload → <behavior>

## Security

- Authentication: <mechanism>
- Authorization: <model — owner, role, scope>
- Sensitive data: <fields, handling>
- Audit: <what gets logged>
- Threat model notes: <key risks, mitigations>

## Observability

- Metrics: <list>
- Logs: <structured fields required>
- Alerts: <thresholds>
- Dashboards: <what to display>

## Acceptance criteria

- [ ] <binary, testable outcome>
- [ ] <binary, testable outcome>
- [ ] <binary, testable outcome>

## Implementation checklist

- [ ] <concrete step>
- [ ] <concrete step>
- [ ] Unit tests for <FRs>
- [ ] Integration tests for <critical paths>
- [ ] Feature flag created: `<flag_key>`
- [ ] Runbook added / updated
- [ ] Dashboard + alerts wired
- [ ] Documentation updated

## Rollout

- Feature flag: <default off; staged rollout plan>
- Migration: <if any, order and rollback>
- Communication: <internal announcement, external changelog>

## Open questions

| # | Question | Owner | Needed by |
|---|---|---|---|

## Decision log

- <date>: Decided to <choice> because <rationale>.
- <date>: Rejected <alternative> because <reason>.
```

## Acceptance criteria patterns

Binary. Testable. Specific. One outcome per bullet.

### Good

- A logged-in user can create an export with CSV format via POST /exports and receives a 202 with a job URL.
- An export that exceeds 10 MB is processed asynchronously and the user receives an email within 15 minutes of completion.
- A logged-out user calling POST /exports receives a 401 with `code: UNAUTHENTICATED`.
- The export file is deleted from storage within 24 hours of first successful download.

### Bad

- "The export works correctly." (not testable)
- "The UX is good." (subjective)
- "Exports are secure." (not specific — secure how?)
- "The system handles large exports." (how large? handles how?)

## Checklist styles

### Behavior checklist (user-facing)

```markdown
- [ ] User can request a CSV export.
- [ ] User sees an immediate confirmation and job ID.
- [ ] User receives an email when a large export is ready.
- [ ] User can download the generated file from a unique URL.
- [ ] File is deleted 24 h after first download.
```

### Implementation checklist (engineer-facing)

```markdown
- [ ] Add `exports` table migration.
- [ ] Implement POST /exports endpoint with validation.
- [ ] Wire background worker using existing job queue.
- [ ] Emit `Export.Requested` and `Export.Completed` events.
- [ ] Add Prometheus metrics: `exports_total`, `export_duration_seconds`.
- [ ] Add alert: p95 > 120 s for 5 minutes.
- [ ] Add feature flag: `exports_enabled`.
- [ ] Update OpenAPI spec for /exports endpoints.
```

## Anti-patterns

- **Implementation in the spec.** "The system shall use Redis for caching" —
  belongs in an ADR or design doc, not an FR.
- **Vague acceptance criteria.** "Works well under load" — unprovable.
- **Checklist that only restates FRs.** Checklists must add concrete steps
  (feature flag, migration, alert, dashboard, runbook).
- **No open questions.** If every answer is known, you didn't stress-test
  the spec. At least two open questions is the norm early on.
- **Spec longer than 2–3 pages.** Break the feature into smaller features.
