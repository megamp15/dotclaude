# dotclaude

A portable, layered AI-assistant setup you can drop into any project on any
tech stack. Universal principles live in `core/`; language- and
framework-specific pieces live in `stacks/`; anything unique to a particular
repo is captured from an interview at init time and stays project-owned.

Running the `dotclaude-init` skill inside a target repo produces a flat
`.claude/` directory shaped exactly the way Claude Code expects — merged
from the three layers, with `source:` tags on every file that came from
this repo so future syncs know what's safe to refresh.

**The same canonical content renders to other agents too.** Cursor
(`.cursor/rules/*.mdc`), GitHub Copilot (`.github/copilot-instructions.md`
+ path-scoped `.instructions.md`), OpenCode (`opencode.jsonc` +
`.opencode/`), and the universal `AGENTS.md` standard are all produced by
per-agent renderer skills that translate from the *same* `core/` and
`stacks/` sources. You author rules once; every agent on your team reads
them in its native format.

## What's in here

```
dotclaude/
├── core/                                # universal — applies to every project
│   ├── CLAUDE.base.md                   # universal instructions, principles, guardrails
│   ├── settings.partial.json            # universal permissions + hook registration
│   ├── rules/                           # code-quality, testing, security, git,
│   │                                    # design-patterns, software-principles,
│   │                                    # error-handling, database, observability,
│   │                                    # dependencies, documentation
│   ├── skills/                          # pr-review, debug-fix, ship, tdd,
│   │                                    # refactor, explain, test-writer, commit,`
│   │                                    # security-audit, hotfix
│   ├── agents/                          # code-reviewer, security-reviewer,
│   │                                    # performance-reviewer, doc-reviewer,
│   │                                    # architect, code-searcher
│   ├── hooks/                           # block-dangerous-commands, protect-files,
│   │                                    # scan-secrets, warn-large-files,
│   │                                    # session-start, notify, format-on-save,
│   │                                    # auto-test, context-recovery
│   ├── templates/                       # CLAUDE.local.md, settings.local.json  (one-shot copy)
│   └── mcp/                             # filesystem, fetch, git, memory,
│       ├── mcp.partial.json             # sequential-thinking, time  (always-on)
│       ├── optional/                    # github, context7, chrome-devtools (opt-in)
│       └── skills/                      # usage skill per MCP server
│
├── stacks/                              # layered — language + infra, pick all that apply
│   ├── python/                          # pyproject / requirements.txt
│   │   ├── CLAUDE.stack.md
│   │   ├── settings.partial.json
│   │   ├── rules/                       # python-style, async-patterns (MagicStack-flavored)
│   │   ├── skills/                      # pytest-debug, uv-deps
│   │   ├── agents/                      # python-reviewer
│   │   ├── hooks/                       # ruff-format
│   │   └── mcp/                         # postgres, sqlite (opt-in)
│   ├── node-ts/                         # package.json / tsconfig
│   │   ├── CLAUDE.stack.md
│   │   ├── settings.partial.json
│   │   ├── rules/                       # ts-style
│   │   ├── skills/                      # vitest-debug
│   │   ├── agents/                      # ts-reviewer
│   │   └── hooks/                       # format-prettier
│   ├── docker/                          # Dockerfile / docker-compose.yml
│   │   ├── CLAUDE.stack.md
│   │   ├── settings.partial.json
│   │   ├── rules/                       # dockerfile-best-practices, compose-patterns
│   │   └── skills/                      # container-debug
│   └── terraform/                       # *.tf / .terraform.lock.hcl
│       ├── CLAUDE.stack.md
│       ├── settings.partial.json
│       ├── rules/                       # state-safety
│       ├── skills/                      # tf-plan-review
│       └── hooks/                       # block-destroy-apply
│
└── skills/                              # the framework itself — one skill per workflow
    ├── dotclaude-init/                  # scan → interview → merge  (Claude Code target)
    │   ├── SKILL.md
    │   └── references/
    │       ├── scanning.md
    │       ├── interview.md
    │       └── merge.md
    ├── dotclaude-sync/                  # refresh upstream content, preserve project-owned
    │   ├── SKILL.md
    │   └── references/
    │       ├── classification.md
    │       ├── update-rules.md
    │       └── drift-handling.md
    │
    │                                    # per-agent renderers — same sources, different targets
    ├── dotclaude-init-cursor/           # → .cursor/rules/*.mdc + .cursor/mcp.json + AGENTS.md
    │   ├── SKILL.md
    │   └── references/
    │       ├── mdc-format.md
    │       └── translation.md
    ├── dotclaude-init-copilot/          # → .github/copilot-instructions.md + .github/instructions/
    │   ├── SKILL.md
    │   └── references/translation.md
    ├── dotclaude-init-opencode/         # → opencode.jsonc + .opencode/agents|command|instructions/
    │   ├── SKILL.md
    │   └── references/translation.md
    └── dotclaude-init-agents-md/        # → AGENTS.md only (universal fallback)
        └── SKILL.md
