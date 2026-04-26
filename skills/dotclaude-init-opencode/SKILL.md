---
name: dotclaude-init-opencode
description: Render dotclaude's canonical core + stack sources into OpenCode's native config (opencode.jsonc, AGENTS.md, .opencode/agents/, .opencode/command/). OpenCode has the richest feature set after Claude Code — real subagents, slash commands, MCP, ask/allow/deny permissions.
triggers: dotclaude-init-opencode, render opencode, setup opencode, opencode.jsonc, /dotclaude-init-opencode
---

# dotclaude-init-opencode

OpenCode (opencode.ai, the SST team's open-source agent) is the target
with the **highest feature parity** to Claude Code. Subagents map to
subagents; slash commands map to skills; MCP maps directly; permissions
have the same `ask`/`allow`/`deny` model. Hooks and some skill-references
don't translate cleanly, but most dotclaude content survives intact.

## When to use

- Project uses OpenCode as the primary agent.
- Team is multi-agent and wants OpenCode + Claude Code parity.
- Refreshing OpenCode config after upstream dotclaude changes.

## What this produces

```
my-project/
├── AGENTS.md                            # rules + project context (OpenCode reads this natively)
├── opencode.jsonc                       # main config: providers, MCP, permissions, instructions paths
└── .opencode/
    ├── agents/
    │   ├── code-reviewer.md
    │   ├── security-reviewer.md
    │   ├── performance-reviewer.md
    │   ├── doc-reviewer.md
    │   ├── architect.md
    │   ├── code-searcher.md
    │   └── ts-reviewer.md               # (if stacks/node-ts is active)
    ├── command/
    │   ├── pr-review.md
    │   ├── debugging.md
    │   ├── ship.md
    │   ├── testing.md
    │   ├── refactor.md
    │   ├── commit.md
    │   ├── security.md
    │   └── hotfix.md
    └── instructions/                    # extra rule files referenced from opencode.jsonc
        ├── code-quality.md
        ├── testing.md
        ├── security.md
        ├── error-handling.md
        ├── database.md
        ├── observability.md
        ├── dependencies.md
        ├── documentation.md
        ├── git.md
        ├── design-patterns.md
        ├── software-principles.md
        ├── python.md                    # stack: python (if active)
        ├── docker.md                    # stack: docker (if active)
        └── terraform.md                 # stack: terraform (if active)
```

## What maps 1:1 or very close

| dotclaude | OpenCode | Fidelity |
|---|---|---|
| `core/agents/*.md` | `.opencode/agents/<name>.md` | **High** — real subagent system |
| `core/skills/*/SKILL.md` | `.opencode/command/<name>.md` | **High** — real slash commands with prompts |
| `core/rules/*.md` | `.opencode/instructions/<name>.md` referenced from `opencode.jsonc` `instructions:` | **High** — file list with globs |
| `core/settings.partial.json` permissions | `opencode.jsonc` `permission:` (`ask`/`allow`/`deny`) | **High** — same model |
| `core/mcp/**` merged | `opencode.jsonc` `mcp:` section | **High** — same MCP protocol |
| `core/CLAUDE.base.md` + stack CLAUDE + interview | `AGENTS.md` | **High** — AGENTS.md is the native project-context file |
| `core/hooks/*.sh` | (partial) OpenCode plugins / pre-commit | **Low** — OpenCode has a plugin system but it's not a 1:1 hook map. Skipped by default; optional install to `scripts/dotclaude-hooks/`. |
| `core/skills/<name>/references/*.md` | Included inline in command body, or referenced via path | **Medium** — commands can reference other files |
| `core/templates/*` | (skipped) | — OpenCode has user-scope global config |

## Workflow

1. **Resolve `DOTCLAUDE_HOME`.** Error if unset.
2. **Scan repo** — reuse `dotclaude-init/references/scanning.md`.
3. **Ask the invisibles** — reuse `dotclaude-init/references/interview.md`.
4. **Render:**
   - `opencode.jsonc` — assemble providers (keep empty/default; user fills in), permissions, MCP, instructions paths.
   - `.opencode/agents/` — one file per core + stack agent.
   - `.opencode/command/` — one file per core + stack skill.
   - `.opencode/instructions/` — one file per core + stack rule.
   - `AGENTS.md` — condensed working principles + project context + stack context.
5. **Warn** about hooks (not rendered by default).
6. **Report** — file list + what was skipped.

## Reference guide

| Topic | Reference | Load when |
|---|---|---|
| dotclaude → OpenCode concept map | `references/translation.md` | Step 4 |
| Scan logic (shared) | `../dotclaude-init/references/scanning.md` | Step 2 |
| Interview bank (shared) | `../dotclaude-init/references/interview.md` | Step 3 |

## Permissions — honest about the mapping

OpenCode's `permission` field supports `ask` | `allow` | `deny` at the
tool level, and `edit`, `bash`, and `webfetch` have pattern-based
granularity (similar-ish to Claude Code's `permissions.allow` /
`permissions.deny`).

Render approach:

```jsonc
{
  "permission": {
    "edit": "allow",
    "bash": {
      "git push": "ask",
      "git push --force*": "deny",
      "rm -rf /*": "deny",
      "rm -rf ~/*": "deny",
      "chmod 777*": "deny",
      "curl * | sh": "deny",
      "curl * | bash": "deny",
      "*": "allow"
    },
    "webfetch": "allow"
  }
}
```

Translate `core/settings.partial.json` `permissions.deny` → `bash:
"<pattern>": "deny"` entries. Translate `permissions.allow` → `bash:
"<pattern>": "allow"` entries, with catch-all `"*": "allow"` at the end
so unlisted commands aren't blocked.

Verify against OpenCode's docs for the exact pattern syntax at render
time — the model has matured and may accept or require slight
adjustments.

## Refresh / sync

Re-running this skill regenerates everything under `.opencode/`
and `opencode.jsonc`. Files outside that tree (including `AGENTS.md` and
custom agents/commands the user added) follow the drift-handling model
from `dotclaude-sync`:

- Files in `.opencode/agents/` and `.opencode/command/` and `.opencode/instructions/` matching names we rendered → re-rendered.
- Files in those directories not matching our renders → left alone (project-owned).
- `AGENTS.md` → project-section between `<!-- project-start -->` / `<!-- project-end -->` preserved.
- `opencode.jsonc` → deep-merged same as dotclaude-sync handles `settings.json`. User-added MCP servers, providers, and permissions survive.

Since OpenCode subagents and commands live as individual markdown files
(same shape as dotclaude), adding `source:` frontmatter is natural —
**and we do**. Future `dotclaude-sync-opencode` can use the same drift
logic as `dotclaude-sync`. (Not implemented yet; noted as future work.)

## Do not

- Do not overwrite user-added files in `.opencode/agents/` or `.opencode/command/` that have no `source:` tag.
- Do not write personal provider API keys into `opencode.jsonc`. Use env-var references (`"apiKey": "{env:OPENAI_API_KEY}"`) or leave the providers section empty for the user to fill.
- Do not render hooks as OpenCode plugins without explicit opt-in — plugin code running on every agent action is a large surface.
- Do not delete `.opencode/tui.json` or other user-scope-ish files.
- Do not assume OpenCode's schema is frozen — it's evolving. Warn if the target's installed OpenCode version is older than what this skill expects.
