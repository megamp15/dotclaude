# Translation table — dotclaude → GitHub Copilot

How dotclaude's structured content becomes Copilot's simpler prose
instructions.

## Copilot's file format

Two types of file:

### Repo-wide: `.github/copilot-instructions.md`

```markdown
# Project instructions

<plain markdown — no frontmatter, no special fields>
```

- No frontmatter.
- Applies to every Copilot chat request in this repo.
- Read by Copilot code completion, Copilot Chat, Copilot code review (first 4000 chars of the total combined instruction context).

### Path-specific: `.github/instructions/<name>.instructions.md`

```markdown
---
applyTo: "**/*.ts,**/*.tsx"
---

<body: plain markdown>
```

- Frontmatter has `applyTo:` (required) — comma-separated glob list in a single string.
- Optional `excludeAgent:` to hide from specific Copilot modes (`code-review`, `coding-agent`).
- Activates when any file matching the glob is in the current context.

## Source-to-target mapping

| dotclaude source | Copilot target | Notes |
|---|---|---|
| `core/CLAUDE.base.md` (condensed) | `.github/copilot-instructions.md` (top section) | Pull universal working principles; drop Claude-specific directives |
| Interview project context | `.github/copilot-instructions.md` (middle, between markers) | Owners, rate limits, sensitive paths, description |
| `core/rules/*.md` (alwaysApply: true) | `.github/copilot-instructions.md` (appended sections) | These are universal; always-on is correct |
| `core/rules/*.md` (triggered) | `.github/copilot-instructions.md` (appended sections, brief) | Copilot has no intent trigger; include but mark as "applies when…" |
| `stacks/<s>/CLAUDE.stack.md` | `.github/instructions/<s>.instructions.md` (top) | `applyTo:` from stack's canonical globs |
| `stacks/<s>/rules/*.md` | `.github/instructions/<s>.instructions.md` (sections) | Same file; glob-scoped |
| `core/skills/<name>/SKILL.md` | `.github/copilot-instructions.md` (# Workflows section) | Each skill summarized in one short paragraph |
| `core/skills/<name>/references/*.md` | (skipped, but referenced) | Summary in workflows section; full content not included |
| `core/agents/<name>.md` | `.github/copilot-instructions.md` (# Review personas section) | Condensed from 100+ lines to one paragraph each |
| `core/skills/pr-review/` + agents | `.github/instructions/code-review.instructions.md` | Separate file for Copilot code review specifically |
| `core/hooks/*` | (skipped) | Listed as "not supported" in first-run report |
| `core/mcp/**` | (skipped by default) | Mentioned if user opts in |
| `core/CLAUDE.base.md` guardrails | `.github/copilot-instructions.md` (# Guardrails) | Prose-only; no enforcement |
| `core/templates/*` | (skipped) | Personal settings are Copilot-side (user config) |

## The main `copilot-instructions.md` structure

Target structure (all in one file):

```markdown
# <project-name> — Copilot instructions

<!-- rendered from dotclaude; project context is between project-start/end -->

<project one-liner from interview>

## Stack

<list: python, docker, ...>

<!-- project-start -->
## Project context

<interview answers: owners, rate limits, sensitive paths, etc.>
<!-- project-end -->

## Working principles

<condensed version of core/CLAUDE.base.md — keep under ~40 lines>

## Code style

<condensed from core/rules/code-quality.md — key bullets only>

## Testing

<condensed from core/rules/testing.md>

## Security

<condensed from core/rules/security.md>

## Error handling

<condensed from core/rules/error-handling.md>

## Guardrails (do not)

<rendered from permissions.deny + hook intent>

- Do not run `git push --force` or `git reset --hard` without explicit confirmation.
- Do not run `rm -rf` on large scopes.
- Do not commit `.env`, private keys, or files containing secrets.
- Do not paste API keys or tokens into responses.

## Review personas

When asked to review code, apply the right lens:

- **Correctness and maintainability**: check for real bugs, dead code, complex state, missing error paths. Don't nitpick formatting.
- **Security**: check for SQL/command injection, missing authZ checks, secrets in code, unsafe deserialization, SSRF.
- **Performance**: flag real bottlenecks with measurable impact; ignore micro-optimizations.
- **Documentation**: cross-reference docs against code; flag drift.

<!-- condensed from core/agents/*.md -->

## Workflows

When the user asks for these flows, follow the pattern:

- **PR review** — walk the diff, check each review lens, produce severity-labeled findings.
- **Debug and fix** — reproduce first, isolate, minimal fix, regression test.
- **Hotfix** — smallest change to stop bleeding, rollback-first mindset, regression test follow-up.
- **Ship** — commit in logical chunks, push, open PR with summary.
- **TDD** — red-green-refactor; start with a failing test.

<!-- condensed from core/skills/*/SKILL.md -->

---

*This file is generated from [dotclaude](https://github.com/megamp15/dotclaude).
To update: run `dotclaude-init-copilot` from inside this repo.*
```

**Length target**: aim for ~2500-3500 characters total. Copilot code review reads the first 4000, and this file also gets combined with any path-specific instructions in the same request. Keep it lean.

## Per-stack `instructions.md` files

One file per active stack. Example for Python:

```markdown
---
applyTo: "**/*.py,**/pyproject.toml,**/requirements*.txt"
---

# Python conventions

<body from stacks/python/CLAUDE.stack.md, condensed>

## Style

<from stacks/python/rules/python-style.md>

## Async patterns

<from stacks/python/rules/async-patterns.md>

## Testing (Python)

<relevant extracts from stacks/python/skills/python-pro/references/testing.md "Debugging a failing test" — tight bullets>

## Deps

<from stacks/python/skills/python-pro/references/packaging.md "Common uv workflows" — brief>
```

`applyTo` globs per stack:

| Stack | `applyTo:` value |
|---|---|
| python | `"**/*.py,**/pyproject.toml,**/requirements*.txt,**/*.pyi"` |
| node-ts | `"**/*.ts,**/*.tsx,**/*.js,**/*.jsx,**/*.mjs,**/*.cjs,**/package.json,**/tsconfig*.json"` |
| docker | `"**/Dockerfile,**/Dockerfile.*,**/docker-compose*.y*ml,**/compose*.y*ml,**/.dockerignore"` |
| terraform | `"**/*.tf,**/*.tfvars,**/.terraform.lock.hcl"` |
| github-actions | `".github/workflows/*.y*ml,.github/workflows/**/*.y*ml"` |
| react | `"**/*.tsx,**/*.jsx,**/src/components/**"` |
| kubernetes | `"**/*.yaml,**/*.yml"` — Copilot handles this poorly; narrow via filename convention if possible |

Stacks get only one instruction file each, not one per source rule. Keep it readable.

## `code-review.instructions.md` — special

Copilot code review has a **4000 character** limit. This file is the
project's review checklist. Structure:

```markdown
---
applyTo: "**"
---

# Code review checklist

## Correctness (highest priority)
- Bug: logic errors, off-by-one, null/undefined paths
- State: unnecessary, duplicated, or unsynchronized
- Error handling: missing, swallowed, or too broad

## Security
- SQL/command/template injection
- Missing auth / authorization per-object checks
- Secrets in code, logs, or URLs
- Unsafe deserialization (pickle, YAML unsafe load, Java serialization)
- SSRF in URL fetchers

## Testing
- New code has tests covering the critical path
- Tests don't sleep, don't rely on global state, don't test the framework

## Style (lowest priority — don't block on these)
- Naming: clarifies intent; no `foo`, `tmp`, `data2`
- Dead code and unreachable branches

## Do not flag
- Formatting differences (formatter's job)
- Personal style preferences not in the project's rules
- Defensive nitpicks ("consider adding a comment")
```

**Budget**: the above is ~800 chars. Keep the rendered version at or below 3500 to leave headroom if Copilot prepends context.

Render algorithm:

1. Build sections: Correctness / Security / Testing / Style / Do-not-flag.
2. Pull concise bullets from: `core/rules/code-quality.md`, `core/rules/security.md`, `core/rules/testing.md`, `core/agents/code-reviewer.md`, `core/agents/security-reviewer.md`.
3. Trim ruthlessly. A review checklist that doesn't fit isn't a checklist.

## `AGENTS.md` compatibility

VS Code Copilot reads `AGENTS.md` (alongside `.github/copilot-instructions.md`). Treat `AGENTS.md` as the canonical project-context file and lighter-weight; treat `copilot-instructions.md` as Copilot-specific.

Minimize duplication:

- **`AGENTS.md`** — project description, stacks, architecture, build/test/lint commands, guardrails.
- **`copilot-instructions.md`** — Copilot-focused: review lens, workflow patterns, personas-as-prose.

If both exist, Copilot combines them. Avoid repeating the same bullets in both — keep review-flavor content in `copilot-instructions.md` only.

## Character budgets (cheat sheet)

| File | Hard limit | Target |
|---|---|---|
| `.github/copilot-instructions.md` | — (truncation at ~4000 in code review contexts) | 2500-3500 |
| `.github/instructions/<stack>.instructions.md` | — | ≤3000 |
| `.github/instructions/code-review.instructions.md` | 4000 (code review) | ≤3500 |
| `AGENTS.md` | — | ≤4000 |

Over-budget? Truncate + warn:

```
copilot-instructions.md would be 5200 chars after render; target is 3500.
Dropped: verbose examples in Code style section.
To keep them, set DOTCLAUDE_COPILOT_BUDGET=max.
```

## What gets lost (be honest in the report)

At the end of rendering, print:

```
Copilot renderer summary
========================
Rendered:
  .github/copilot-instructions.md  (2847 chars)
  .github/instructions/python.instructions.md     (1923 chars)
  .github/instructions/docker.instructions.md     (1455 chars)
  .github/instructions/code-review.instructions.md (2104 chars)
  AGENTS.md                                         (3012 chars)

Skipped (not supported by Copilot):
  Hooks: block-dangerous-commands, protect-files, scan-secrets,
    warn-large-files, session-start, notify, format-on-save,
    auto-test, context-recovery
  Subagent tool-restriction (code-reviewer et al. merged into prose)
  MCP servers (Copilot Chat MCP is scoped differently; mention in chat setup)
  Skill references/ folders (content condensed into SKILL body)

Abridged (condensed for character budget):
  core/rules/observability.md → 8 bullets of 120
  core/skills/pr-review/references/* → skipped in favor of SKILL body only
```

Transparency makes the system trustworthy. Silent loss is corrosive.
