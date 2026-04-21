---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/the-fool/references/evidence-audit.md
ported-at: 2026-04-17
adapted: true
---

# Evidence audit

A claim is only meaningful if you can specify what would disprove it
(Popper). The Evidence Audit mode extracts claims from a proposal, designs
falsification criteria, assesses evidence quality, and surfaces competing
explanations.

The goal isn't to disprove — it's to determine whether the evidence actually
supports the conclusion.

## Process

1. **Extract claims.** Find the specific claims being made (often implicit).
2. **Design falsification criteria.** For each claim, what would disprove it?
3. **Assess evidence quality.** Grade the evidence supporting each claim.
4. **Identify cognitive biases.** Systematic errors in reasoning.
5. **Surface competing explanations.** Alternatives for the same evidence.

## Claim types

| Type | Example | Hidden in |
|---|---|---|
| Causal | "X causes Y" | "Our refactor improved performance" |
| Predictive | "X will happen" | "Users will adopt this" |
| Comparative | "X is better than Y" | "React is the better choice for us" |
| Existential | "X exists / doesn't exist" | "There's no alternative" |
| Universal | "X is always true" | "Microservices always improve velocity" |
| Quantitative | "X is N" | "This will save 200 hours/quarter" |

### Extraction method

For each statement in the proposal:

1. Is it a claim or a definition?
2. If a claim, what type?
3. What evidence is cited (or implied)?
4. What would make this claim false?

### Example

```
Statement: "Based on our pilot, migrating to Kubernetes will reduce deployment
time by 60%."

Claims extracted:
1. The pilot results are representative of production (Predictive)
2. Kubernetes is the cause of the reduction (Causal)
3. The 60 % reduction will persist at scale (Quantitative)
```

## Falsification criteria

| Claim | Falsification criterion | Test |
|---|---|---|
| "Users want feature X" | <10 % engagement within 30 days | Feature flag; measure adoption |
| "Will scale to 100K users" | Response > 500 ms at 50K | Load test to target |
| "Migration takes 3 months" | >2 unknown-unknowns discovered in month 1 | Track surprise count |
| "Framework X is faster" | <5 % difference on representative benchmark | Controlled benchmark |
| "Will reduce costs" | TCO > current cost within 12 months | TCO analysis incl. migration, training, ops |

### Unfalsifiable claims (red flag)

| Pattern | Example | Problem |
|---|---|---|
| Vague outcome | "This will improve things" | No measurable criterion |
| Moving goalposts | "It'll work eventually" | No time boundary |
| Circular | "Best because experts recommend it" | Evidence is the claim restated |
| Hedged | "Might help in some cases" | True by definition |

When you see these, ask: "What specific, measurable outcome would tell us
this worked or didn't work?"

## Evidence quality matrix

| Dimension | Strong | Weak |
|---|---|---|
| Sample size | Large, representative | Single case, anecdote |
| Recency | <12 months | 2+ years old |
| Relevance | Same domain + scale | Different domain or scale |
| Independence | Multiple independent sources | Single or vendor-provided |
| Methodology | Controlled, reproducible | Ad hoc, unreproducible |
| Specificity | Precise metrics + conditions | Vague or qualitative |

### Grading scale

| Grade | Description | Reliability |
|---|---|---|
| A | Controlled experiment, large sample, reproducible | High |
| B | Observational data, reasonable sample, consistent | Moderate |
| C | Case study, small sample, single source | Low — needs corroboration |
| D | Anecdote, opinion, vendor marketing | Insufficient alone |
| F | No evidence | Unsupported |

### Weak-evidence patterns

| Pattern | Example | Weakness |
|---|---|---|
| Survivorship bias | "Companies using X are successful" | Ignores companies using X that failed |
| Cherry-picked metric | "Response time improved 40 %" | Other metrics may have worsened |
| Vendor benchmarks | "Our tool is 3× faster" | Optimized for vendor's strengths |
| Appeal to authority | "Google does it this way" | Google's constraints ≠ yours |
| Anchoring | "Industry average is X" | The average may not be your benchmark |

## Cognitive biases to check

| Bias | Signal |
|---|---|
| Confirmation | Only positive evidence cited; no counter-evidence considered |
| Survivorship | "All the successful companies do X" |
| Anchoring | First estimate unchanged despite new data |
| Sunk cost | "We've already spent 6 months on this" as justification |
| Availability | Decision based on one vivid incident |
| Bandwagon | "Everyone is doing it" without fitness assessment |
| Dunning-Kruger | Confident claims in unfamiliar domain |
| Status quo | "It's always been this way" despite change evidence |

## Competing explanations (abductive reasoning)

For every conclusion, ask: "What else could explain this evidence?"

### Example

```
Evidence: "Deployment failures dropped 50 % after adopting tool X."

Proposed explanation: Tool X is better.

Alternatives:
1. The team also started doing more code review in the same period.
2. A particularly error-prone service was retired last month.
3. The team gained experience that would have improved results with any tool.
```

Compare the explanatory power of each. If the evidence is equally consistent
with multiple explanations, the original claim is overstated.

## Output template

```markdown
## Evidence audit: <proposal / decision>

### Claims extracted
| # | Claim | Type | Evidence cited |
|---|---|---|---|
| 1 | [Claim] | Causal/Predictive/… | [What supports it] |

### Falsification criteria
| Claim | What would disprove it | How to test |
|---|---|---|

### Evidence quality
| Claim | Grade | Key weakness |
|---|---|---|
| #1 | A/B/C/D/F | [Primary concern] |

### Bias check
| Bias detected | Where | Impact |
|---|---|---|

### Competing explanations
| Evidence | Proposed explanation | Alternatives |
|---|---|---|

### Verdict
**Overall evidence strength:** Strong / Moderate / Weak / Insufficient

**Recommendations:**
1. [Action to strengthen the weakest claim]
2. [Action to test the riskiest assumption]
```

## Anti-patterns

- **Grading everything as A.** If every claim is strong, you didn't audit — you validated.
- **Nitpicking every minor claim.** Focus on the claims that drive the decision.
- **Demanding impossibly rigorous evidence.** Calibrate to the exposure —
  low-risk decisions don't need RCT-grade data.
- **Listing alternatives without comparing.** "Could also be X, Y, or Z" is
  just brainstorming. You need to weigh them.
