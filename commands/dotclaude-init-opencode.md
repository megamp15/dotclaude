---
description: Render dotclaude sources into OpenCode config (opencode.jsonc, .opencode/{agents,command,instructions}/, AGENTS.md).
---

Run the `dotclaude-init-opencode` skill at `~/.claude/skills/dotclaude-init-opencode/SKILL.md`.

Follow its full workflow:

1. Scan the current repo — same detection as `dotclaude-init`.
2. Present findings, ask for corrections, run the interview.
3. Translate `core/` + matched `stacks/` into **OpenCode's native layout**:
   - `opencode.jsonc` at repo root — MCP config, ask/allow/deny permissions, and project metadata.
   - `.opencode/agents/` — real subagents translated from `core/agents/` and any stack agents.
   - `.opencode/command/` — slash commands for the project-relevant skills.
   - `.opencode/instructions/` — rules split into OpenCode's instructions format.
   - `AGENTS.md` — universal fallback at repo root.
4. Print what translated fully (agents, commands, MCP, permissions — OpenCode is the highest-fidelity non-Claude target) and what remained Claude-Code-specific.

Safe to run alongside `/dotclaude-init` — each renderer writes only to its own directory and cooperates on `AGENTS.md` via `<!-- project-start -->` / `<!-- project-end -->` markers.

Follow `references/translation.md` inside the skill directory for the detailed rules.

$ARGUMENTS
