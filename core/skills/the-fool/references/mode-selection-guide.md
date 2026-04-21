---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/the-fool/references
ported-at: 2026-04-17
adapted: true
---

# Mode selection guide

Pick the right mode for the situation. Chaining costs time — only do it for
high-exposure decisions.

## Single-mode picker

| Situation | Mode |
|---|---|
| Feels obvious but I can't say why | Socratic questioning |
| Months of investment riding on this | Pre-mortem |
| Public-facing or security-sensitive | Red team |
| The claims in this deck don't smell right | Evidence audit |
| Two options, strong feelings, need to decide today | Dialectic |

## Signals per mode

### Socratic is right when…

- Lots of "obviously" / "everyone knows" language in the pitch.
- Terms are used without being defined (scalable, real-time, better).
- The proposer hasn't articulated alternatives.
- Uncertainty level: "I think this is right but not sure why."

### Pre-mortem is right when…

- High cost of failure or irreversible change (migration, rewrite).
- Plan has many moving parts.
- Confidence feels too high for the complexity.
- Team hasn't discussed rollback.

### Red team is right when…

- External attack surface (public API, auth system, payments).
- Competitor would directly benefit from weaknesses.
- Business logic creates incentives people might exploit.
- Compliance-adjacent areas (PII, payment data, healthcare).

### Evidence audit is right when…

- Proposal leans on specific numbers.
- Claims of X-fold improvement, market adoption, performance.
- Vendor benchmarks or case studies cited.
- Recommendation based on "industry best practice."

### Dialectic is right when…

- Clear go/no-go or choose-A-or-B under pressure.
- One side is being dismissed too quickly.
- Strong opinions without strong evidence on either side.
- Need a defensible decision, not an analysis.

## Chaining (only when exposure is high)

| Chain | When |
|---|---|
| Pre-mortem → Mitigation plan | Large plan; failure narratives drive mitigations |
| Evidence audit → Pre-mortem | Numbers look shaky; also plan a failure mode |
| Red team → Evidence audit | Threat landscape unclear; check what's actually known |
| Socratic → Dialectic | Start by surfacing assumptions, then force a decision |
| Dialectic → Evidence audit | After synthesis, audit what each side claimed |

Don't chain three modes. By the third, you're committing time that the
decision doesn't warrant.

## Time budgets (rough)

| Mode | Target depth | Typical time (alone, for medium decision) |
|---|---|---|
| Socratic | 3–5 questions, 2–3 assumptions surfaced | 15–30 min |
| Pre-mortem | 3 failure narratives with chains | 30–60 min |
| Red team | 2 personas, 3–5 vectors | 30–60 min |
| Evidence audit | 3–5 claims graded | 30–60 min |
| Dialectic | 1 thesis, 1 steel-manned antithesis, 1 synthesis | 30–45 min |

If a mode is taking 2× its budget, you've found complexity worth escalating
(and possibly chaining).

## Anti-patterns

- **Running every mode on every plan.** Performative rigor; low signal.
- **Running one mode because it's familiar.** If the situation calls for red
  team, Socratic questioning won't get there.
- **No verdict at the end.** Every mode ends with a concrete recommendation:
  proceed, proceed with mitigations, or do not proceed.
- **Ignoring the exposure.** Low-stakes decisions get lightweight scrutiny;
  high-stakes decisions earn the chain.
