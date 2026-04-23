---
description: Render dotclaude sources into a single AGENTS.md at repo root (universal fallback for any coding agent).
---

Run the `dotclaude-init-agents-md` skill at `~/.claude/skills/dotclaude-init-agents-md/SKILL.md`.

Follow its full workflow:

1. Scan the current repo — same detection as `dotclaude-init`, but lighter-weight since the target is one file.
2. Present findings, ask for corrections, run a trimmed interview (`AGENTS.md` is prose; fewer knobs matter).
3. Compose a single `AGENTS.md` at the repo root from:
   - `core/CLAUDE.base.md` — universal instructions, principles, guardrails.
   - Matched `stacks/<name>/CLAUDE.stack.md` — layered on top in the order they were detected.
   - Project context from the interview, enclosed in `<!-- project-start -->` / `<!-- project-end -->` markers so other renderers can safely coexist with it.
4. Print what made it in and what was dropped (skills, subagents, hooks, MCP — `AGENTS.md` is prose-only).

This is the **universal fallback**. Use it for repos whose agent isn't Claude Code / Cursor / Copilot / OpenCode — Continue, Aider, Cline, Zed, and others read `AGENTS.md` as the emerging standard. It's also safe to run alongside any other renderer; they all cooperate on the `<!-- project-start -->` markers.

$ARGUMENTS
