---
name: documentation
description: What to document, what not to, and where
source: core
alwaysApply: true
---

# Documentation

The best documentation is clear code. The second-best is documentation
that explains what code can't: **intent, trade-offs, constraints, history**.

## What to write down

- **Why** a non-obvious decision was made. "Why retry 5 times and not 3." "Why Redis and not an in-process cache."
- **Trade-offs** that were considered and rejected. Future-you will propose them again otherwise.
- **Landmines** — the thing that looks broken but isn't, the workaround that must stay.
- **Setup and run steps** that aren't automated. (If they *can* be automated, automate them and document only what the automation couldn't capture.)
- **How to deploy** and how to roll back.
- **External dependencies** — what breaks if this service is down, what breaks if it's down.

## What NOT to write down

- **What the code does line-by-line.** The code says it. Comments drift; code doesn't.
- **Obvious API usage.** If the library has good docs, link to them, don't mirror them.
- **Step-by-step for every feature in a README.** Keep the README scannable; put walkthroughs in linked pages.
- **Architecture diagrams that nobody maintains.** A stale diagram is worse than no diagram. If you draw it, own it.

## README

Every project has one. A good README answers, in order:

1. **What is this?** One sentence. What problem it solves, not how.
2. **Status** — production / experimental / archived.
3. **Quickstart** — install + run in under a minute.
4. **Common tasks** — test, lint, build, format, deploy.
5. **Architecture** — one paragraph or one diagram. Where things live.
6. **How to contribute** — or link to CONTRIBUTING.
7. **License + support** — where issues go, who maintains.

If your README starts with the company history or a wall of badges, a newcomer quits before finding the install line.

## ADRs (architecture decision records)

For decisions that will be questioned later: write a short ADR.

- **Context** — what problem, what constraints.
- **Decision** — what we chose.
- **Considered alternatives** — what we rejected and why.
- **Consequences** — what this commits us to, what it rules out.

One page. Dated. Never edited after ratification except to mark superseded. `docs/adr/` or `docs/decisions/`. Numbered.

## Inline comments

Default is: write code that doesn't need them.

When you *do* need a comment, it should explain **intent or context the code can't carry**:

- Why the order of operations matters (`// must reset before emit; downstream consumer caches on emit`)
- Why a specific value was chosen (`// 512KB: chosen to fit in one TLS record`)
- What external constraint drove the shape (`// API returns items[] wrapped in data[]; we unwrap once here`)
- Pointers to issues, RFCs, spec sections (`// RFC 7231 §6.5.1`)

**Never** narrate:

- `// increment the counter`
- `// return the result`
- `// loop over items`
- `// import the module`

That's not documentation; it's wallpaper.

## Docstrings and API docs

- **Public APIs get docstrings.** Internal helpers usually don't need them if names are good.
- **Docstring says what the function does from the caller's perspective** — inputs, outputs, errors raised, notable side effects. Not implementation.
- **Examples in docstrings** age. If you include one, it must run (doctest, code fence verified in CI, or a tested example file).

## Diagrams

- **Only if you maintain them.** Stale diagram = misinformation.
- **Prefer generated** (from OpenAPI, from code, from infra config). Hand-drawn diagrams drift; generated ones don't.
- **Sequence diagrams beat box-and-arrow** for explaining flows.
- Keep them in the repo as text (Mermaid, PlantUML) so they diff and review.

## Changelogs

- Kept for libraries and for user-facing releases. Not needed for internal-only tools.
- **Keep a Changelog** format. Unreleased at top. Grouped by Added / Changed / Deprecated / Removed / Fixed / Security.
- Written for **users**, not for maintainers. "Fixed crash on empty input" beats "refactored handler.py".

## Runbooks

For any alert that pages a human: **there must be a runbook link in the alert**.

- Symptom: what the alert says.
- Impact: who/what is affected.
- Immediate action: what to do first to stop the bleeding.
- Investigation: how to find root cause.
- Escalation: who to wake up.

Test runbooks in gamedays. Out-of-date runbooks are worse than missing ones.
