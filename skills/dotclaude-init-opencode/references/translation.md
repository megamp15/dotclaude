# Translation table — dotclaude → OpenCode

OpenCode's structure closely mirrors Claude Code's. Most content copies
over; the main work is re-shaping config files.

## OpenCode layout refresher

```
repo/
├── AGENTS.md                  # project rules + context (like CLAUDE.md)
├── opencode.jsonc             # main config
└── .opencode/
    ├── agents/                # subagent definitions (markdown with frontmatter)
    ├── command/               # slash commands (markdown with frontmatter)
    ├── instructions/          # rule files referenced from opencode.jsonc
    └── plugins/               # (optional) TS/JS plugins for hook-like behavior
```

Global equivalents live at `~/.config/opencode/` — we never touch those.

## `opencode.jsonc` structure

```jsonc
{
  "$schema": "https://opencode.ai/config.json",

  "instructions": [
    ".opencode/instructions/**/*.md"
  ],

  "permission": {
    "edit": "allow",
    "bash": {
      "git push --force*": "deny",
      "rm -rf /*": "deny",
      "chmod 777*": "deny",
      "curl * | sh": "deny",
      "git push": "ask",
      "*": "allow"
    },
    "webfetch": "allow"
  },

  "mcp": {
    "filesystem": {
      "type": "local",
      "command": ["npx", "-y", "@modelcontextprotocol/server-filesystem", "."]
    },
    "github": {
      "type": "local",
      "command": ["npx", "-y", "@modelcontextprotocol/server-github"],
      "environment": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "{env:GITHUB_PERSONAL_ACCESS_TOKEN}"
      }
    },
    "context7": {
      "type": "remote",
      "url": "https://mcp.context7.com/mcp",
      "headers": {
        "CONTEXT7_API_KEY": "{env:CONTEXT7_API_KEY}"
      }
    }
  }

  /* providers are intentionally omitted; user configures them per-env */
}
```

Notes:

- **JSONC** — comments allowed. Use them for `source:` tags on major sections.
- **`instructions:`** — glob list of markdown files loaded as context on every turn.
- **`permission.bash:`** — pattern-matched, ordered. More-specific patterns first, catch-all last.
- **`mcp:`** — slightly different shape than Claude Code's `.mcp.json`:
  - `type`: `"local"` for stdio-launched, `"remote"` for HTTP/SSE.
  - `command`: array (not single string).
  - `environment`: (not `env`).
  - Remote uses `url` + `headers`.
- **`providers:`** — left out; user supplies their own keys.

## Source-to-target mapping

### Agents

`core/agents/code-reviewer.md` (existing):

```markdown
---
source: core
name: code-reviewer
description: correctness, maintainability, real bugs
tools: [Read, Grep, Glob]
---

# code-reviewer

(system prompt body)
```

Renders to `.opencode/agents/code-reviewer.md`:

```markdown
---
source: core/agents/code-reviewer.md
description: correctness, maintainability, real bugs
mode: subagent
tools:
  read: true
  grep: true
  glob: true
  edit: false
  bash: false
---

# code-reviewer

(system prompt body — verbatim)
```

Key transforms:

- `source:` — pointed at the upstream file (enables future `dotclaude-sync-opencode`).
- `mode: subagent` — tells OpenCode this is a subagent, not the primary agent.
- `tools:` — convert array form (`[Read, Grep, Glob]`) to map form (`{read: true, grep: true, ...}`), explicitly denying anything not listed (`edit: false, bash: false`). Verify against OpenCode's current schema; the shape has varied.

### Slash commands (skills)

`core/skills/pr-review/SKILL.md` renders to `.opencode/command/pr-review.md`:

```markdown
---
source: core/skills/pr-review/SKILL.md
description: run multi-agent PR review (correctness, security, performance, docs) with severity-labeled findings
agent: build  # or whatever default; can be omitted
---

(SKILL.md body verbatim, followed by inlined references)

## References

### Checklist

<contents of references/checklist.md>

### Diff scoping

<contents of references/diff-scoping.md>
```

OpenCode supports `$ARGUMENTS` and `!` prefix for shell-exec in command templates. Use them when the source skill calls for shell context:

```markdown
Current branch: !`git branch --show-current`
Current diff: !`git diff HEAD~1`
```

Most dotclaude skills don't need this — the agent handles git on demand — but `ship`, `commit`, `pr-review` can benefit. Keep conservative; don't add shell interpolation to skills that weren't authored with shell context in mind.

### Rules

`core/rules/code-quality.md` renders to `.opencode/instructions/code-quality.md` with tags preserved:

```markdown
---
source: core/rules/code-quality.md
---

# Code quality

(body verbatim)
```

Stack rules go to `.opencode/instructions/<stack>-<name>.md`:

- `stacks/lang/python/rules/python-style.md` → `.opencode/instructions/python-style.md`
- `stacks/infra/docker/rules/dockerfile-best-practices.md` → `.opencode/instructions/docker-dockerfile-best-practices.md`

(Use stack prefix when the bare name could collide across stacks; `python-style.md` is unique, `docker-dockerfile-best-practices.md` prefix is explicit for clarity.)

All instructions files are globbed into `opencode.jsonc`:

```jsonc
{
  "instructions": [
    ".opencode/instructions/**/*.md"
  ]
}
```

### AGENTS.md

Same layout as in Cursor's renderer; OpenCode reads it natively. Key difference: OpenCode also loads the `instructions:` globbed files, so AGENTS.md can be leaner than Cursor's equivalent (which carried everything not in `.mdc`).

Target structure:

```markdown
# <project-name>

<one-liner>

## Stacks

- python
- docker

<!-- project-start -->
## Project context

<interview answers>
<!-- project-end -->

## Working principles

<condensed from core/CLAUDE.base.md — 30-50 lines>

## Available subagents

Invoke with OpenCode's subagent syntax (e.g., `@code-reviewer` in chat):

- `code-reviewer` — correctness, maintainability, real bugs
- `security-reviewer` — exploitable issues, OWASP-aligned
- ...

## Available commands

Invoke with slash (e.g., `/pr-review`):

- `/pr-review` — multi-agent PR review
- `/debugging` — methodical bug hunt or advanced debugging escalation
- ...

---

*Rendered from [dotclaude](https://github.com/megamp15/dotclaude). Run `dotclaude-init-opencode` to refresh.*
```

Full rule bodies live in `.opencode/instructions/` — don't duplicate them here. AGENTS.md is for orientation, not content.

### Hooks

By default: skip, warn.

Optional: OpenCode has a **plugin system** (TS/JS files in `.opencode/plugins/` or `~/.config/opencode/plugins/`) that can observe and react to events. This is technically a hook analog, but:

- Plugins are code, not shell scripts. Not a 1:1 port.
- Installing them silently is surprising.
- Most dotclaude hooks (format-on-save, block-dangerous-commands) overlap with OpenCode's built-in `permission` system and its formatter integration.

Recommendation — split by hook:

| Hook | OpenCode equivalent |
|---|---|
| `block-dangerous-commands.sh` | `permission.bash.deny` patterns (rendered) |
| `protect-files.sh` | `permission.edit` pattern deny list if supported; otherwise prose guardrail |
| `scan-secrets.sh` | No equivalent. Recommend `gitleaks` as pre-commit hook. |
| `warn-large-files.sh` | No equivalent. Skip. |
| `session-start.sh` | `AGENTS.md` prose + OpenCode's built-in context. Skip the hook. |
| `notify.sh` | OpenCode's own notification. Skip. |
| `format-on-save.sh` | OpenCode's `formatter` config if present, or editor integration. Skip the hook. |
| `auto-test.sh` | Skip — prefer `/testing` in tdd mode to drive this. |
| `context-recovery.sh` | Skip — OpenCode handles its own context management. |

So most hooks are absorbed into `permission` + `AGENTS.md`, not rendered.

## MCP

Same source-of-truth as Claude Code renders; different output schema.

Transform each MCP entry:

**Local stdio** (source from `core/mcp/mcp.partial.json`):

```jsonc
{
  "_comment": "source: core/mcp",
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "."]
    }
  }
}
```

**Renders to** (inside `opencode.jsonc`):

```jsonc
"mcp": {
  "filesystem": {
    "type": "local",
    "command": ["npx", "-y", "@modelcontextprotocol/server-filesystem", "."]
  }
}
```