```

Stacks are **layered**, not exclusive. A Python API that runs in Docker
under Kubernetes infra managed by Terraform in a GitHub Actions pipeline
gets rules from `python`, `docker`, `kubernetes`, `terraform`, and
`github-actions` — all of them. Infra stacks don't conflict with language
stacks.

`core/` and `stacks/` are **sources**. They never get copied wholesale —
the init skill merges the pieces it needs into the target repo's
`.claude/` directory.

## How a target repo ends up looking

After running `dotclaude-init` inside a Python project, its `.claude/`
looks flat — exactly the shape Claude Code reads:

```
my-project/
├── .claude/
│   ├── CLAUDE.md             # core base + stack conventions + project context
│   ├── settings.json         # merged from core + stack
│   ├── agents/               # source-tagged copies
│   ├── hooks/                # source-tagged copies
│   ├── rules/
│   │   ├── python-style.md   # source: stacks/python
│   │   └── project.md        # project-owned (no source tag)
│   └── skills/               # source-tagged copies
└── .mcp.json                 # merged MCP config at repo root
```

## Layered merge model

```
          dotclaude (source)                target repo (.claude/)
   ┌───────────────────────────────┐      ┌────────────────────────┐
   │ core/                         │      │ CLAUDE.md              │
   │   CLAUDE.base.md              │ ───▶ │   ← base + stack +     │
   │   rules/, skills/, hooks/     │      │     project-interview  │
   │   mcp/mcp.partial.json        │      │                        │
   ├───────────────────────────────┤      │ settings.json          │
   │ stacks/<lang>/                │ ───▶ │   ← core + stack       │
   │   CLAUDE.stack.md             │      │                        │
   │   settings.partial.json       │      │ rules/                 │
   │   rules/, skills/, hooks/     │      │   python-style.md      │
   │   mcp/*.mcp.json              │      │   project.md  ← owned  │
   ├───────────────────────────────┤      │                        │
   │ (interview answers)           │ ───▶ │ skills/ agents/ hooks/ │
   │                               │      │                        │
   │                               │ ───▶ │ .mcp.json (at root)    │
   └───────────────────────────────┘      └────────────────────────┘
```

Every file that came from `core/` or `stacks/` carries a `source:` tag in
its frontmatter (or header comment for scripts/JSON). Files without a
`source:` tag — like `rules/project.md` and the `<!-- project-start -->`
section of `CLAUDE.md` — are project-owned and never touched by future
syncs.

## Install

One-time, per machine:

```bash
git clone https://github.com/<you>/dotclaude ~/code/dotclaude
export DOTCLAUDE_HOME=~/code/dotclaude          # add to your shell init

# expose dotclaude skills to every project at the user scope
mkdir -p ~/.claude/skills
ln -s ~/code/dotclaude/skills ~/.claude/skills/dotclaude
```

After this, the `dotclaude-init` skill is visible from any Claude Code
session on the machine.

## Usage

### Initialize a new or existing project

From inside the target repo:

```
> /dotclaude-init
```

The skill:

1. Scans the repo (stack detection, framework detection, external services).
2. Shows you what it found and asks you to correct anything wrong.
3. Asks at most ~5 questions about things code can't reveal — owners,
   rate limits, sensitive paths, public API surface.
4. Writes a flat `.claude/` directory merged from `core/` + matched stacks
   + your answers.

Full rules in [`skills/dotclaude-init/SKILL.md`](skills/dotclaude-init/SKILL.md).

### Sync upstream changes

From inside a target repo that was previously initialized:

```
> /dotclaude-sync
```

What happens:

1. Classifies every file in `.claude/` as **upstream** (has a `source:` tag), **project-owned** (no tag), **template-seeded** (never synced after init), or **merged** (composite — `settings.json`, `.mcp.json`, `CLAUDE.md`).
2. Compares upstream files against current `DOTCLAUDE_HOME`. Classifies as *unchanged*, *update*, *add*, *delete*, *drift*, or *stack-removed*.
3. Presents a grouped plan, highest-risk first. Bulk-confirms safe operations; per-file confirms risky ones.
4. Applies, writes a summary, leaves `git` as the rollback mechanism.

Drift (a file you edited locally that also changed upstream) is never
silently overwritten — sync asks: take upstream, keep local, or convert
the file to project-owned (remove the `source:` tag).

Full rules in [`skills/dotclaude-sync/SKILL.md`](skills/dotclaude-sync/SKILL.md).

### Render to a different agent

When the project (or a teammate) uses Cursor, Copilot, OpenCode, or any
agent that reads `AGENTS.md`, run the matching renderer instead of (or
in addition to) `dotclaude-init`. All renderers read from the same
`core/` + `stacks/` sources and ask the same interview questions.

| Command | Target | Output |
|---|---|---|
| `/dotclaude-init` | Claude Code | `.claude/` (flat), `.mcp.json` |
| `/dotclaude-init-cursor` | Cursor | `.cursor/rules/*.mdc`, `.cursor/mcp.json`, `AGENTS.md` |
| `/dotclaude-init-copilot` | GitHub Copilot | `.github/copilot-instructions.md`, `.github/instructions/*.instructions.md`, `AGENTS.md` |
| `/dotclaude-init-opencode` | OpenCode | `opencode.jsonc`, `.opencode/{agents,command,instructions}/`, `AGENTS.md` |
| `/dotclaude-init-agents-md` | Any agent | Single `AGENTS.md` at repo root (universal baseline) |

Renderers compose — running `dotclaude-init` *and* `dotclaude-init-cursor`
on the same repo is normal on teams that mix agents. Each renderer only
writes to its own directory and cooperates on `AGENTS.md` via
`<!-- project-start -->` / `<!-- project-end -->` markers.

### Audit drift (planned)

```
> /dotclaude-audit
```

Read-only dry-run of sync — report what would change without touching
files. Useful for CI checks.

## Adding a new stack

1. Create `stacks/<lang>/` with the same shape as `stacks/python/`:
   `CLAUDE.stack.md`, `settings.partial.json`, `rules/`, `skills/`,
   `agents/`, `hooks/`, optionally `mcp/`.
2. Add detection rules to
   [`skills/dotclaude-init/references/scanning.md`](skills/dotclaude-init/references/scanning.md)
   so the init skill picks it up automatically.

## Multi-agent portability

The framework is built around a single insight: **content is portable,
structure isn't**. A good code-quality rule is a good code-quality rule
whether it's loaded by Claude Code, Cursor, Copilot, or OpenCode. But
how each tool *loads* that rule — frontmatter schema, directory layout,
trigger mechanism — varies wildly.

```
                        ┌──────────────────────┐
                        │  core/  +  stacks/   │   ← canonical sources
                        │  (rules, skills,     │      (this repo)
                        │   agents, hooks,     │
                        │   MCP, interview)    │
                        └──────────┬───────────┘
                                   │
                ┌──────────────────┼──────────────────────────┐
                │                  │                  │       │
                ▼                  ▼                  ▼       ▼
         dotclaude-init  dotclaude-init-cursor  dotclaude-init-copilot  ...
                │                  │                  │
                ▼                  ▼                  ▼
        .claude/ (flat)     .cursor/rules/      .github/instructions/
        .mcp.json           .cursor/mcp.json    .github/copilot-instructions.md
                            AGENTS.md           AGENTS.md
```

**What translates well** — rules, conventions, review lenses, MCP
configs (with schema tweaks), project context.

**What translates lossily** — skills (intent-triggered in Claude Code,
often manual-invoke or prose elsewhere), subagents (first-class in Claude
Code & OpenCode; manual rules in Cursor; merged prose in Copilot).

**What doesn't translate at all** — hooks, fine-grained file/command
permissions. Each renderer is explicit about what it dropped.

Per-agent renderers cover:

- **Claude Code** — [`dotclaude-init`](skills/dotclaude-init/SKILL.md), [`dotclaude-sync`](skills/dotclaude-sync/SKILL.md) (highest fidelity; native target)
- **Cursor** — [`dotclaude-init-cursor`](skills/dotclaude-init-cursor/SKILL.md) (rules + MCP translate cleanly; hooks and subagent processes don't)
- **GitHub Copilot** — [`dotclaude-init-copilot`](skills/dotclaude-init-copilot/SKILL.md) (simplest target; prose-only; 4000-char budget on code-review instructions)
- **OpenCode** — [`dotclaude-init-opencode`](skills/dotclaude-init-opencode/SKILL.md) (second-highest fidelity; real subagents and slash commands)
- **Any agent reading `AGENTS.md`** — [`dotclaude-init-agents-md`](skills/dotclaude-init-agents-md/SKILL.md) (universal baseline; works with Continue, Aider, Cline, Zed, and others)

## Design principles

- **Scan, don't interrogate.** If grep can tell you the answer, don't ask.
- **Flat target, layered source.** Target repos stay simple; complexity
  lives here.
- **Source tags decide ownership.** Files with `source:` are ours to
  refresh; everything else is the project's.
- **One truth, many surfaces.** Canonical content in `core/` + `stacks/`;
  per-agent renderers translate into native formats.
- **Lossy translation is named.** Every renderer prints what it dropped
  and why. No silent feature loss.
- **Free tier only in `core/` and stack MCPs.** Paid services are the
  user's responsibility.
- **Idempotent.** Same inputs → byte-identical output.

## References & inspiration

Ideas borrowed (not depended on) from:

- [anthropics/claude-code](https://github.com/anthropics/claude-code)
- [centminmod/my-claude-code-setup](https://github.com/centminmod/my-claude-code-setup)
- [Jeffallan/claude-skills](https://github.com/Jeffallan/claude-skills) —
  skill-as-folder pattern, `triggers:` frontmatter, domain-hub skills.
