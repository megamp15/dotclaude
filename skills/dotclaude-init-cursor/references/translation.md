# Translation table — dotclaude → Cursor

How each kind of dotclaude source becomes Cursor-native content.
Deterministic: same inputs, same `.cursor/` output.

## Source-to-target mapping

| dotclaude source | Cursor target | Activation | Notes |
|---|---|---|---|
| `core/CLAUDE.base.md` | `AGENTS.md` (top section) + `.cursor/rules/00-base.mdc` (summary) | always | AGENTS.md has full text; 00-base.mdc is a 50-line boiled-down version for `alwaysApply: true` |
| `core/rules/*.md` (alwaysApply: true) | `.cursor/rules/10-<name>.mdc` | `alwaysApply: true` | One-to-one copy of body; frontmatter regenerated |
| `core/rules/*.md` (alwaysApply: false, triggers) | `.cursor/rules/10-<name>.mdc` | intelligent (description only) | `triggers:` concatenated into `description:` |
| `stacks/<s>/CLAUDE.stack.md` | `AGENTS.md` (stack section) | always (via AGENTS.md) | Same content, rendered under `## Stack: <s>` heading |
| `stacks/<s>/rules/*.md` (alwaysApply: true) | `.cursor/rules/20-<s>-<name>.mdc` | `alwaysApply: true` + globs | Inherits globs from source frontmatter if present, else stack's default globs |
| `stacks/<s>/rules/*.md` (with globs) | `.cursor/rules/20-<s>-<name>.mdc` | globs | Pass through the source's globs |
| `core/skills/<name>/SKILL.md` | `.cursor/rules/30-<name>.mdc` | intelligent | `description:` from SKILL's `description:` field |
| `core/skills/<name>/references/*.md` | appended to `30-<name>.mdc` OR skipped | — | See "References handling" below |
| `stacks/<s>/skills/<name>.md` (flat skill) | `.cursor/rules/30-<s>-<name>.mdc` | intelligent (+globs for stack) | |
| `core/agents/<name>.md` | `.cursor/rules/40-<name>.mdc` | manual (`@<name>`) | Body preserved; described as a persona to invoke |
| `stacks/<s>/agents/<name>.md` | `.cursor/rules/40-<s>-<name>.mdc` | manual | |
| `core/hooks/*.sh` | (skipped) | — | Warn. Optional: write to `scripts/dotclaude-hooks/` for manual use. |
| `stacks/<s>/hooks/*.sh` | (skipped) | — | Same |
| `core/mcp/mcp.partial.json` + opted optionals + stack MCPs | `.cursor/mcp.json` | — | Deep-merge same rules; strip `_comment` |
| `core/mcp/skills/<name>/SKILL.md` | `.cursor/rules/30-mcp-<name>.mdc` | intelligent | Only if MCP opted in |
| `core/templates/*.example` | (skipped) | — | Cursor has its own user-scope settings |
| `core/settings.partial.json` (permissions) | `AGENTS.md` (guardrails section) | — | Rendered as prose, not enforced |

## Rule body handling

Most rule bodies transfer directly. Adjustments:

### Strip dotclaude-specific frontmatter

Our rules carry:

```yaml
---
source: core
name: code-quality
description: ...
alwaysApply: true
triggers: ...
---
```

For Cursor, we regenerate frontmatter cleanly:

```yaml
---
description: code-quality — universal code quality rules
alwaysApply: true
---
```

Drop: `source`, `name`, `triggers`. `description` is constructed from the source's `name` + the source's `description`.

### Preserve body exactly

The markdown body under the frontmatter transfers byte-for-byte. No rewording. Cursor reads markdown; our content is markdown; no translation needed.

### Translating `triggers:` to `description:`

Some dotclaude rules use `triggers:` (a bag of keywords) to help the agent decide when to load. Cursor has no direct equivalent; its semantic match is purely over `description`. Combine:

```yaml
# source (dotclaude)
description: async patterns for Python services
triggers: asyncio, uvloop, asyncpg, httpx, starlette

# rendered (Cursor)
description: async patterns for Python services — asyncio, uvloop, asyncpg, httpx, starlette
```

The trigger words end up in the description. Inelegant but effective for semantic match.

## Agents — rendering as personas

A dotclaude agent (`core/agents/code-reviewer.md`) is a system prompt
meant to be summoned via `Task`. Cursor has no subagent. We render it
as a **manual-activation rule** the user invokes via `@code-reviewer`:

```mdc
---
# no alwaysApply, no description, no globs → manual only
---

# code-reviewer persona

(Body of the agent's system prompt goes here verbatim. User invokes this
by typing `@code-reviewer` in a Cursor chat, which loads it into the
turn's context.)
```

Users invoke as:

```
@code-reviewer review this diff
```

Caveats:

