---
name: dotclaude-init-copilot
description: Render dotclaude's canonical core + stack sources into GitHub Copilot's repository custom instructions (.github/copilot-instructions.md + .github/instructions/*.instructions.md). Use when setting up or refreshing a repo for Copilot users.
triggers: dotclaude-init-copilot, render copilot, setup copilot instructions, .github/copilot-instructions, copilot custom instructions, /dotclaude-init-copilot
---

# dotclaude-init-copilot

Renders `core/` + `stacks/` into GitHub Copilot's native config. The
target is more constrained than Claude Code or Cursor — no hooks, no
subagents, no skills system, no MCP in all Copilot contexts. What
translates well: rules, conventions, guardrails.

## When to use

- Project's AI assistance is GitHub Copilot in VS Code / VS / JetBrains / Copilot CLI.
- Team uses Copilot code review and wants project-specific review criteria.
- Refreshing Copilot instructions after upstream dotclaude changes.

## What this produces

```
my-project/
├── .github/
│   ├── copilot-instructions.md           # repo-wide, always applies
│   └── instructions/
│       ├── python.instructions.md        # applyTo: "**/*.py"
│       ├── typescript.instructions.md    # applyTo: "**/*.ts,**/*.tsx"
│       ├── docker.instructions.md        # applyTo: "**/Dockerfile,**/docker-compose*.y*ml"
│       ├── terraform.instructions.md     # applyTo: "**/*.tf"
│       └── code-review.instructions.md   # used by Copilot code review
└── AGENTS.md                              # VS Code Copilot reads this too (as of late 2025)
```

## What Copilot does NOT support

| dotclaude concept | Copilot equivalent | Handling |
|---|---|---|
| **Hooks** | None | Skipped. Documented in top-of-file header. |
| **Subagents / agents** | None | Merged into prose — "when reviewing code, consider these angles…" |
| **Skill auto-invocation** | None | Skills with `alwaysApply: false` are still rendered, but the triggering is manual — user has to type the intent in chat. |
| **MCP servers** | Limited — Copilot Chat has some MCP support (recent) | Documented, not auto-rendered. If user opts in, we'll note which MCPs they'd configure. |
| **Permission allow/deny lists** | None | Prose guardrails only. |
| **References hierarchy** (SKILL + references/) | None | Skills are flattened into single instruction files. |
| **Manual-invocation rules** (like Cursor's `@agent`) | None | Agent personas become prose sections in the main instructions file. |

See `references/translation.md` for the full mapping.

## Character budget discipline

Copilot code review **only reads the first 4000 characters** of an
instruction file. This is the tightest constraint we hit.

- The main `copilot-instructions.md` is limited only by usefulness; keep it focused.
- The `code-review.instructions.md` **must** fit in 4000 chars — render it as a tight checklist, not a tutorial.
- Path-specific instructions don't have the 4000-char limit for general completion, but still — Copilot rewards brevity.

See `references/translation.md#character-budgets`.

## Workflow

1. **Resolve `DOTCLAUDE_HOME`.** Error if unset.
2. **Scan the repo** — reuse `dotclaude-init/references/scanning.md`. Stack detection drives which `.instructions.md` files get generated.
3. **Ask the invisibles** — reuse `dotclaude-init/references/interview.md`.
4. **Render:**
   - `core/CLAUDE.base.md` + interview project context → `.github/copilot-instructions.md`.
   - Stack CLAUDE + rules → one `.github/instructions/<stack>.instructions.md` per active stack.
   - Skills with value for review → merged into `code-review.instructions.md` (under 4000 chars).
   - Agents → condensed into prose sections in the main `copilot-instructions.md` under `## Review personas`.
5. **Warn** about what didn't translate (hooks, MCP, tool permissions, subagent-as-process).
6. **Write `AGENTS.md`** if not present — VS Code Copilot reads it.
7. **Report** — file list + dropped concepts + character counts for files near limits.

## Reference guide

| Topic | Reference | Load when |
|---|---|---|
| dotclaude → Copilot concept map | `references/translation.md` | Step 4 |
| Scan logic (shared) | `../dotclaude-init/references/scanning.md` | Step 2 |
| Interview bank (shared) | `../dotclaude-init/references/interview.md` | Step 3 |

## Refresh / sync

Re-running this skill is the refresh. Files under `.github/instructions/`
matching our naming (one `.instructions.md` per known stack + `code-review`)
are regenerated; other files in that directory are left alone.

The main `copilot-instructions.md` is trickier: if the user edited it,
we don't want to clobber. Treat it like CLAUDE.md:

- Look for `<!-- project-start -->` and `<!-- project-end -->` markers.
- If present: re-render everything outside the markers; preserve content between.
- If missing on first run: render with markers present so future runs work.
- If missing after the user removed them: warn, skip re-render of this file, suggest they add markers back.

## Do not

- Do not write anything outside `.github/` and `AGENTS.md`.
- Do not add executable scripts anywhere (hooks → warned, never installed).
- Do not exceed 4000 characters in `code-review.instructions.md` — if the rendered content is over, truncate and warn.
- Do not write organizational custom instructions (that's `.github/` at the org level, not repo level). This skill is repo-scope only.
- Do not touch `.github/workflows/` — those are GitHub Actions, a different system.
