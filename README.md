# dotclaude

A portable, layered AI-assistant setup you can drop into any project.

Universal behavior lives in `core/`, stack-specific behavior lives in
`stacks/`, and project-specific context is collected during init and stays
project-owned. Running `/dotclaude-init` inside a target repo produces a flat
`.claude/` directory shaped for Claude Code, with `source:` tags on every file
that dotclaude owns so future syncs know what is safe to refresh.

The same canonical content can also render to Cursor, GitHub Copilot,
OpenCode, and plain `AGENTS.md` through the renderer skills in `skills/`.

## Start Here

1. Install the framework skills and commands:
   [docs/install.md](docs/install.md)
2. Initialize a repo with `/dotclaude-init`:
   [docs/usage.md](docs/usage.md)
3. Learn how the source layers merge into a target repo:
   [docs/architecture.md](docs/architecture.md)

## Layout

```text
dotclaude/
├── core/        # universal rules, skills, agents, hooks, MCP defaults
├── stacks/      # categorized language/framework/infra stack overlays
├── skills/      # dotclaude framework skills and renderer skills
├── commands/    # slash-command wrappers
├── scripts/     # backing scripts and validators
├── docs/        # longer docs split out from the root README
└── .github/     # repo validation workflow
```

## Core Ideas

- **Flat target, layered source.** Target repos get a simple `.claude/`
  directory. This repo keeps the layered source model.
- **Source tags decide ownership.** Files with `source:` are refreshed by
  sync; files without it are project-owned.
- **One truth, many agents.** Claude Code, Cursor, Copilot, OpenCode, and
  `AGENTS.md` render from the same `core/` and `stacks/` material.
- **Skills are the primary surface.** Most workflows are intent-triggered
  skills. Slash commands exist for named framework operations.
- **Continuity is built in.** `project-state.md`, `learnings.md`, optional
  MCP memory/graphs, and the conductor brief keep context alive across agents.

## Main Commands

| Command | Purpose |
|---|---|
| `/dotclaude-init` | Initialize or refresh a target repo's `.claude/` layout. |
| `/dotclaude-sync` | Pull upstream dotclaude changes into an initialized repo. |
| `/dotclaude-init-cursor` | Render dotclaude into Cursor rules and MCP config. |
| `/dotclaude-init-copilot` | Render dotclaude into Copilot instructions. |
| `/dotclaude-init-opencode` | Render dotclaude into OpenCode config. |
| `/dotclaude-init-agents-md` | Render a universal `AGENTS.md`. |
| `/dotclaude-parallel` | Use Agent Teams or fallback parallel-agent patterns. |
| `/dotclaude-doctor` | Diagnose install, skills, hooks, source tags, and config. |
| `/dotclaude-permissions-audit` | Read-only audit of permission rules and hook drift. |
| `/dotclaude-resume` | Print the project re-entry brief on demand. |
| `/dotclaude-learn` | Append a high-signal project learning. |

## Documentation

- [Install](docs/install.md)
- [Usage](docs/usage.md)
- [Architecture](docs/architecture.md)
- [Continuity](docs/continuity.md)
- [Permissions](docs/permissions.md)
- [Ported skills](docs/ported-skills.md)
- [OneDrive and Windows locks](docs/windows-onedrive-locks.md)

## Validation

Run the repo validator locally:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate-dotclaude.ps1
```

GitHub Actions runs the same validator on pushes and pull requests.

## Status Notes

Stack folders are grouped by category under `stacks/`, while target-project
source tags remain stable as `source: stacks/<name>` for sync compatibility.
