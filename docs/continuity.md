# Cross-Agent Continuity

The continuity layer keeps context alive across Claude Code, Cursor, Codex,
OpenCode, Copilot, and other agents.

## Pieces

| Piece | Where | Purpose |
|---|---|---|
| `conductor-brief.sh` | `core/hooks/` | SessionStart brief with state, learnings, MCP availability, and phase hint. |
| Continuity instructions | `core/CLAUDE.base.md` | Cross-agent rule: read state and memory on cold start. |
| `/dotclaude-resume` | `commands/`, `scripts/` | Print the brief manually. |
| `project-conductor` | `core/skills/project-conductor/` | Lifecycle-aware routing and state updates. |
| `learnings-log` | `core/skills/learnings-log/` | Append-only `.claude/learnings.md` memory. |
| brain-mcp | `core/mcp/optional/brain-mcp.mcp.json` | Optional conversational memory. |
| graphify | `core/mcp/optional/graphify.mcp.json` | Optional exploration graph. |
| code-review-graph | `core/mcp/optional/code-review-graph.mcp.json` | Optional review-time blast radius graph. |

## Cold Start Loop

1. Agent opens a project.
2. The SessionStart hook prints the conductor brief, or the agent follows the
   continuity instructions manually.
3. If brain-mcp is wired, recover conversational context.
4. If graphify or code-review-graph is relevant, read structural context.
5. Confirm the brief in one or two sentences and continue the user's task.
6. At the end of substantive work, update `project-state.md` and log any
   non-obvious learnings.

## Optional MCP Installs

```bash
pipx install brain-mcp
brain-mcp setup

pip install graphifyy
graphify install

pip install code-review-graph
code-review-graph install
```

All MCPs degrade gracefully. If a tool is not installed, the brief says so and
the agent skips that layer.

