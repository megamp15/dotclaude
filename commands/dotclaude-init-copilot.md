---
description: Render dotclaude sources into GitHub Copilot config (.github/copilot-instructions.md + path-scoped .instructions.md).
---

Run the `dotclaude-init-copilot` skill at `~/.claude/skills/dotclaude-init-copilot/SKILL.md`.

Follow its full workflow:

1. Scan the current repo — same detection as `dotclaude-init`.
2. Present findings, ask for corrections, run the interview.
3. Translate `core/` + matched `stacks/` into **GitHub Copilot's custom-instructions layout**:
   - `.github/copilot-instructions.md` — top-level file read by Copilot; prose-only, disciplined about the 4000-char code-review budget.
   - `.github/instructions/*.instructions.md` — path-scoped instructions with `applyTo:` frontmatter (globs).
   - `AGENTS.md` — universal fallback at repo root.
4. Print exactly what translated lossily (skills → prose paragraphs, subagents → merged text) and what didn't translate at all (hooks, MCP configuration, fine-grained permissions).

Copilot is the simplest target; if the content isn't expressible in prose, it's dropped. Every drop gets named in the summary.

Follow `references/translation.md` inside the skill directory for the detailed rules.

$ARGUMENTS
