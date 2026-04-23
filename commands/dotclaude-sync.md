---
description: Refresh this repo's .claude/ with upstream changes from DOTCLAUDE_HOME, preserving project-owned files.
---

Run the `dotclaude-sync` skill at `~/.claude/skills/dotclaude-sync/SKILL.md`.

Follow its full workflow:

1. Classify every file in the current repo's `.claude/`:
   - **upstream** — has a `source:` frontmatter tag (came from `core/` or `stacks/`).
   - **project-owned** — no `source:` tag (the project owns these; never touched).
   - **template-seeded** — seeded from `core/templates/` at init, never synced after.
   - **merged** — composite files like `CLAUDE.md`, `settings.json`, `.mcp.json`.
2. For every upstream file, compare its body against the current content in `$DOTCLAUDE_HOME`. Classify as: unchanged, update, add, delete, drift (user edited), or stack-removed.
3. Present a grouped plan, highest-risk first. Bulk-confirm safe operations; per-file confirm anything risky (drift, deletes).
4. Apply the accepted changes. Never silently overwrite drift — offer: take upstream, keep local, or convert file to project-owned (remove the `source:` tag).
5. Print a summary. Leave git as the rollback mechanism.

`$DOTCLAUDE_HOME` must be set; abort with a clear error if it isn't. A `.claude/` directory must already exist; if not, direct the user to `/dotclaude-init` first.

Follow `references/classification.md`, `references/update-rules.md`, and `references/drift-handling.md` inside the skill directory for the detailed rules.

$ARGUMENTS
