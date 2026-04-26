# dotclaude-parallel recipes

## Parallel PR Review

Team lead prompt:

```text
Review this change in parallel. I am the team lead and will synthesize.

Shared input:
- Diff or PR: <scope>
- Blast radius: <if code-review-graph is wired, include it>
- Merge bar: correctness/security/data-loss findings block; style does not.

Teammates:
- code-reviewer: correctness, maintainability, contracts, tests.
- security-reviewer: auth/authz, injection, secrets, crypto, trust boundaries.
- performance-reviewer: resource use, DB, async/concurrency, frontend render cost.
- doc-reviewer: public docs, comments, migration notes, changelog if relevant.
- architect: only if module boundaries or external integrations changed.

Each teammate returns findings with file:line evidence and a ship/fix/rethink
recommendation. Do not rewrite code.
```

Synthesis:

```text
Overall:
Findings: <N block, M consider, K nit>
Agents run:

Blocking:
To consider:
Nits:
Clean bill:
```

## Competing-Hypotheses Debug

Use when there are multiple plausible root causes.

```text
We are debugging <symptom>. Split into competing hypotheses.

Lane A: assume root cause is in <area>.
Lane B: assume root cause is in <different area>.
Lane C: assume dependency/config/data regression.
Verifier: try to disprove the leading hypothesis and demand reproduction.

Rules:
- No code changes until a hypothesis has evidence.
- Each lane must produce a falsifiable test or observation.
- The lead chooses the smallest fix after comparing evidence.
```

## Cross-Layer Feature

```text
Build <feature> with separate lanes and explicit ownership.

Backend owner:
- Files:
- Acceptance:

Frontend owner:
- Files:
- Acceptance:

Tests owner:
- Files:
- Acceptance:

Docs/migration owner:
- Files:
- Acceptance:

Lead owns integration, final verification, and conflict resolution.
```

## Adversarial Design Review

```text
Review this design with separate critique modes.

Socratic lane: ask what must be true for this to work.
Red-team lane: find abuse, failure, and misalignment paths.
Pre-mortem lane: assume launch failed; explain why.
Evidence lane: separate facts, assumptions, and missing data.
Synthesis lane: propose the smallest design changes.
```

## Verification Before Completion

```text
Implementer continues the change.
Verifier independently builds the acceptance checklist, runs available tests,
checks docs/migrations/config, and reports evidence.

Verifier must not edit implementation files unless explicitly reassigned.
```

