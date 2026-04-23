---
description: Initialize or update a project's .claude/ by merging dotclaude core + stacks + project context.
---

Run the `dotclaude-init` skill at `~/.claude/skills/dotclaude-init/SKILL.md`.

Follow its full workflow:

1. Scan the current repo (stack detection, framework detection, external services, existing `.claude/`).
2. Present findings and ask the user to correct anything wrong.
3. Ask at most ~5 interview questions — only about things code can't reveal (owners, rate limits, sensitive paths, public API surface).
4. Merge `core/` + all matched `stacks/<name>/` + interview answers into a flat `.claude/` directory in the repo root.
5. Write `.mcp.json` at the repo root from `core/mcp/mcp.partial.json` + any stack/optional MCP selections.
6. Tag every file that came from `core/` or `stacks/` with a `source:` frontmatter entry. Leave project-owned files (like `rules/project.md`) untagged.
7. Print a summary of what was written, which stacks were applied, and which optional MCPs the user skipped.

`$DOTCLAUDE_HOME` must be set; abort with a clear error if it isn't. Read sources from `$DOTCLAUDE_HOME/core/` and `$DOTCLAUDE_HOME/stacks/<name>/`.

Follow `references/scanning.md`, `references/interview.md`, and `references/merge.md` inside the skill directory for the detailed rules.

$ARGUMENTS