**HTTP remote** (e.g., `core/mcp/optional/context7.mcp.json`):

```jsonc
"mcp": {
  "context7": {
    "type": "remote",
    "url": "https://mcp.context7.com/mcp",
    "headers": {
      "CONTEXT7_API_KEY": "{env:CONTEXT7_API_KEY}"
    }
  }
}
```

Env-var syntax: `${VAR}` (Claude Code style) becomes `{env:VAR}` (OpenCode style).

Merge order — same as Claude Code init:
1. `core/mcp/mcp.partial.json` (always-on).
2. `core/mcp/optional/*.mcp.json` (only those opted in during interview).
3. `stacks/<category>/<s>/mcp/*.mcp.json` for every active stack.
4. Result deep-merged into `opencode.jsonc`'s `mcp:` section.

Keep `_comment` as a JSONC line comment above each MCP entry (OpenCode accepts comments in `.jsonc`):

```jsonc
"mcp": {
  // source: core/mcp — filesystem access for reads
  "filesystem": { ... },

  // source: core/mcp/optional/context7.mcp.json — library docs
  "context7": { ... },

  // source: stacks/python/mcp/<...> — Python-specific
  "python-docs": { ... }
}
```

## Permissions — detailed render

`core/settings.partial.json` contains:

```json
{
  "permissions": {
    "allow": [
      "Bash(git status)",
      "Bash(git diff*)",
      "Bash(git log*)",
      "Bash(git branch*)"
    ],
    "deny": [
      "Bash(git push --force*)",
      "Bash(git reset --hard*)",
      "Bash(rm -rf /*)",
      "Bash(chmod 777*)",
      "Bash(curl * | sh)",
      "Bash(curl * | bash)",
      "Write(**/.env)",
      "Write(**/id_rsa*)"
    ]
  }
}
```

Translate to OpenCode's `permission:`:

```jsonc
"permission": {
  "edit": "allow",
  "bash": {
    "git push --force*": "deny",
    "git reset --hard*": "deny",
    "rm -rf /*": "deny",
    "chmod 777*": "deny",
    "curl * | sh": "deny",
    "curl * | bash": "deny",
    "git push": "ask",
    "git status": "allow",
    "git diff*": "allow",
    "git log*": "allow",
    "git branch*": "allow",
    "*": "allow"
  },
  "webfetch": "allow"
}
```

Key transforms:

- Strip `Bash(...)` wrapper.
- Map `Bash(X)` → `"X": "allow"` or `"deny"`.
- Add `"git push": "ask"` — safer default since we can't render all the `--no-force` positive checks. Asking before pushes is cheap.
- `Write(...)` patterns have no direct OpenCode equivalent — OpenCode's `edit` is `allow`/`ask`/`deny` at tool level, not per-file. Include forbidden paths as prose in `AGENTS.md` guardrails.
- End with `"*": "allow"` so any unlisted command proceeds (matching Claude Code's implicit behavior).

**Order matters** — OpenCode processes patterns top-to-bottom; first match wins. Render deny list first, then narrow allows, then catch-all.

## Character budgets

OpenCode doesn't impose hard caps like Copilot. Keep:

- `AGENTS.md` ≤ 4000-5000 chars (orientation, not content).
- Individual instruction files bounded by their source (~200-500 lines).
- `opencode.jsonc` — as long as it needs to be.

## Report

```
OpenCode renderer summary
=========================
Rendered:
  opencode.jsonc                                   (1 file)
  AGENTS.md                                        (1 file)
  .opencode/agents/                                (6 files)
  .opencode/command/                               (10 files)
  .opencode/instructions/                          (14 files)

Skipped (not cleanly portable):
  Hooks: 9 hooks skipped. 2 behaviors absorbed into permission.bash
    (block-dangerous-commands → deny patterns; protect-files → prose guardrail).
  Templates: user-scope config is OpenCode's own.

Permission list:
  deny: 6 patterns
  ask:  1 pattern
  allow: 5 patterns + catch-all

MCP servers rendered: 4
  core: filesystem, fetch, git, memory, sequential-thinking, time
  optional (opted in): context7
  stacks (python): (none selected)
```