- In Cursor, this rule becomes *additional context* on the current conversation, not a separate subprocess. The main model still handles the reply. Behavior is close-enough to subagent-style review but context is shared.
- No way to enforce tool restrictions (the subagent's `tools:` field is meaningless in Cursor).
- Long agent bodies bloat the context on invocation. Keep agent bodies lean; dotclaude's already are.

## References handling for skills

A dotclaude skill often has `SKILL.md` plus `references/*.md`. Cursor's
`.mdc` is a single file. Two rendering options per skill:

### Option A — single file, references inlined (default)

Render as one `.mdc` with the references appended under `## References`:

```mdc
---
description: pr-review — run multi-agent review
---

# pr-review
(SKILL.md body)

## References

### checklist

(contents of references/checklist.md)

### diff-scoping

(contents of references/diff-scoping.md)
```

Pros: everything is there when the rule loads.
Cons: rules get fat; some skills have references > 500 lines combined.

### Option B — single file, references summarized (for large skills)

When total rendered content would exceed ~500 lines:

- Include `SKILL.md` body in full.
- For each reference, include its title, first two paragraphs, and a path pointer: `(full reference: dotclaude-sources/skills/pr-review/references/checklist.md)`.
- Warn that the references were abridged.

### Decision heuristic

- `SKILL.md` + references ≤ 500 lines → Option A.
- Otherwise → Option B.

(Config knob: `DOTCLAUDE_CURSOR_SKILL_MODE=inline|summary` lets the user force one.)

## MCP rendering

Read every MCP config file that would go into a Claude Code project (core always-on + opted-in optionals + stack optionals). Deep-merge the `mcpServers` maps using the same rules as init's merge logic. Write to `.cursor/mcp.json`.

One adjustment:

- **Strip `_comment`** fields from each MCP entry before writing. Cursor logs a warning on unknown top-level fields; `_comment` inside a server entry is tolerated but ugly.
- **Keep env-var references.** `${GITHUB_PERSONAL_ACCESS_TOKEN}`-style interpolations work in both systems.

## `AGENTS.md` composition

Target structure:

```markdown
# <project name>

<one-sentence project description, from interview>

## Stacks

- python
- docker

## Project context

<interview answers: owners, rate limits, sensitive paths, etc.>

## Working principles

<condensed version of core/CLAUDE.base.md — the universal working rules>

## Stack: python

<core content from stacks/python/CLAUDE.stack.md>

## Stack: docker

<core content from stacks/docker/CLAUDE.stack.md>

## Guardrails

<rendered prose version of permissions: "do not run force push, do not run chmod 777, do not curl | sh, etc.">

## Available personas (manual invocation)

When you want a specialized review, invoke one of these by name:

- `@code-reviewer` — correctness, maintainability, real bugs
- `@security-reviewer` — exploitable issues, OWASP-aligned
- `@ts-reviewer` — TypeScript-specific (stack: node-ts)
- ...

## Available workflows (intent-triggered or manual)

- `@pr-review` — multi-agent PR review
- `@debug-fix` — methodical bug hunt
- `@hotfix` — emergency production-change flow
- ...

---

*This file is rendered from [dotclaude](https://github.com/megamp15/dotclaude)
sources. To update: run `dotclaude-init-cursor` from inside this repo.*
```

**Guardrails section** is special: Cursor can't enforce the deny list at the IDE level, but including it as prose means the model reads it and honors it in most cases. It's defense-in-depth, not a hard block.

## Hooks — what to do

Three behaviors, user picks at init time:

1. **Skip (default)** — don't render. Print a warning listing which hooks were dropped and why.
2. **Scripts-only** — copy hook scripts to `scripts/dotclaude-hooks/` in the target repo. User wires them to git hooks, CI, or runs manually. A `README.md` in that dir explains each hook's intent.
3. **Git hooks** — wire `block-dangerous-commands.sh` and `protect-files.sh` as git pre-commit hooks (via husky / pre-commit / vanilla `.git/hooks`). Opt-in only; adds tooling.

Default is skip because silent install of scripts that run on commit is surprising. Always print:

```
The following dotclaude hooks are not supported by Cursor and were not rendered:
  - block-dangerous-commands.sh (Claude Code's Bash-matcher enforcement has no Cursor analog)
  - protect-files.sh (Claude Code's Write/Edit matcher has no Cursor analog)
  - scan-secrets.sh
  - warn-large-files.sh
  - session-start.sh
  - notify.sh
  - format-on-save.sh

To install them as git hooks or scripts anyway, re-run with
`HOOKS=scripts` or `HOOKS=git-hooks`.
```

## Drift and re-render

Re-running this skill overwrites all `.cursor/rules/*.mdc` files matching our naming prefixes (`00-`, `10-`, `20-`, `30-`, `40-`). Files with other names are left alone.

If users want per-file drift detection like `dotclaude-sync` offers for Claude Code, a future enhancement can embed an HTML comment:

```mdc
---
description: ...
---

<!-- source: core/rules/code-quality.md -->

# Body
```

HTML comments survive Cursor's parser and give us a source-tag we can grep. Not implemented today — re-render is the current refresh story.
