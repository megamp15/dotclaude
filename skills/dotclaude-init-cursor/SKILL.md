---
name: dotclaude-init-cursor
description: Render dotclaude's canonical core + stack sources into Cursor's native config (.cursor/rules/*.mdc, .cursor/mcp.json, AGENTS.md). Use when setting up or refreshing a repo for Cursor users.
triggers: dotclaude-init-cursor, render cursor, setup cursor rules, .cursor/rules, .mdc, cursor mcp, /dotclaude-init-cursor
---

# dotclaude-init-cursor

Canonical content lives in `core/` and `stacks/`. This skill renders it
into Cursor's native format so a Cursor user gets the same rules,
conventions, and MCP access as a Claude Code user — within the limits of
what Cursor supports.

## When to use

- Project uses Cursor instead of (or in addition to) Claude Code.
- Refreshing Cursor config after upstream `core/` or `stacks/` changes.
- Testing: you want to see how dotclaude translates without committing to Cursor.

## What this produces

```
my-project/
├── .cursor/
│   ├── rules/
│   │   ├── 00-base.mdc                  # alwaysApply: true  (core working principles)
│   │   ├── 10-code-quality.mdc          # alwaysApply: true
│   │   ├── 10-security.mdc              # alwaysApply: true
│   │   ├── 20-python-style.mdc          # globs: ["**/*.py"]  (from stacks/python)
│   │   ├── 30-pr-review.mdc             # alwaysApply: false, description-triggered  (from skills/)
│   │   ├── 30-debugging.mdc             # alwaysApply: false, description-triggered
│   │   └── 40-code-reviewer.mdc         # alwaysApply: false, manual  (from agents/)
│   └── mcp.json                         # rendered from core + stack MCP configs
└── AGENTS.md                             # universal project context (Cursor reads this too)
```

## What Cursor does NOT support (and how we handle it)

| dotclaude concept | Cursor equivalent | Handling |
|---|---|---|
| **Hooks** (`core/hooks/*.sh`) | None | Skipped with a warning. Optionally rendered as git pre-commit hooks or a `scripts/` directory the user runs manually. |
| **Subagents** (`core/agents/*.md`) | Partial — via manual rules | Rendered as manual-mode rules (`alwaysApply: false`, no `globs`, no `description`) invoked via `@<rule-name>`. They become "this is the reviewer persona" prompts you summon. |
| **Skill folders with `references/`** | None | Only the top-level `SKILL.md` renders into a rule. References are concatenated into a single appended section or skipped (configurable). |
| **Permission allow/deny lists** | Partial — Privacy Mode + MCP scope | Cursor doesn't gate tool calls per-pattern. Documented as prose in `AGENTS.md`. |
| **Templates** (`CLAUDE.local.md`, `settings.local.json`) | Cursor user settings (IDE-scoped) | No rendering; the user manages personal overrides via Cursor's own settings. |

See `references/translation.md` for the full mapping.

## Workflow

1. **Resolve `DOTCLAUDE_HOME`.** Error if unset.
2. **Scan the repo** — reuse the logic from `dotclaude-init/references/scanning.md` (detect stacks, frameworks, MCPs). The classification is format-agnostic.
3. **Ask the invisibles** — reuse `dotclaude-init/references/interview.md`. Same questions; different output location.
4. **Render** — per `references/translation.md`:
   - Every `core/rules/*.md` with `alwaysApply: true` in frontmatter → `.cursor/rules/10-<name>.mdc` with `alwaysApply: true`.
   - Every stack rule with `globs:` → `.cursor/rules/20-<name>.mdc` preserving the globs.
   - Every skill → `.cursor/rules/30-<skill>.mdc` with `alwaysApply: false` + description (auto-triggered by intent).
   - Every agent → `.cursor/rules/40-<agent>.mdc` with no `description`/`globs`/`alwaysApply` (manual-invoke only).
   - Merged MCP config → `.cursor/mcp.json`.
   - Merged CLAUDE.md → `AGENTS.md` (without Claude-specific sections).
5. **Warn** about what didn't translate (hooks, unsupported permission patterns, specific references/).
6. **Report** — list every file written, every concept skipped with reason.

## Reference guide

| Topic | Reference | Load when |
|---|---|---|
| Cursor's `.mdc` file format | `references/mdc-format.md` | Step 4, authoring rules |
| dotclaude → Cursor concept map | `references/translation.md` | Step 4, translating each source |
| Scan logic (shared) | `../dotclaude-init/references/scanning.md` | Step 2 |
| Interview bank (shared) | `../dotclaude-init/references/interview.md` | Step 3 |

## File-name prefix convention

Cursor rules apply in alphabetical order when multiple match; the digit
prefix gives a predictable loading sequence:

- `00-` — base / meta (always first, shortest, sets tone)
- `10-` — universal rules (always apply; from `core/rules/`)
- `20-` — stack rules (glob-scoped; from `stacks/*/rules/`)
- `30-` — skills (intent-triggered)
- `40-` — agents/personas (manual invoke)

This isn't enforced by Cursor — it's readability.

## Refresh / sync

This skill is the equivalent of `dotclaude-init` for Cursor users.
There's no `dotclaude-sync-cursor` (yet) — re-running this skill
regenerates files from current upstream. Cursor's `.cursor/rules/`
doesn't use `source:` tags (the `.mdc` format doesn't expose arbitrary
frontmatter cleanly), so drift detection is cruder:

- Files in `.cursor/rules/` that match our prefix convention (`00-`…`40-`) → eligible for re-render.
- Everything else in `.cursor/rules/` → project-owned, never touched.

If a user manually edited a dotclaude-rendered `.mdc`, re-rendering will overwrite it. Warn on first run. Future enhancement: embed a `<!-- source: ... -->` HTML comment in the `.mdc` body for a tag we can detect.

## Do not

- Do not delete files in `.cursor/rules/` that don't match our naming prefix. Those are hand-authored by the user.
- Do not render hooks as anything that runs automatically without explicit user opt-in.
- Do not translate the subagent system prompts as if they were `alwaysApply: true` rules — that pollutes every prompt with reviewer personas.
- Do not write `.cursorignore` or `.cursorindexignore`. The user manages those.
- Do not touch Cursor's user-scope settings (`~/.cursor/`). This skill is project-scope only.
