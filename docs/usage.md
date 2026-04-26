# Usage

## Initialize a Repo

From inside the target repo:

```text
> /dotclaude-init
```

The skill:

1. Scans the repo for stacks, frameworks, external services, and existing
   `.claude/` state.
2. Shows what it found and asks for corrections.
3. Asks only the questions code cannot answer: owners, rate limits, sensitive
   paths, public API surface, and optional MCP choices.
4. Writes a flat `.claude/` directory merged from `core/`, matched `stacks/`,
   and project answers.

Full workflow: [../skills/dotclaude-init/SKILL.md](../skills/dotclaude-init/SKILL.md).

## Sync Upstream Changes

From inside a repo that was already initialized:

```text
> /dotclaude-sync
```

Sync classifies every `.claude/` file as upstream, project-owned,
template-seeded, or merged. It then compares upstream files against current
`DOTCLAUDE_HOME`, groups safe updates, and asks before drift or deletes.

Full workflow: [../skills/dotclaude-sync/SKILL.md](../skills/dotclaude-sync/SKILL.md).

## Render to Other Agents

All renderers read from the same canonical sources.

| Command | Target | Output |
|---|---|---|
| `/dotclaude-init` | Claude Code | `.claude/`, `.mcp.json` |
| `/dotclaude-init-cursor` | Cursor | `.cursor/rules/*.mdc`, `.cursor/mcp.json`, `AGENTS.md` |
| `/dotclaude-init-copilot` | GitHub Copilot | `.github/copilot-instructions.md`, `.github/instructions/*.instructions.md`, `AGENTS.md` |
| `/dotclaude-init-opencode` | OpenCode | `opencode.jsonc`, `.opencode/{agents,command,instructions}/`, `AGENTS.md` |
| `/dotclaude-init-agents-md` | Any agent | `AGENTS.md` |

Renderers compose. A team can run Claude Code and Cursor renderers in the same
repo because each writes to its own native directory.

## Add a Stack

1. Create `stacks/<category>/<name>/` with `CLAUDE.stack.md`,
   `settings.partial.json`, and optional `rules/`, `skills/`, `agents/`,
   `hooks/`, and `mcp/`.
2. Add detection rules to
   [../skills/dotclaude-init/references/scanning.md](../skills/dotclaude-init/references/scanning.md).
3. Keep source tags stable as `source: stacks/<name>` even though the physical
   folder is categorized.
4. Run the validator:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate-dotclaude.ps1
```
