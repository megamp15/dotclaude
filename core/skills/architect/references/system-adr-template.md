---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/architecture-designer/references/adr-template.md
ported-at: 2026-04-17
adapted: true
---

# ADR template

Architecture Decision Records capture the **why** behind significant decisions.
Future maintainers read them before reversing something. An ADR written after
the fact is just archaeology.

## Template

```markdown
# ADR-<NNN>: <Title in present tense>

## Status
Proposed | Accepted | Deprecated | Superseded by ADR-<M>

## Context
The situation and forces at play. What problem? What constraints? What are we
trying to achieve? Why now?

## Decision
What we will do. One paragraph, no hedging.

## Alternatives considered
- **<Alt 1>** — rejected because <specific reason>
- **<Alt 2>** — rejected because <specific reason>
- **<Alt 3>** — considered, may revisit if <condition>

## Consequences
### Positive
- <Benefit>
### Negative
- <Cost or drawback>
### Neutral
- <Side effects that are neither good nor bad>

## References
- <Link to RFC / thread / doc>
```

## Example: ADR-001 Use PostgreSQL for the primary database

```markdown
# ADR-001: Use PostgreSQL for the primary database

## Status
Accepted — 2026-04-17

## Context
We need a relational store for the order service. Requirements:
- ACID transactions across orders, line items, customers.
- Flexible columns for product attributes (JSON).
- Current team has PostgreSQL and MySQL experience.
- Expected scale: 10M orders/year for the next 3 years.
- Managed hosting is acceptable; self-hosting is not.

## Decision
Use PostgreSQL 16 on AWS RDS Multi-AZ as the primary store for the order
service.

## Alternatives considered
- **MySQL on RDS** — similar operational profile, but JSON features and
  indexing are weaker for our flexible-attribute use case.
- **DynamoDB** — excellent scalability but forces denormalisation and
  cross-aggregate queries become painful.
- **CockroachDB** — better horizontal scaling, but the team has no operational
  experience and the cost is significantly higher at our scale.

## Consequences
### Positive
- Strong transactional guarantees suit the order domain.
- Rich tooling; team is productive on day one.
- JSONB columns give us flexibility without leaving SQL.
### Negative
- Vertical scaling has a ceiling. At ~5× current scale we'll need to think
  about read replicas or sharding.
- Managed RDS cost for Multi-AZ + backups is non-trivial.
### Neutral
- Migration from the current SQLite development DB is needed.

## References
- NFR doc: `docs/architecture/nfr.md`
- Benchmark spike: `docs/spikes/db-comparison.md`
```

## Naming and storage

- Location: `docs/adr/NNNN-kebab-case-title.md`
- Numbering: zero-padded to 4 digits, never reused.
- A `README.md` in `docs/adr/` lists every ADR with its status.

## Status transitions

| From | To | When |
|---|---|---|
| Proposed | Accepted | Decision is made and the work begins |
| Accepted | Deprecated | We stop doing this but don't replace it |
| Accepted | Superseded | A new ADR replaces it — link both ways |

Never delete an ADR. History matters even for bad decisions — *especially* for
bad decisions.

## Anti-patterns

- Writing an ADR for trivial choices. "Use HTTPS" is not an ADR.
- Listing alternatives with no rationale for rejection.
- Vague consequences ("may improve things").
- ADRs that narrate a meeting instead of the decision.
- Editing an accepted ADR in place to change the decision. Write a new one
  and mark the old "Superseded by".
