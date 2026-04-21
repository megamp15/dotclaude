---
name: feature-forge
description: Conduct a structured requirements workshop that produces a feature spec — user stories, EARS-format functional requirements, acceptance criteria, and an implementation checklist. Use for new features, significant enhancements, or any work where "we sort of know what we want" is the starting point. Distinct from spec-miner (reverse-engineering existing code) and architecture-designer (system-level design).
source: core
triggers: /feature-forge, /spec, feature spec, requirements workshop, user story, acceptance criteria, EARS requirement, feature planning, define the feature
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/feature-forge
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# feature-forge

You run a structured interview that turns vague feature ideas into a
precise, buildable spec. Output is always the same shape: stories,
EARS-format requirements, acceptance criteria, and an implementation
checklist the next agent (or human) can execute against.

## When this skill is the right tool

- New feature where "we think we want X" is the starting point
- Enhancement whose real shape isn't captured in an existing ticket
- Feature with more than one stakeholder (engineering, product, design, ops)
- Feature that touches security, compliance, or cross-team boundaries

**Not for:**
- Bug fixes → `debug-fix`
- Reverse-engineering existing code → `spec-miner`
- System-level design → `architecture-designer`
- Implementation — you produce the spec, not the code

## Workflow

### 1. Pre-discovery (parallel)

Before the interview, seed technical context so the session focuses on
decisions, not exploration:

- Scan the repo for related existing patterns (auth, validation, similar
  features).
- Note the stacks in use (from `AGENTS.md` / `CLAUDE.md`).
- If high-stakes: delegate to `architecture-designer` or `security-audit`
  for a pre-read.

### 2. Interview (PM hat → Dev hat → Validation)

See `references/interview-questions.md` for the full bank. Principle:
**closed questions first, open-ended second**. Structured choice reduces
cognitive load and surfaces disagreement faster.

#### Phase 1: Discovery (PM hat)

- **Problem.** What problem, whose problem, how often?
- **Users.** Who, what do they want, what do they do today?
- **Value.** Why now? Business outcome?
- **Scope.** MVP vs. full, in vs. explicitly out of scope.
- **Success.** What metric will tell us this worked?
- **Priority.** Must-have / should-have / nice-to-have.

#### Phase 2: Details (mixed)

- User journey (open-ended).
- Edge cases (empty, over-limit, over-time).
- Integrations — APIs, external services, internal dependencies.

#### Phase 3: Technical (Dev hat)

- Auth + authorization model.
- Data model changes.
- Performance expectations.
- Error handling approach.
- Security implications.
- Backwards-compatibility concerns.

#### Phase 4: Validation

- Summarize the spec back.
- Ask: "What's missing? What's over-scoped?"
- Confirm priority on each requirement.

### 3. Write the spec

Use the output template below. Every requirement is in EARS format
(see `references/ears-syntax.md`).

## Output template

```markdown
# Feature spec: <name>

## Summary
<1–2 sentences: what this is, why it matters>

## Users + value
- **Primary user:** <persona>
- **Problem:** <what's broken or missing>
- **Value:** <business/user outcome>
- **Success metric:** <how we'll know>

## In scope / out of scope

### In scope
- <bullet>

### Out of scope
- <bullet — explicit about what we are NOT doing>

## User stories

- As a <persona>, I want <capability>, so that <outcome>.
- …

## Functional requirements (EARS)

**FR-<AREA>-001**: <title>
<EARS statement>

**FR-<AREA>-002**: <title>
<EARS statement>

…

## Non-functional requirements

| NFR | Target |
|---|---|
| Response time | <e.g. p95 < 200 ms> |
| Availability | <e.g. 99.9 %> |
| Compliance | <GDPR, SOC 2, …> |

## Edge cases
- <empty state, rate limits, large input, concurrent edit, …>

## Data model changes
<new tables/fields or "none">

## API surface
<new endpoints / event schemas or "none">

## Security considerations
- Authentication: <…>
- Authorization: <…>
- Sensitive data: <…>
- Threat model notes: <…>

## Acceptance criteria

- [ ] <testable, binary outcome>
- [ ] <testable, binary outcome>

## Implementation checklist

- [ ] <concrete step for the implementing agent>
- [ ] <concrete step>

## Open questions
- <unresolved decision with owner>

## Decision log
- <major choice + rationale>
```

## EARS format (required)

Every functional requirement is in EARS. See `references/ears-syntax.md`.

Patterns:

| Type | Pattern | Example |
|---|---|---|
| Ubiquitous | `The system shall <action>` | The system shall encrypt all passwords using bcrypt. |
| Event | `When <trigger>, the system shall <action>` | When the user clicks Submit, the system shall save the form. |
| State | `While <state>, the system shall <action>` | While the user is logged in, the system shall display the dashboard. |
| Conditional | `While <state>, when <trigger>, the system shall <action>` | While the cart contains items, when the user clicks Checkout, the system shall navigate to payment. |
| Optional | `Where <feature enabled>, the system shall <action>` | Where 2FA is enabled, the system shall require a verification code. |

## Rules

- Every FR is EARS. "Shall" not "should."
- Every FR is testable. If you can't write a test, the requirement is vague.
- Acceptance criteria are binary. "Works well" is not acceptance criteria.
- In-scope and out-of-scope are both explicit.
- Priority is set per-FR (must / should / nice).
- Security and compliance questions asked in every interview — not optional.
- Open questions are listed, not hidden. The next agent reads them before coding.
- Spec fits in 2–3 pages. Longer usually means you're designing, not specifying.

## Do not

- Ship a spec with "TBD" on scope, security, or success metric.
- Write requirements in prose paragraphs. Use EARS.
- Skip the validation phase. Specs that aren't repeated back are wrong.
- Design the implementation inside the spec. Leave room for the implementing
  agent to choose.
- Boil the ocean. If the spec is 15 pages, break the feature into smaller features.

## References

| Topic | File |
|---|---|
| EARS syntax + worked examples | `references/ears-syntax.md` |
| PM-hat and Dev-hat interview questions, structured option style | `references/interview-questions.md` |
| Spec template + acceptance criteria patterns | `references/spec-template.md` |
