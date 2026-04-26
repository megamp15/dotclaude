---
description: Print the dotclaude re-entry brief — project state, brain-mcp + graphify availability, lifecycle phase. Use on cold start or any time you've lost context.
---

Run the `project-conductor` re-entry brief.

This is identical to what the `conductor-brief.sh` SessionStart hook
prints, but on demand. Use it when:

- You started in an agent that doesn't fire SessionStart hooks.
- You just did `/clear` and want context back.
- You're pasting the brief into a different agent's chat to bootstrap.
- The user explicitly says "resume" / "where am I" / "pick up".

Steps:

1. If `.claude/hooks/conductor-brief.sh` exists in the current project,
   execute it and print its output verbatim. This is the canonical brief.
2. Otherwise, fall back to running the steps inline:
   - `cat .claude/project-state.md` (if present); else note that no
     state file exists yet.
   - Check whether `brain-mcp` is on `PATH` and tell the user / yourself
     to call `brain.context_recovery(domain=<project>)` and
     `brain.open_threads()` if so.
   - Check whether `graphify-out/GRAPH_REPORT.md` exists; if so,
     mention its age and recommend reading it before structural changes.
   - Print a phase hint from cheap git heuristics (commit count, tags,
     last-commit recency).
3. After the brief, do not act yet. Confirm the brief with the user in
   1-2 sentences and ask what they want to do next — unless the brief's
   "Next steps" line is unambiguous and the user has already told you to
   proceed.

The full skill is at `.claude/skills/project-conductor/SKILL.md` with
references for the lifecycle phases and the project-state.md template.

$ARGUMENTS
