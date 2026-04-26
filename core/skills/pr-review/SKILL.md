---
name: pr-review
description: Review a pull request by delegating to specialist agents (code, security, performance, docs) and synthesizing a unified report. Use for staged changes, open PRs, specific files, or a branch diff.
source: core
triggers: /pr-review, review PR, pull request review, code review this, review my changes, review staged
---

# pr-review

Orchestrate a multi-agent review. The skill delegates to the specialists
in parallel and synthesizes their findings into one ranked report.

## Invocation patterns

| Input | Interpretation |
|---|---|
| (no arg) | Review staged changes (`git diff --cached`) |
| `staged` | Same |
| PR number | `gh pr diff <n>` |
| Branch name | `git diff main...<branch>` |
| File path | Review that file as changed vs `main` |

## Workflow

### 1. Gather the diff

Use the cheapest source available: `git diff --cached`, `gh pr diff`, or
`git diff main...HEAD`. Capture both the diff and the files touched.

### 1a. (When wired) Get blast radius from code-review-graph

If the project has `code-review-graph` wired (check the conductor brief
for `[code-review-graph wired]` or look for `.code-review-graph/` in the
repo root), call its review-time tools **before** routing to the
specialist agents:

1. `get_minimal_context_tool` — ~100-token framing of what changed.
2. `detect_changes_tool` — risk-scored impact analysis on the diff.
3. `get_impact_radius_tool` — full blast radius (callers, dependents, tests).
4. `get_affected_flows_tool` — which execution flows the change touches.
5. `get_knowledge_gaps_tool` (only if the impact radius includes hot
   paths) — flag untested hotspots inside the radius.

Or invoke the bundled MCP prompt `review_changes` / `pre_merge_check`
directly, which composes these for you.

Pass the resulting blast radius and risk score into the agent fan-out
in step 3 — it tells each specialist what's *actually* in scope, not
just what the diff line-count suggests. Touching one file but having a
47-caller blast radius means the change is much bigger than it looks.

If CRG is not wired, skip this step silently and proceed to step 2.
Do not pretend to have called CRG when you didn't.

### 2. Classify the change

Route to agents based on what the diff touches:

| Touched | Agents to run |
|---|---|
| Any code change | `code-reviewer` (always) |
| Auth, input handling, crypto, deserialization, env, secrets, dependencies | `security-reviewer` |
| DB queries, ORM, network calls, loops over large data, async/concurrency, frontend rendering | `performance-reviewer` |
| `*.md`, docstrings, code comments on public API | `doc-reviewer` |
| Module structure, new boundaries, new external integrations | `architect` |

Always run `code-reviewer`. Run others only if signals match. Running all five on a one-line typo fix is waste.

### 3. Delegate in parallel

Invoke each relevant agent as a subagent, passing the same diff and scope.
Don't serialize — they're independent.

### 4. Merge findings

Combine all agent outputs. Deduplicate — if two agents flag the same line
for related issues, keep both but note the overlap.

Sort by severity: `block` → `consider` → `nit`.

### 5. Produce the synthesis report

```
# PR Review: <title or scope>

## Summary
Overall: <ship / fix-then-ship / rethink>
Findings: N block, M consider, K nit
Agents run: code-reviewer, security-reviewer, ...

## Blocking issues
[from the various agents, highest severity first]

## To consider
[medium severity]

## Nits
[style-level, optional]

## What's good
[call out notable positives — only if honest, don't pad]
```

### 6. Do not

- Rewrite the code. Leave suggestions in prose.
- Merge the PR. Review only.
- Re-run if nothing has changed since the last review in this session.

## Reference guide

| Topic | Reference |
|---|---|
| How each agent works | See `.claude/agents/code-reviewer.md`, `security-reviewer.md`, etc. |
| Diff scoping | `references/diff-scoping.md` |
| Review checklist (universal) | `references/checklist.md` |
