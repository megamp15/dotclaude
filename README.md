# dotclaude

A portable, layered Claude Code setup you can drop into any project on any
tech stack. Universal principles live in `core/`; language- and
framework-specific pieces live in `stacks/`; anything unique to a particular
repo is captured from an interview at init time and stays project-owned.

Running the `dotclaude-init` skill inside a target repo produces a flat
`.claude/` directory shaped exactly the way Claude Code expects — merged
from the three layers, with `source:` tags on every file that came from
this repo so future syncs know what's safe to refresh.

## What's in here

```
dotclaude/
├── core/                                # universal — applies to every project
│   ├── CLAUDE.base.md                   # universal instructions, principles, guardrails
│   ├── settings.partial.json            # universal permissions + hook registration
│   ├── rules/                           # code-quality, testing, security, git,
│   │                                    # design-patterns, software-principles
│   ├── skills/                          # pr-review, debug-fix, ship, tdd,
│   │                                    # refactor, explain, test-writer, commit
│   ├── agents/                          # code-reviewer, security-reviewer,
│   │                                    # performance-reviewer, doc-reviewer, architect
│   ├── hooks/                           # block-dangerous-commands, protect-files,
│   │                                    # scan-secrets, warn-large-files,
│   │                                    # session-start, notify
│   └── mcp/                             # filesystem, fetch, git, memory,
│       ├── mcp.partial.json             # sequential-thinking, time  (always-on)
│       ├── optional/                    # github, context7, chrome-devtools (opt-in)
│       └── skills/                      # usage skill per MCP server
├── stacks/                              # per-language layers
│   └── python/
│       ├── CLAUDE.stack.md
│       ├── settings.partial.json
│       ├── rules/                       # python-style
│       ├── skills/                      # pytest-debug, uv-deps
│       ├── agents/                      # python-reviewer
│       ├── hooks/                       # ruff-format
│       └── mcp/                         # postgres, sqlite (opt-in)
└── skills/
    └── dotclaude-init/                  # the init skill (scan → interview → merge)
        ├── SKILL.md
        └── references/
            ├── scanning.md
            ├── interview.md
            └── merge.md
```

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

### Sync upstream changes (planned)

```
> /dotclaude-sync
```

Refresh files that came from `core/` or `stacks/`; leave project-owned
files alone. Driven off the `source:` tags.

### Audit drift (planned)

```
> /dotclaude-audit
```

Report what's missing, outdated, or orphaned in a target's `.claude/`
relative to the current `DOTCLAUDE_HOME`.

## Adding a new stack

1. Create `stacks/<lang>/` with the same shape as `stacks/python/`:
   `CLAUDE.stack.md`, `settings.partial.json`, `rules/`, `skills/`,
   `agents/`, `hooks/`, optionally `mcp/`.
2. Add detection rules to
   [`skills/dotclaude-init/references/scanning.md`](skills/dotclaude-init/references/scanning.md)
   so the init skill picks it up automatically.

## Design principles

- **Scan, don't interrogate.** If grep can tell you the answer, don't ask.
- **Flat target, layered source.** Target repos stay simple; complexity
  lives here.
- **Source tags decide ownership.** Files with `source:` are ours to
  refresh; everything else is the project's.
- **Free tier only in `core/` and stack MCPs.** Paid services are the
  user's responsibility.
- **Idempotent.** Same inputs → byte-identical output.

## References & inspiration

Ideas borrowed (not depended on) from:

- [anthropics/claude-code](https://github.com/anthropics/claude-code)
- [centminmod/my-claude-code-setup](https://github.com/centminmod/my-claude-code-setup)
- [Jeffallan/claude-skills](https://github.com/Jeffallan/claude-skills) —
  skill-as-folder pattern, `triggers:` frontmatter, domain-hub skills.
