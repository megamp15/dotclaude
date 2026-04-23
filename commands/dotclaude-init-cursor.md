---
description: Render dotclaude sources into Cursor config (.cursor/rules/*.mdc, .cursor/mcp.json, AGENTS.md).
---

Run the `dotclaude-init-cursor` skill at `~/.claude/skills/dotclaude-init-cursor/SKILL.md`.

Follow its full workflow:

1. Scan the current repo — same detection as `dotclaude-init` (stacks, frameworks, external services).
2. Present findings, ask for corrections, run the interview.
3. Translate `core/` + matched `stacks/` into **Cursor's native layout**:
   - `.cursor/rules/*.mdc` — one `.mdc` per rule, frontmatter with `globs`, `alwaysApply`, `description` as appropriate.
   - `.cursor/mcp.json` — Cursor's MCP schema, translated from `core/mcp/mcp.partial.json` + any stack MCPs the user accepted.
   - `AGENTS.md` — universal fallback at repo root, composed from core/stack `CLAUDE.*.md` + project context.
4. Print exactly what translated lossily and what didn't translate at all (hooks, fine-grained file/command permissions, Claude-Code-specific subagent processes).

Safe to run alongside `/dotclaude-init` — each renderer writes only to its own directory and cooperates on `AGENTS.md` via `<!-- project-start -->` / `<!-- project-end -->` markers.

Follow `references/mdc-format.md` and `references/translation.md` inside the skill directory for the detailed rules.

$ARGUMENTS
