---
source: core/templates
---

# Templates

Example files that `dotclaude-init` copies (and renames) into a target
repository's `.claude/` directory, then stops touching. They're starting
points that each developer or project edits.

## What lives here

| Template | Target path | Purpose |
|---|---|---|
| `CLAUDE.local.md.example` | `.claude/CLAUDE.local.md` | Per-developer, uncommitted context overrides |
| `settings.local.json.example` | `.claude/settings.local.json` | Per-developer, uncommitted settings overrides |

## Merge behavior

Templates are **one-shot copied**, not merged on re-run. `dotclaude-sync`
must skip them — otherwise it would clobber a developer's local edits.

The target repo's `.gitignore` should contain, after init:

```
.claude/CLAUDE.local.md
.claude/settings.local.json
```

The `dotclaude-init` skill is responsible for adding those entries if
missing.

## When to add a new template

Rarely. A template belongs here only when:

1. It's a starting point a human should customize.
2. It's not safe for `dotclaude-sync` to touch after first copy.
3. It's per-developer or per-environment, not per-project.

Everything else belongs in `core/` or `stacks/` as normal tagged content.
