---
name: dotclaude-parallel
description: Run parallel agent workflows with Claude Code Agent Teams when available, with fallbacks for regular Claude subagents, Codex, Cursor, Copilot, and worktree-based agents. Use for parallel PR review, competing-hypotheses debugging, cross-layer feature work, adversarial design review, and verification-before-completion.
source: core
triggers: /dotclaude-parallel, agent teams, parallel agents, swarm, multi-agent, parallel PR review, competing hypotheses, adversarial review, cross-layer feature, teammate, teammate idle, task completed, worktree agents, subagent driven development, verification before completion
---

# dotclaude-parallel

Use the strongest parallel primitive available, then fall back cleanly.

Priority order:

1. Claude Code Agent Teams, when `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
   is available.
2. Claude subagents invoked in parallel by the orchestrator.
3. Codex-style delegated workers/explorers, when the host supports them.
4. Worktree-based parallel agents.
5. Manual lane split for Cursor/Copilot/AGENTS.md users.

## When to use

- Parallel PR review across code, security, performance, docs, and architecture.
- Competing-hypotheses debugging where multiple root causes are plausible.
- Cross-layer feature work with independent frontend, backend, tests, docs, or
  migration lanes.
- Adversarial design review with multiple critique modes.
- Verification-before-completion, where an independent verifier checks the work
  while the implementer finishes.

Do not use this for tiny tasks. Parallelism has coordination cost.

## Team setup

If Agent Teams are available:

1. Create a team lead responsible for synthesis and final decisions.
2. Create one teammate per independent lane.
3. Assign each teammate a file ownership scope or read-only review scope.
4. Put acceptance criteria in the shared task list.
5. Require every teammate to report evidence, files touched, tests run, and
   blockers.
6. Use the `TaskCompleted` hook as the verification gate.

If Agent Teams are not available, load
[`references/fallbacks.md`](references/fallbacks.md) and run the closest
available pattern.

## Recipes

Load [`references/recipes.md`](references/recipes.md) for full prompts.

Short forms:

- `parallel-pr-review`: code-reviewer, security-reviewer,
  performance-reviewer, doc-reviewer, optional architect.
- `competing-debug`: 2-4 investigators with different hypotheses, one verifier
  that tries to falsify the winning explanation.
- `cross-layer-feature`: separate owners for backend, frontend, tests, docs, and
  migrations. No shared write set unless the lead explicitly coordinates it.
- `adversarial-design-review`: run modes from `the-fool` as separate lanes:
  Socratic, red-team, pre-mortem, evidence audit, synthesis.
- `verification-before-completion`: implementer continues while verifier builds
  the checklist, runs tests, and checks acceptance criteria.

## Coordination rules

- Every lane must be concrete, bounded, and materially useful.
- Never assign two writers to the same files unless the lead owns integration.
- Do not let a verifier rewrite implementation files. Verification is evidence.
- Ask teammates to prefer small diffs, local patterns, and focused tests.
- The lead synthesizes; teammates do not merge each other's conclusions by
  committee.
- If a teammate goes idle, narrow the task, provide missing context, or reclaim
  the work.

## Completion gate

A lane is complete only when it reports:

```text
Result:
Files changed:
Tests or checks run:
Evidence:
Remaining risk:
```

If `CLAUDE_TEAM_VERIFY_CMD` is set, the `TaskCompleted` hook runs it. Set
`CLAUDE_AGENT_TEAM_STRICT=1` to make a failed verification command block the
completion hook.

