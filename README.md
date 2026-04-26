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
│   │                                    # refactor, explain, test-writer, commit,
│   │                                    # security-audit, hotfix
│   │                                    # + architecture / design skills:
│   │                                    #   architecture-designer, cloud-architect,
│   │                                    #   microservices-architect,
│   │                                    #   api-designer, graphql-architect
│   │                                    # + workflow / meta skills:
│   │                                    #   feature-forge (greenfield spec workshop),
│   │                                    #   spec-miner (reverse-engineer a spec),
│   │                                    #   code-documenter (docstrings / OpenAPI / sites),
│   │                                    #   fullstack-guardian (thin: feature across API + UI
│   │                                    #     with security done end-to-end),
│   │                                    #   the-fool (critical-reasoning modes: Socratic,
│   │                                    #     pre-mortem, red team, evidence audit, dialectic)
│   │                                    # + domain hubs (Jeffallan-style deep dives):
│   │                                    #   llm-serving/  (model formats, serving
│   │                                    #                 options, memory & batching)
│   │                                    #   homelab-infra/ (Proxmox/Talos bring-up,
│   │                                    #                  networking, storage & backup)
│   │                                    # + pro-level deep-dives (Jeffallan-adapted):
│   │                                    #   data: postgres-pro, sql-pro
│   │                                    #   ops: sre-engineer, monitoring-expert,
│   │                                    #        chaos-engineer, debugging-wizard,
│   │                                    #        legacy-modernizer
│   │                                    #   testing: test-master, playwright-expert
│   │                                    #   security: secure-code-guardian,
│   │                                    #             security-reviewer (skill form)
│   │                                    #   AI/ML: rag-architect, ml-pipeline,
│   │                                    #          fine-tuning-expert, prompt-engineer
│   │                                    #   realtime: websocket-engineer
│   │                                    # + project-conductor (lifecycle-aware orchestrator:
│   │                                    #   detects phase, routes to driver skill,
│   │                                    #   maintains agent-agnostic .claude/project-state.md)
│   │                                    # + learnings-log (Ralph-style append-only memory:
│   │                                    #   .claude/learnings.md, zero-dep cross-session
│   │                                    #   memory baseline; composes with brain-mcp)
│   ├── conventions/                     # cross-cutting conventions (non-rule docs):
│   │                                    #   ported-skills.md (provenance for skills
│   │                                    #                     adapted from external sources)
│   ├── agents/                          # code-reviewer, security-reviewer,
│   │                                    # performance-reviewer, doc-reviewer,
│   │                                    # architect, code-searcher
│   ├── hooks/                           # block-dangerous-commands, protect-files,
│   │                                    # scan-secrets, warn-large-files,
│   │                                    # session-start, notify, format-on-save,
│   │                                    # auto-test, context-recovery,
│   │                                    # conductor-brief (continuity layer:
│   │                                    #   prints project-state.md + brain-mcp
│   │                                    #   + graphify availability + phase hint
│   │                                    #   on every SessionStart)
│   ├── templates/                       # CLAUDE.local.md, settings.local.json  (one-shot copy)
│   └── mcp/                             # filesystem, fetch, git, memory,
│       ├── mcp.partial.json             # sequential-thinking, time  (always-on)
│       ├── optional/                    # github, context7, chrome-devtools,
│       │                                # brain-mcp (cross-agent memory, MIT, local),
│       │                                # graphify (multi-modal code graph, MIT, local),
│       │                                # code-review-graph (incremental review graph,
│       │                                #   28 MCP tools, blast-radius, MIT) (opt-in)
│       └── skills/                      # usage skill per MCP server
│
├── stacks/                              # layered — language + infra, pick all that apply
│   ├── python/                          # pyproject / requirements.txt
│   │   ├── CLAUDE.stack.md
│   │   ├── settings.partial.json
│   │   ├── rules/                       # python-style, async-patterns (MagicStack-flavored)
│   │   ├── skills/                      # pytest-debug, uv-deps,
│   │   │                                # python-pro (Jeffallan-adapted deep-dive)
│   │   ├── agents/                      # python-reviewer
│   │   ├── hooks/                       # ruff-format
│   │   └── mcp/                         # postgres, sqlite (opt-in)
│   ├── node-ts/                         # package.json / tsconfig
│   │   ├── CLAUDE.stack.md
│   │   ├── settings.partial.json
│   │   ├── rules/                       # ts-style
│   │   ├── skills/                      # vitest-debug,
│   │   │                                # typescript-pro (Jeffallan-adapted deep-dive)
│   │   ├── agents/                      # ts-reviewer
│   │   └── hooks/                       # format-prettier
│   ├── fastapi/                         # FastAPI + Pydantic V2 + async SQLAlchemy
│   │   ├── CLAUDE.stack.md
│   │   ├── settings.partial.json
│   │   ├── rules/                       # fastapi-patterns
│   │   └── skills/                      # fastapi-expert (deep-dive, ported from Jeffallan)
│   ├── docker/                          # Dockerfile / docker-compose.yml
│   │   ├── CLAUDE.stack.md
│   │   ├── settings.partial.json
│   │   ├── rules/                       # dockerfile-best-practices, compose-patterns
│   │   └── skills/                      # container-debug
│   ├── terraform/                       # *.tf / .terraform.lock.hcl
│   │   ├── CLAUDE.stack.md
│   │   ├── settings.partial.json
│   │   ├── rules/                       # state-safety
│   │   ├── skills/                      # tf-plan-review,
│   │   │                                # terraform-engineer (Jeffallan-adapted)
│   │   └── hooks/                       # block-destroy-apply
│   │
│   │                                    # frontend stacks (additive to node-ts or backend)
│   ├── react/                           # React 19+ — react-patterns
│   │                                    #   + skills/react-expert (Jeffallan-adapted deep-dive:
│   │                                    #     RSC, React 19 actions, hooks design, perf, migration)
│   ├── nextjs/                          # Next.js 14+ App Router — layers on react + node-ts
│   │                                    #   CLAUDE.stack.md, settings.partial.json,
│   │                                    #   rules/nextjs-patterns.md,
│   │                                    #   skills/nextjs-developer (App Router + Server Actions)
│   ├── angular/                         # Angular 17+ — signals, OnPush, standalone
│   │                                    #   + skills/angular-architect (Jeffallan-adapted:
│   │                                    #     NgRx createFeature, RxJS, functional guards)
│   ├── htmx-alpine/                     # server-rendered HTML + hypermedia patterns
│   ├── reflex/                          # Python full-stack (rx.State patterns)
│   │
│   │                                    # infra / CI stacks
│   ├── kubernetes/                      # manifest hygiene, probes, PDB, RBAC
│   │                                    #   + skills/kubernetes-specialist (Jeffallan-adapted:
│   │                                    #     workloads, networking, storage, security, debug)
│   ├── aws/                             # IAM least-privilege, tagging, cost discipline
│   ├── github-actions/                  # workflow security (pin SHAs, OIDC, permissions)
│   │
│   │                                    # ML / inference stacks
│   ├── pytorch/                         # training loop, AMP, DDP/FSDP, checkpoints
│   ├── vllm-ollama/                     # inference ops (ties to core skill llm-serving)
│   │
│   └── dotnet/                          # .NET 8+ / C# 12+ — nullable, records, async
│
├── skills/                              # the framework itself — one skill per workflow
│   ├── dotclaude-init/                  # scan → interview → merge  (Claude Code target)
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── scanning.md
│   │       ├── interview.md
│   │       └── merge.md
│   ├── dotclaude-sync/                  # refresh upstream content, preserve project-owned
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── classification.md
│   │       ├── update-rules.md
│   │       └── drift-handling.md
│   │
│   │                                    # per-agent renderers — same sources, different targets
│   ├── dotclaude-init-cursor/           # → .cursor/rules/*.mdc + .cursor/mcp.json + AGENTS.md
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── mdc-format.md
│   │       └── translation.md
│   ├── dotclaude-init-copilot/          # → .github/copilot-instructions.md + .github/instructions/
│   │   ├── SKILL.md
│   │   └── references/translation.md
│   ├── dotclaude-init-opencode/         # → opencode.jsonc + .opencode/agents|command|instructions/
│   │   ├── SKILL.md
│   │   └── references/translation.md
│   └── dotclaude-init-agents-md/        # → AGENTS.md only (universal fallback)
│       └── SKILL.md
│
└── commands/                            # Claude Code slash-command wrappers over the six
                                         # framework skills. Deterministic /-menu invocation
                                         # alongside natural-language activation via skills.
                                         # Installed into ~/.claude/commands/.
    ├── dotclaude-init.md
    ├── dotclaude-sync.md
    ├── dotclaude-init-cursor.md
    ├── dotclaude-init-copilot.md
    ├── dotclaude-init-opencode.md
    └── dotclaude-init-agents-md.md
