# Parallel fallbacks

## Claude without Agent Teams

Use ordinary subagents in parallel when the host supports that fan-out. Keep the
team-lead pattern: one orchestrator gathers context, delegates independent
lanes, then synthesizes.

## Codex

Use bounded sidecar agents only when the user explicitly allows delegation or
parallel agent work. Assign disjoint write sets to worker agents. Use explorers
for specific codebase questions that can run while implementation continues.

Good Codex split:

```text
Main agent: integration and final verification.
Worker 1: backend files only.
Worker 2: frontend files only.
Worker 3: tests only.
Explorer: answer one scoped architecture/risk question.
```

## Cursor

Cursor rules translate skills into intent-triggered guidance, not true
teammates. Use a manual lane plan:

```text
Lane 1: backend implementation
Lane 2: frontend implementation
Lane 3: tests
Lane 4: review checklist
```

Run one lane at a time, or use separate Cursor windows on separate worktrees.

## GitHub Copilot

Copilot has the lowest fidelity. Put the lane split directly in the prompt and
ask it to complete exactly one lane. Use a human or another agent as the lead.

## Worktree Agents

For heavier parallel work:

1. Create one git worktree per lane.
2. Give each agent an ownership brief and acceptance checklist.
3. Keep shared files in the lead worktree when possible.
4. Merge lane branches one at a time.
5. Run verification after each merge, then full verification at the end.

This is slower than Agent Teams but safer for long-running independent work.

