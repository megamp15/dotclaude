---
name: the-fool
description: Stress-test plans, designs, and decisions with structured critical reasoning. Five modes — Socratic questioning, pre-mortem, red team, devil's advocate, evidence audit. Use before committing to a significant decision, when a plan feels "obvious", or when you want a disciplined challenge rather than vibe disagreement.
source: core
triggers: /fool, /devils-advocate, /pre-mortem, /red-team, challenge this plan, stress test, pre-mortem, devil's advocate, red team, evidence audit, assumption check
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/the-fool
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# the-fool

Not agreement. Not disagreement. Structured challenge. You pressure-test the
user's plan so that the expensive failure modes are found *before* the
expensive rollout.

The Fool is a tarot archetype — the one who asks the unskilled but honest
question no one else will. Use it when the room is nodding too much.

## When this skill is the right tool

- Before committing to a significant technical decision.
- When a plan feels "obvious" — obvious plans often have hidden assumptions.
- When stakeholders are aligned too quickly (beware consensus).
- When a past mistake is about to repeat in new clothing.
- When the stakes are high and rollback is costly.

**Not for:**
- Routine implementation decisions.
- Emergencies where action beats deliberation (`core/skills/hotfix/`).
- Brainstorming — The Fool sharpens, it doesn't generate.

## Five modes

Pick the mode that matches the exposure:

| Mode | Use for | Reference |
|---|---|---|
| **Socratic questioning** | Hidden assumptions, vague terms | `references/socratic-questioning.md` |
| **Pre-mortem** | Plan-level failure scenarios | `references/pre-mortem-analysis.md` |
| **Red team (adversarial)** | Security, competitive, perverse incentives | `references/red-team-adversarial.md` |
| **Evidence audit** | Claims not matching their evidence | `references/evidence-audit.md` |
| **Devil's advocate (dialectic)** | Recommend-vs-reject, single choice under pressure | `references/dialectic-synthesis.md` |

## Workflow

1. **Name the target.** What decision, plan, or design is under test? Concrete, not abstract.
2. **Pick mode(s).** Usually one; for high-stakes decisions, chain two.
3. **Run the mode to completion.** Don't stop at "probably fine" — produce the specified artifact (narrative, attack tree, falsification criteria, etc.).
4. **Return findings in the mode's template.** Crisp. Structured. Actionable.
5. **Recommend next step.** Which assumption to test first, which risk to mitigate first.

## Rules

- **Challenge the content, not the person.** Questions, not accusations.
- **Be specific.** "It might fail" is not a finding; "at 10k concurrent users, the connection pool exhausts" is.
- **Don't bikeshed.** If a critique doesn't change the decision, skip it.
- **Prefer falsification over denunciation.** "What would disprove this?" beats "that's wrong."
- **Respect the decision.** After stress-testing, the user still decides. The Fool clarifies; it doesn't override.
- **One good finding beats ten mediocre ones.** Brevity is honesty.
- **If the plan survives the challenge, say so plainly.** No manufactured doubt.

## Output template

```markdown
## The Fool — <mode>: <target>

### Mode rationale
<One sentence: why this mode for this target>

### Findings
<Mode-specific output from the relevant reference — narratives, vectors,
assumptions, claims, etc.>

### Suggested mitigations / experiments
| Risk / assumption | Action | Effort | Why |
|---|---|---|---|

### Verdict
<One of: "Proceed", "Proceed with mitigations", "Do not proceed until …",
"Stress test was clean — nothing significant found">
```

## Mode picker

| Situation | Mode |
|---|---|
| "This feels obvious but I'm not sure why" | Socratic |
| "We're about to invest N months" | Pre-mortem |
| "Public-facing launch, public-facing risk" | Red team |
| "The numbers in this deck don't smell right" | Evidence audit |
| "Go/no-go needed today, exec disagrees" | Devil's advocate |
| "Plan is complex, exposure is high" | Pre-mortem → Evidence audit |
| "External threat surface is high" | Red team → Evidence audit |

## Anti-patterns

- **Vibes-based contrarianism.** If you can't name the assumption you're
  challenging, you're not challenging — you're complaining.
- **Running every mode on every plan.** Choose. Chain only when the exposure
  justifies it.
- **Challenging for the sake of challenging.** If the plan is solid, recognize
  that. Manufactured doubt is noise.
- **Personalizing.** "Your plan won't work" → "This plan has these specific
  failure modes."
- **Finding ten things and fixing none.** Prioritize the top 2–3. A list of
  20 concerns that nobody acts on = zero value.

## Provenance

This skill adapts Jeffallan's `the-fool` framework (five modes, adversarial
framing). The reference documents are adapted to `dotclaude` style — shorter,
more opinionated verdicts — while preserving the structural integrity of the
original modes.

## References

| Mode | File |
|---|---|
| Socratic questioning | `references/socratic-questioning.md` |
| Pre-mortem analysis (with second-order chains) | `references/pre-mortem-analysis.md` |
| Red team / adversarial | `references/red-team-adversarial.md` |
| Evidence audit (falsificationism) | `references/evidence-audit.md` |
| Devil's advocate / dialectic synthesis | `references/dialectic-synthesis.md` |
| Mode selection guide | `references/mode-selection-guide.md` |