```

**Commands vs skills, by design.** The six framework entry points
above are the *only* things that exist as both a skill and a slash
command. Commands exist because framework init/sync is a
user-initiated, named operation where deterministic triggering and
menu discoverability matter. The 40+ `core/` and `stack/` skills
(e.g. `debug-fix`, `pr-review`, `postgres-pro`, `rag-architect`) are
skill-only by design — they're meant to auto-activate based on the
user's described intent, which is a feature that wrapping in commands
would break.

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

One-time, per machine.

**Linux / macOS:**

```bash
git clone https://github.com/<you>/dotclaude ~/code/dotclaude
export DOTCLAUDE_HOME=~/code/dotclaude          # add to your shell init

# Expose each framework skill at the top level of ~/.claude/skills/.
# Claude Code discovers skills at ONE level deep — nesting under a
# single `dotclaude/` subdir hides them. Symlink each skill directly.
mkdir -p ~/.claude/skills ~/.claude/commands
for skill in "$DOTCLAUDE_HOME"/skills/*/; do
  ln -sfn "$skill" "$HOME/.claude/skills/$(basename "$skill")"
done

# Expose framework slash commands (/dotclaude-init, /dotclaude-sync, etc.).
for cmd in "$DOTCLAUDE_HOME"/commands/*.md; do
  ln -sfn "$cmd" "$HOME/.claude/commands/$(basename "$cmd")"
done
```

**Windows (PowerShell):**

```powershell
git clone https://github.com/<you>/dotclaude "$env:USERPROFILE\code\dotclaude"
setx DOTCLAUDE_HOME "$env:USERPROFILE\code\dotclaude"
$env:DOTCLAUDE_HOME = "$env:USERPROFILE\code\dotclaude"

New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude\skills"   | Out-Null
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude\commands" | Out-Null

Get-ChildItem -Path "$env:DOTCLAUDE_HOME\skills" -Directory | ForEach-Object {
    $link = Join-Path "$env:USERPROFILE\.claude\skills" $_.Name
    if (Test-Path $link) { Remove-Item $link -Force -Recurse }
    New-Item -ItemType Junction -Path $link -Target $_.FullName | Out-Null
}

# Commands are individual files — use hardlinks (no admin required on NTFS).
# Hardlinks reflect in-place edits immediately. If `git pull` ever replaces
# a source command file (rare; creates a new inode), just re-run this step.
Get-ChildItem -Path "$env:DOTCLAUDE_HOME\commands" -Filter *.md | ForEach-Object {
    $link = Join-Path "$env:USERPROFILE\.claude\commands" $_.Name
    if (Test-Path $link) { Remove-Item $link -Force }
    cmd /c mklink /H "`"$link`"" "`"$($_.FullName)`"" | Out-Null
}
```

After this, the framework surfaces in two ways from any Claude Code
session on the machine:

- **Skills** (auto-activate on natural language) — `dotclaude-init`,
  `dotclaude-sync`, `dotclaude-init-cursor`, `dotclaude-init-copilot`,
  `dotclaude-init-opencode`, `dotclaude-init-agents-md`.
- **Slash commands** (deterministic, show in `/` menu) — same six
  names: `/dotclaude-init`, `/dotclaude-sync`,
  `/dotclaude-init-cursor`, `/dotclaude-init-copilot`,
  `/dotclaude-init-opencode`, `/dotclaude-init-agents-md`.

**Restart any running Claude Code session** — both skills and
commands are discovered at session start.

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

## Domain hubs

Some topics cut across every stack and deserve Jeffallan-style
deep-dive skills — a `SKILL.md` that orchestrates, plus `references/`
siblings that go into depth. These live under `core/skills/` and
activate on demand when the user asks a question in that domain.

| Hub | What it covers | When it activates |
|---|---|---|
| [`llm-serving`](core/skills/llm-serving/SKILL.md) | Runtime choice (Ollama / vLLM / llama.cpp / TGI / SGLang), model formats (gguf / safetensors / AWQ / GPTQ / FP8), VRAM + KV-cache sizing, batching, multi-GPU | user asks about running LLMs locally, quantization, "why is it slow / OOM'ing", runtime comparisons |
| [`homelab-infra`](core/skills/homelab-infra/SKILL.md) | Proxmox + Talos / k3s bring-up, LXC vs VM decisions, networking (VLANs, reverse proxy, MetalLB, Tailscale), storage (ZFS, NFS, Longhorn), the 3-2-1 backup rule | user plans a homelab, debugs a non-booting cluster, asks "where should this service live" |

Domain hubs are bigger than tactical skills by design — one or two per
session is the right pace to add more.

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

## Ported skills

A subset of skills are **adapted** from
[Jeffallan/claude-skills](https://github.com/Jeffallan/claude-skills) —
rewritten in `dotclaude` voice and scope, with provenance tracked via
frontmatter. See
[`core/conventions/ported-skills.md`](core/conventions/ported-skills.md)
for the convention and
[`skills/dotclaude-sync/SKILL.md`](skills/dotclaude-sync/SKILL.md) for
how sync treats them.

| Location | Skill | Origin (Jeffallan) |
|---|---|---|
| `core/skills/` | `architecture-designer` | `architecture-designer` |
| `core/skills/` | `cloud-architect` | `cloud-architect` |
| `core/skills/` | `microservices-architect` | `microservices-architect` |
| `core/skills/` | `api-designer` | `api-designer` |
| `core/skills/` | `graphql-architect` | `graphql-architect` |
| `core/skills/` | `the-fool` | `the-fool` |
| `core/skills/` | `feature-forge` | `feature-forge` |
| `core/skills/` | `spec-miner` | `spec-miner` |
| `core/skills/` | `code-documenter` | `code-documenter` |
| `core/skills/` | `fullstack-guardian` (thin) | `fullstack-guardian` |
| `core/skills/` | `postgres-pro` | `postgres-pro` |
| `core/skills/` | `sql-pro` | `sql-pro` |
| `core/skills/` | `sre-engineer` | `sre-engineer` |
| `core/skills/` | `monitoring-expert` | `monitoring-expert` |
| `core/skills/` | `test-master` | `test-master` |
| `core/skills/` | `playwright-expert` | `playwright-expert` |
| `core/skills/` | `secure-code-guardian` | `secure-code-guardian` |
| `core/skills/` | `security-reviewer` (skill form) | `security-reviewer` |
| `core/skills/` | `rag-architect` | `rag-architect` |
| `core/skills/` | `ml-pipeline` | `ml-pipeline` |
| `core/skills/` | `fine-tuning-expert` | `fine-tuning-expert` |
| `core/skills/` | `prompt-engineer` | `prompt-engineer` |
| `core/skills/` | `websocket-engineer` | `websocket-engineer` |
| `core/skills/` | `chaos-engineer` | `chaos-engineer` |
| `core/skills/` | `debugging-wizard` | `debugging-wizard` |
| `core/skills/` | `legacy-modernizer` | `legacy-modernizer` |
| `stacks/python/skills/` | `python-pro` | `python-pro` |
| `stacks/node-ts/skills/` | `typescript-pro` | `typescript-pro` |
| `stacks/terraform/skills/` | `terraform-engineer` | `terraform-engineer` |
| `stacks/kubernetes/skills/` | `kubernetes-specialist` | `kubernetes-specialist` |
| `stacks/react/skills/` | `react-expert` | `react-expert` |
| `stacks/nextjs/skills/` | `nextjs-developer` | `nextjs-developer` |
| `stacks/angular/skills/` | `angular-architect` | `angular-architect` |
| `stacks/fastapi/skills/` | `fastapi-expert` | `fastapi-expert` |

Each adapted skill carries `ported-from:`, `ported-at:`, and
`adapted: true` in its frontmatter so future syncs can diff against the
upstream and decide whether to re-port. `dotclaude-sync` only pulls from
`DOTCLAUDE_HOME` — upstream drift from Jeffallan's repo is surfaced
manually (or, in the future, by a dedicated `dotclaude-upstream-check`
skill).

## Cross-agent continuity (memory + graph + conductor)

The continuity layer is **default-on infrastructure**, not optional
add-ons. It guarantees that switching between Claude Code, Cursor,
Codex, OpenCode, or Gemini CLI doesn't cost you context — and that
every cold start begins with a re-entry brief, automatically.

### How it's wired

| Layer | Where | What it does |
|---|---|---|
| **`conductor-brief.sh`** SessionStart hook | `core/hooks/` (registered in `core/settings.partial.json`) | Auto-runs at every session start. Prints `.claude/project-state.md`, the top 3 entries of `.claude/learnings.md`, brain-mcp / graphify availability, and a phase hint *before* the user types anything. |
| **`CLAUDE.md` Continuity section** | `core/CLAUDE.base.md` (top-level section) | Instructs every agent — Claude Code, Cursor, Codex, OpenCode, Gemini CLI — to read `project-state.md` and `learnings.md` first and call brain-mcp on cold start. The cross-agent guarantee for tools that don't support hooks. |
| **`/dotclaude-resume` command** + `scripts/dotclaude-resume.sh` | `commands/`, `scripts/` | Manual invocation: prints the brief on demand. Useful for agents without SessionStart hooks, after `/clear`, or when pasting context into a different agent. |
| **`project-conductor` skill** | `core/skills/project-conductor/` | Drives when the user explicitly asks "where are we", when phase ambiguity needs a real conversation, and when state needs updating at the end of substantive work. |
| **`learnings-log` skill** + **`/dotclaude-learn`** command | `core/skills/learnings-log/`, `commands/dotclaude-learn.md` | Append-only project memory at `.claude/learnings.md`. Captures gotchas, hidden couplings, "looks wrong but is intentional" notes. Zero-dep — works without any MCP installed. The Ralph-style baseline that carries cross-session memory when brain-mcp isn't wired. |
| **brain-mcp** (default ON in init, opt-in install) | `core/mcp/optional/brain-mcp.mcp.json` + `core/mcp/skills/brain-mcp/SKILL.md` | Cross-agent persistent memory ([brain-mcp](https://github.com/mordechaipotash/brain-mcp), MIT, 100% local). 25 MCP tools. Recommended global install: `pipx install brain-mcp && brain-mcp setup`. |
| **graphify** (default ON for non-trivial repos, opt-in install) | `core/mcp/optional/graphify.mcp.json` + `core/mcp/skills/graphify/SKILL.md` | Multi-modal codebase knowledge graph ([graphify](https://github.com/safishamsi/graphify), MIT, local-first). Tree-sitter + Leiden clustering. Best for **exploration** ("what is this codebase?"). Install: `pip install graphifyy && graphify install`. |
| **code-review-graph (CRG)** (default ON for active non-trivial repos, opt-in install) | `core/mcp/optional/code-review-graph.mcp.json` + `core/mcp/skills/code-review-graph/SKILL.md` | Incremental review-time code graph ([code-review-graph](https://github.com/tirth8205/code-review-graph), MIT, local, SQLite). Tree-sitter (23 langs + Jupyter) + auto-update hook (<2s on save/commit) + first-class blast-radius. 28 MCP tools, 5 workflow prompts. Best for **review** ("what does this change break?"). Install: `pip install code-review-graph && code-review-graph install` (auto-configures 11 supported agents). |

### The composition

Five artifacts, five concerns, one re-entry brief:

- `.claude/project-state.md` keeps the **current intent** (what phase, what's next, what not to lose) — agent-agnostic Markdown, snapshot, lives in git.
- `.claude/learnings.md` keeps the **accumulated discovery** (gotchas, dead ends, hidden couplings) — append-only, zero-dep, the Ralph-style baseline.
- `brain-mcp` keeps the **full conversational** context (everything said, decided, doubted across every AI tool) — semantic search, optional install.
- `graphify` keeps the **structural exploration** context (multi-modal: code + docs + papers + diagrams; "what is this codebase?") — Tree-sitter graph + Leiden clustering, optional install.
- `code-review-graph` keeps the **change-shaped structural** context (incremental, auto-updated <2s on save/commit; "what does this change break?") — Tree-sitter graph + SQLite + 28 MCP tools, optional install.

The two file-based artifacts work with zero installs. The three MCPs
add semantic search, exploration depth, and review-time blast-radius
on top. Graceful degradation throughout — each layer skips silently
when the underlying tool isn't installed.

**graphify vs code-review-graph** — both are graphs, but they answer
different questions: graphify is your map for *exploring* a codebase
(multi-modal, semantic, surprises), CRG is your map for *reviewing
changes* (incremental, blast-radius, risk-scored). Wire both; the
skills route different question shapes to the right one.

### The cold-start loop

1. You open a project in any agent.
2. `conductor-brief.sh` fires (or, on agents without SessionStart hooks, the agent reads the Continuity section in `CLAUDE.md` and runs the equivalent inline). The brief shows the project state, the top 3 learnings entries, brain-mcp / graphify availability, and the phase hint.
3. If wired, the agent calls `brain.context_recovery(domain=<project>)` and `brain.open_threads()` for conversational context.
4. If the change is structural, the agent reads `graphify-out/GRAPH_REPORT.md`.
5. The agent confirms the brief with you in 1-2 sentences and proposes the next concrete action — or just acts if the next step is unambiguous.
6. At the end of substantive work, the agent updates `.claude/project-state.md` (current state) and appends to `.claude/learnings.md` if anything non-obvious was discovered. You commit both. The next agent — possibly on a different platform — starts at step 1 with full context.

### Install (global, one-time per machine)

```bash
# brain-mcp — wires into every agent on the machine
pipx install brain-mcp
brain-mcp setup

# graphify — per-project graph builder + slash commands
pip install graphifyy
graphify install

# code-review-graph — per-project incremental review graph;
# auto-detects and configures 11 supported agents (Claude Code,
# Codex, Cursor, Windsurf, Zed, Continue, OpenCode, Antigravity,
# Qwen, Qoder, Kiro)
pip install code-review-graph
code-review-graph install
```

All three gracefully degrade — if any isn't installed, the conductor
brief says so and the agent skips the corresponding step. No errors,
no nags.

### Per-project setup

`dotclaude-init` handles this automatically:

- Wires brain-mcp (default ON), graphify (default ON for non-trivial repos), and code-review-graph (default ON for non-trivial *active* repos — skipped for greenfield) into `.mcp.json`. Each gets a three-way choice: wire only, wire AND install now (with per-tool confirmation), or skip.
- Copies `conductor-brief.sh` into `.claude/hooks/` and registers it in `.claude/settings.json`.
- Seeds `.claude/project-state.md` with the detected phase if the file doesn't already exist.
- Seeds `.claude/learnings.md` with a minimal header + one example entry if the file doesn't already exist (zero-dep cross-session memory baseline).
- If brain-mcp / graphify aren't installed locally and the user didn't opt into the install step, prints the install commands at the end of init.

## References & inspiration

Ideas borrowed (not depended on) from:

- [anthropics/claude-code](https://github.com/anthropics/claude-code)
- [centminmod/my-claude-code-setup](https://github.com/centminmod/my-claude-code-setup)
- [Jeffallan/claude-skills](https://github.com/Jeffallan/claude-skills) —
  skill-as-folder pattern, `triggers:` frontmatter, domain-hub skills,
  and the adapted skills listed above.
- [mordechaipotash/brain-mcp](https://github.com/mordechaipotash/brain-mcp) —
  cross-agent persistent memory (MIT, local). Wired as an opt-in MCP with
  a usage skill in `core/mcp/skills/brain-mcp/`.
- [safishamsi/graphify](https://github.com/safishamsi/graphify) —
  multi-modal knowledge-graph builder (MIT, local-first). Wired as an
  opt-in MCP with a usage skill in `core/mcp/skills/graphify/`.
- [tirth8205/code-review-graph](https://github.com/tirth8205/code-review-graph) —
  incremental review-time code graph (MIT, local, SQLite). Wired as an
  opt-in MCP with a usage skill in `core/mcp/skills/code-review-graph/`.
  Pairs with graphify: graphify for exploration, CRG for review.
- The Strangler Fig / Branch by Abstraction / Parallel Change patterns
  (Fowler, Hammant) — used throughout `legacy-modernizer` and the
  `migration` phase routing in `project-conductor`.
