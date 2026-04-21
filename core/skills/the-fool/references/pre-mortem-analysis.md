---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/the-fool/references/pre-mortem-analysis.md
ported-at: 2026-04-17
adapted: true
---

# Pre-mortem analysis

A pre-mortem inverts the question. Instead of "will this work?" — assume
it failed. It's 6 months from now. *Why did it fail?*

The inversion bypasses optimism bias by making failure the starting point.

## Process

1. **Set the scene.** "It's [timeframe] from now. This plan has failed. Not a
   small setback — a clear failure."
2. **Generate failure narratives.** Specific stories, not abstract worries.
3. **Rank by likelihood × impact.** Not all failures are equal.
4. **Trace consequence chains.** First → second → third order.
5. **Identify early warning signs.** What would you see before the failure?
6. **Design mitigations.** Concrete actions, not vague "be careful".

## Failure narratives must be specific

"It didn't scale" is not a narrative. A narrative names:

- A specific trigger (event or threshold).
- A chain of events, not just the end state.
- Who/what was affected.
- The underlying assumption that proved wrong.

### Narrative template

```markdown
**Failure: <title>**

It's <timeframe> from now. <Specific trigger>. This caused <first-order
effect>, which led to <second-order effect>. The team discovered it when
<detection point>, but by then <consequence>. The root cause was <underlying
assumption that proved wrong>.
```

### Example

```markdown
**Failure: Migration data loss**

It's 3 months from now. During the database migration from PostgreSQL to the
new schema, a batch job silently drops records where `legacy_id` contains
special characters (~2 % of records). The team discovers this 2 weeks
post-migration when a customer reports missing order history. By then, the
legacy database has been decommissioned and backups have rotated past the
migration date. The root cause was that the migration script was tested
against a sanitized staging dataset that didn't include special characters.
```

## Second-order consequence chains

Every failure has effects beyond the immediate impact. Trace at least two
levels deep.

```
Trigger: [event]
  → 1st order: [immediate effect]
    → 2nd order: [consequence of the 1st]
      → 3rd order: [consequence of the 2nd]
```

### Common second-order patterns

| First order | Second order | Third order |
|---|---|---|
| Feature ships late | Sales misses quarter | Eng loses trust, gets more oversight |
| Performance degrades | Users adopt workarounds | Workarounds calcify into "requirements" |
| Key engineer burns out | Knowledge concentrates | Bus factor drops, risk rises |
| Dependency breaks | Hotfix bypasses testing | Bugs introduced, release confidence drops |
| Data quality issue | Reports are wrong | Decisions made on bad data |

## Inversion: "what would guarantee failure?"

| Category | Guaranteed-failure conditions |
|---|---|
| People | Single point of knowledge, no stakeholder buy-in, team doesn't believe in approach |
| Process | No rollback plan, no incremental validation, all-or-nothing deployment |
| Technology | Untested at target scale, undocumented deps, version lock-in |
| Timeline | No buffer, external dependencies with no SLA, parallel critical paths |
| Data | Migration without validation, no data-quality checks, schema changes without backward compatibility |

Ask the plan owner: do any of these conditions exist right now?

## Domain failure patterns

### Technical

| Pattern | Trigger | Typical outcome |
|---|---|---|
| Integration cliff | New service connects to 3+ existing systems | One integration blocks all others |
| Scale surprise | Load 10× beyond testing | Cascading failures |
| Migration trap | "Just move the data" | Data loss, extended downtime, rollback impossible |
| Dependency rot | Pinned to abandoned library | Vulnerability with no upgrade path |
| Config drift | Manual environment setup | "Works on my machine" becomes "works in no machine" |

### Business

| Pattern | Trigger | Typical outcome |
|---|---|---|
| Adoption cliff | Build it, they don't come | Sunk cost without revenue |
| Competitor preempt | Competitor ships similar first | Positioning lost |
| Timing mismatch | Market shifts during dev | Solves yesterday's problem |
| Stakeholder reversal | Sponsor changes | Priority collapses |
| Hidden cost | Ops burden underestimated | Feature costs more than it earns |

### Process

| Pattern | Trigger | Typical outcome |
|---|---|---|
| Timeline fantasy | Best-case estimates | Crunch or scope cuts at the worst time |
| Dependency chain | A waits on B waits on C | Any slip cascades |
| Knowledge silo | Expert leaves/unavailable | Progress stops; replacement ramps for weeks |
| Scope creep | "While we're at it…" | Original goal buried |
| Feedback void | No user test until launch | Wrong product built correctly |

## Early warning signs

| Sign | Predicts |
|---|---|
| "We'll figure that out later" repeated | Critical decisions deferred, not resolved |
| No one can explain the rollback | Rollback hasn't been designed |
| Estimates keep growing | Hidden complexity surfacing |
| Key meetings keep rescheduling | Stakeholder alignment weaker than assumed |
| "It works locally" | Environment parity worse than thought |
| Testing phase compressed | Quality will be sacrificed |
| No success metrics defined | No one will know if this worked |

## Output template

```markdown
## Pre-mortem: <plan / decision>

**Timeframe:** <when would failure be evident>

### Failure narratives

#### 1. <title> — Likelihood: H/M/L | Impact: H/M/L
<Narrative>

**Consequence chain:**
- 1st: [immediate]
- 2nd: [downstream]
- 3rd: [systemic]

#### 2. <title> — Likelihood: H/M/L | Impact: H/M/L
<Narrative>

#### 3. <title> — Likelihood: H/M/L | Impact: H/M/L
<Narrative>

### Early warning signs
| Signal | Predicts | Check frequency |
|---|---|---|

### Mitigations
| Failure | Mitigation | Effort | Reduces risk by |
|---|---|---|---|

### Inversion check
- What would guarantee failure: [top 3 conditions]
- Do any exist now? [Yes/No, with specifics]
```

## Anti-patterns

- **Generic narratives.** "The launch goes badly." That's not a narrative.
- **Stopping at first-order effects.** Most of the damage lives at second
  and third order.
- **Mitigations that aren't actions.** "Monitor carefully" is a wish; "add
  alerts on X metric at Y threshold, with runbook Z" is a plan.
- **Ranking everything as High/High.** Forces no prioritization. Be honest.
