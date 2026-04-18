---
name: dotclaude-init-agents-md
description: Render dotclaude's canonical sources into a single AGENTS.md at repo root — the emerging open standard read by Cursor, Copilot (VS Code), OpenCode, Continue, Aider, and most coding agents. Use as a universal fallback when you don't know which agent the consumer is running.
triggers: dotclaude-init-agents-md, render agents.md, agents.md fallback, universal agent rules, /dotclaude-init-agents-md
---

# dotclaude-init-agents-md

The simplest, least lossy, most portable renderer. Produces a single
`AGENTS.md` at the repo root that follows the emerging open standard for
agent project-context files.

## When to use

- You don't know which agent (or agents) will read this repo.
- Multiple team members use different agents (one on Cursor, one on Copilot, one on Claude Code, one on OpenCode).
- You want a *baseline* that works everywhere, to be supplemented by agent-specific renderers where needed.
- Open-source repo where external contributors may use any agent.

## What this produces

```
my-project/
└── AGENTS.md
```

That's it. One file. No `.claude/`, no `.cursor/`, no `.github/instructions/`, no `.opencode/`.

## What AGENTS.md is

A neutral markdown file at the repo root that agents read for project
context. Format is unstructured prose with sensible sections; no
frontmatter, no special fields. It's a coordination point, not a config
file.

**Agents known to read it (April 2026):**

- Cursor — reads alongside `.cursor/rules/`
- GitHub Copilot in VS Code — reads alongside `.github/copilot-instructions.md`
- OpenCode — primary project-context file
- Claude Code — reads (equivalent to CLAUDE.md; Claude Code also reads CLAUDE.md natively)
- Continue, Aider, Cline, Zed — all read AGENTS.md

The format is informal; there's no enforced schema. This skill picks a
structure that's readable by humans and useful to agents.

## What this does NOT produce

This skill is intentionally minimal. It **does not**:

- Write `.claude/`, `.cursor/`, `.github/`, `.opencode/` — use the other renderers for those.
- Install hooks, MCP configs, or subagent definitions.
- Write anything outside repo root.

If you want more than `AGENTS.md`, compose with another renderer:

```
dotclaude-init-agents-md       # baseline — works everywhere
+ dotclaude-init-cursor        # for Cursor users — adds .cursor/rules/
+ dotclaude-init-claude-code   # (the original `dotclaude-init`) — adds .claude/
```

## What goes in AGENTS.md

Think of it as the *single thing* you'd hand a new contributor who has never seen the repo and might be using any AI assistant.

### Structure

```markdown
# <project-name>

<one-sentence description>

## Tech stack

- <stack 1>
- <stack 2>

## Getting started

<condensed: install, run, test>

<!-- project-start -->
## Project context

<interview answers: owners, rate limits, sensitive paths, audiences, goals>
<!-- project-end -->

## Working principles

<condensed from core/CLAUDE.base.md — universal principles>

## Code style

<condensed from core/rules/code-quality.md — bullets only>

## Testing

<condensed from core/rules/testing.md>

## Security

<condensed from core/rules/security.md>

## Error handling

<condensed from core/rules/error-handling.md>

## <Stack>-specific conventions

<one section per active stack, condensed from stacks/<stack>/CLAUDE.stack.md>

## Guardrails

Do NOT:

- Run `git push --force`, `git reset --hard`, or `git clean -fdx` without explicit user confirmation.
- Run `rm -rf` on large scopes.
- Commit `.env`, private keys, credentials, or any file containing secrets.
- Run `chmod 777` on anything.
- Pipe remote scripts to a shell (`curl ... | sh` / `| bash`).
- Paste API keys, tokens, or PII into responses.

## Available workflows

<condensed from core/skills/*/SKILL.md — one-liner per workflow>

- **PR review** — walk the diff; correctness → security → performance → docs; produce severity-labeled findings.
- **Debug and fix** — reproduce → isolate → minimal fix → regression test.
- **Hotfix** — smallest change to stop bleeding; rollback-first; schedule a proper fix PR after.
- **Ship** — logical commits → push → PR with summary.
- **TDD** — red → green → refactor.
- **Security audit** — focused review; OWASP-aligned checklist.

## Review lenses

<condensed from core/agents/*.md — prose only, one paragraph per persona>

- **Correctness & maintainability** — real bugs, dead code, error handling gaps. Don't nitpick formatting.
- **Security** — SQL/command injection, missing authz per-object, secrets in code/logs, unsafe deserialization, SSRF.
- **Performance** — measurable bottlenecks only. Ignore micro-optimization.
- **Architecture** — the edit-easy-change principle; is this the simplest design that solves the problem?
- **Documentation** — cross-reference against code; flag drift.

---

*This file is generated from [dotclaude](https://github.com/megamp15/dotclaude).
To refresh, run `dotclaude-init-agents-md` from this repo. For agent-specific config
(`.claude/`, `.cursor/`, `.github/instructions/`, `.opencode/`), run the matching renderer.*
```

