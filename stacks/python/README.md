# Python stack

Layer that adds Python-specific configuration on top of the dotclaude core.

## Contents

- `CLAUDE.stack.md` — rules and guidance appended to the target's CLAUDE.md
- `settings.partial.json` — permissions and hooks for `uv`, `pytest`, `ruff`, `mypy`
- `rules/` — Python style and idiom rules
- `skills/` — Python-specific skills (pytest debugging, uv deps)
- `agents/` — Python-focused review agent
- `hooks/` — hook scripts referenced by `settings.partial.json`

## How it gets used

The `/dotclaude-init` skill merges this stack into a target repo's `.claude/`:

- `rules/`, `skills/`, `agents/` files are copied flat
- `settings.partial.json` is deep-merged into the target's `settings.json`
- `CLAUDE.stack.md` is appended as a section inside the target's `CLAUDE.md`
- `hooks/` scripts are copied to the target's `.claude/hooks/`

Per-project customizations live in the target's `.claude/` and are never
overwritten by future `dotclaude sync` runs — only files traceable back
to core/ or this stack are refreshed.
