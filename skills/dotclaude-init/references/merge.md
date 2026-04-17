# Merge rules

Deterministic. Re-running init with the same inputs (repo state + answers)
produces a byte-identical `.claude/`.

## File-by-file behavior

| Source | Target | Strategy |
|---|---|---|
| `core/rules/*.md` | `.claude/rules/*.md` | Copy, inject `source: core` into frontmatter |
| `stacks/<s>/rules/*.md` | `.claude/rules/*.md` | Copy, inject `source: stacks/<s>` |
| `core/skills/**` | `.claude/skills/**` | Recursive copy, preserve folder-per-skill shape |
| `stacks/<s>/skills/**` | `.claude/skills/**` | Recursive copy |
| `core/mcp/skills/**` | `.claude/skills/**` | Copy only if MCP opted in |
| `stacks/<s>/mcp/skills/**` | `.claude/skills/**` | Copy only if MCP opted in |
| `core/agents/*.md` | `.claude/agents/*.md` | Copy + source tag |
| `stacks/<s>/agents/*.md` | `.claude/agents/*.md` | Copy + source tag |
| `core/hooks/*` | `.claude/hooks/*` | Copy, preserve executable bit |
| `stacks/<s>/hooks/*` | `.claude/hooks/*` | Copy, preserve executable bit |
| `core/settings.partial.json` + `stacks/<s>/settings.partial.json` | `.claude/settings.json` | Deep-merge (see below) |
| `core/mcp/mcp.partial.json` + opted-in optionals + `stacks/<s>/mcp/*.mcp.json` | `.mcp.json` at project root | Deep-merge `mcpServers` map |
| `core/CLAUDE.base.md` + `stacks/<s>/CLAUDE.stack.md` + interview | `.claude/CLAUDE.md` | Template render with three sections |

## Deep-merge rules

- **`permissions.allow`** — union of all arrays, deduped, sorted.
- **`permissions.deny`** — union, deduped. Deny wins over allow.
- **`hooks.<event>`** — concatenate entries; entries with the same `matcher` have their `hooks` arrays concatenated (not deduped — duplicates are a user's problem).
- **`mcpServers.<name>`** — object merge. If a stack and core both define the same server name, the stack wins.
- **Anything else** — last-writer-wins with stack > core.

## Source tagging

Every file copied from core/ or stacks/ gets `source:` added to its frontmatter (for markdown) or a comment header (for scripts/JSON):

```yaml
---
source: stacks/python
---
```

Files without `source:` are **project-owned**. `/dotclaude-sync` will never touch them.

## Interview output placement

- **Bullet rules** (rate limits, sensitive paths, public API list) → `.claude/rules/project.md` (no `source:`)
- **Narrative** (description, context, owners) → `.claude/CLAUDE.md` "Project context" section, between `<!-- project-start -->` and `<!-- project-end -->` markers so sync can safely regenerate the other sections around it
- **Raw answers cache** → `.claude/.dotclaude-interview.json` (gitignored)

## Conflict handling on re-init

If a target file exists with `source:` matching current source, and content differs → this is a user edit. Ask:

1. **Overwrite** — lose local edits, take dotclaude version.
2. **Keep local** — remove `source:` so future syncs skip it (file becomes project-owned).
3. **Manual** — print path + diff, skip, let user resolve.

Never silently overwrite user edits.

## Idempotency guarantees

- Same inputs → same outputs (byte-identical).
- Interview answers cached in `.dotclaude-interview.json` so re-runs don't re-ask.
- File ordering in generated `settings.json` / `.mcp.json` is alphabetized for stable diffs.
