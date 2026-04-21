---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/the-fool/references
ported-at: 2026-04-17
adapted: true
---

# Devil's advocate / dialectic synthesis

Use when a single choice is pending under pressure — go/no-go, build vs. buy,
Framework A vs. B. Structured thesis → antithesis → synthesis produces a
decision that is resilient to the strongest version of the opposing view.

Unlike red team (adversaries) or pre-mortem (failure modes), dialectic is
about *choice under uncertainty* — and the discipline of steel-manning the
option you don't favor.

## Process

1. **Thesis.** State the proposed choice cleanly. What does it claim?
2. **Steel-man antithesis.** Construct the strongest version of the
   opposite, not the weakest. If the opposition would argue X, find the
   smartest X they could argue.
3. **Examine tension.** Where do thesis and antithesis genuinely disagree
   (not where they talk past each other)?
4. **Synthesize.** Produce a decision that survives both sides' best case.
   This often isn't a compromise — it's a recognition that one side was
   wrong about something specific.

## Steel-manning rules

| Rule | Why |
|---|---|
| Argue the opposition as if it's your view | Weak opposition is manipulation, not analysis |
| Name the strongest evidence for the opposition | "The best argument for this is…" |
| Identify what would have to be true for the opposition to be correct | Falsification inverted |
| Assume the opposition is at least as smart as you | Arrogance misses real threats |

## Template

```markdown
## Dialectic: <decision>

### Thesis
<Proposed choice, stated cleanly>

**Core claim:** <1 sentence>

**Supporting evidence (best case):**
- [Strongest evidence]
- [Strongest evidence]

### Antithesis (steel-manned)
<Opposite choice, strongest version>

**Core claim:** <1 sentence>

**Supporting evidence (best case):**
- [Strongest evidence]
- [Strongest evidence]

### Tension
Where do these disagree substantively?

| Dimension | Thesis claims | Antithesis claims | Real question |
|---|---|---|---|
| <e.g. scale> | <…> | <…> | <What do we actually know?> |

### Synthesis
<Decision that survives the best case on each side>

**What thesis was right about:** …
**What antithesis was right about:** …
**What the synthesis adds:** …

### Residual risk
<What still isn't resolved, even after synthesis>

### Verdict
**Decision:** <Choose one / Modified thesis / Modified antithesis / Defer>
**Next step:** <What to do in the next 24–72 hours>
```

## Example (abbreviated)

```markdown
## Dialectic: Should we rewrite the billing service in Go?

### Thesis
Rewrite in Go for performance and team skill growth.

### Antithesis (steel-manned)
Keep it in Python. The current performance bottleneck is DB queries, not
language runtime. Rewriting a 40K-line service is a 6-month project with
regression risk in a money-critical path. The team's Go skills can grow on
new services instead.

### Tension
| Dimension | Thesis | Antithesis | Real question |
|---|---|---|---|
| Performance ceiling | Runtime matters | DB dominates | Profile first |
| Risk | Rewrite is fine | Money service ≠ greenfield | What's tested |
| Team growth | Real rewrite best teacher | New services teach too | Where is ROI highest |

### Synthesis
Don't rewrite. Instead:
1. Profile and fix the top 3 DB bottlenecks (thesis was wrong that runtime is the issue).
2. Start the next new service in Go (thesis was right that the team should grow in Go).
3. Revisit rewrite only if profiling shows runtime is the bottleneck post-optimization.

### Verdict
Defer the rewrite; invest in profiling and targeted fixes. Re-evaluate in 3 months.
```

## When dialectic is the right mode

- Genuine go/no-go decisions with strong views on both sides.
- High-stakes choice where a weak opposition has been dismissed too quickly.
- Build vs. buy, monolith vs. microservices, framework A vs. B.

## When it's not

- Exploration ("what are the options?") — use Socratic.
- Failure analysis — use pre-mortem.
- Security / adversarial — use red team.

## Anti-patterns

- **Straw-manning the antithesis.** If the opposing view is absurd as stated,
  you haven't steel-manned.
- **Fake synthesis.** "We'll do a bit of both" that's really "let's do
  thesis and pretend." Be honest if you're picking a side.
- **Dialectic theater.** Going through the motions when the decision is
  already made. Waste of time; just decide.
- **Refusing to conclude.** The output is a decision (or a clear defer with
  criteria for revisiting), not a philosophical discussion.