### Character target

≤ 5000-6000 characters. Agents truncate or down-weight long files.

If rendered content exceeds the target, abridge in this order:

1. Cut verbose examples from rule sections — keep the principle bullet, drop the elaboration.
2. Collapse "Review lenses" to one-line summaries if persona bodies are long.
3. Fold "Testing" and "Security" into "Code style" under sub-bullets if both are short.
4. Keep the guardrails section intact — never cut.

## Workflow

1. **Resolve `DOTCLAUDE_HOME`.** Error if unset.
2. **Scan the repo** — reuse `dotclaude-init/references/scanning.md`. Stack detection drives which stack section gets added.
3. **Ask the invisibles** — reuse `dotclaude-init/references/interview.md`. Same questions, single-file output.
4. **Compose** AGENTS.md section by section.
5. **Enforce budget** — render, count chars, abridge if over ~6000, re-render.
6. **Write** to repo root. Respect `<!-- project-start -->` / `<!-- project-end -->` markers on refresh.
7. **Report** — file written, char count, abridgements applied.

## Refresh

Re-running is the refresh. Behaves like `dotclaude-sync`'s handling of
`CLAUDE.md`:

- Content between `<!-- project-start -->` and `<!-- project-end -->` is preserved verbatim.
- Everything else is regenerated from current upstream sources + interview answers.
- If markers are missing on first re-run (user deleted them), warn and skip the file. Suggest re-adding markers or running with `--overwrite` to restore defaults.

## Do not

- Do not include Claude-specific, Cursor-specific, or Copilot-specific instructions. This file is intentionally neutral.
- Do not reference paths like `.claude/rules/` or `.cursor/rules/` in the body — those tell *one* agent about another's files. AGENTS.md is the universal layer.
- Do not add a frontmatter block. AGENTS.md has no schema; frontmatter confuses some readers.
- Do not exceed ~6000 characters without abridgement.
- Do not write anywhere except repo-root `AGENTS.md`.

## Composing with other renderers

If the user runs multiple renderers, the output layers without conflict:

```
my-project/
├── AGENTS.md                            # from dotclaude-init-agents-md
├── .claude/                             # from dotclaude-init
├── .cursor/rules/                       # from dotclaude-init-cursor
├── .github/
│   ├── copilot-instructions.md          # from dotclaude-init-copilot
│   └── instructions/
├── opencode.jsonc                       # from dotclaude-init-opencode
└── .opencode/
```

Agent-specific renderers may write their own AGENTS.md too (Cursor and
OpenCode renderers do). **Rule**: if a later renderer would write
AGENTS.md and one already exists, it *reads the existing project-section
markers, preserves them, and re-renders the rest*. No renderer clobbers
another's project context.

Practically: run `dotclaude-init-agents-md` first (or last — doesn't
matter), and the others will cooperate.
