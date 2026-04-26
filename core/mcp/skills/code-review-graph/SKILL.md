---
name: code-review-graph
description: Local incremental knowledge graph tuned for code review and daily coding. Tree-sitter (23 langs + Jupyter) + SQLite + auto-update hook (<2s on save/commit) + first-class blast-radius analysis. 28 MCP tools including `detect_changes_tool`, `get_impact_radius_tool`, `get_review_context_tool`. Use for PR reviews, "what does this change break", and as the always-fresh structural map during active development. Pairs with graphify (which is multi-modal and exploration-focused). MIT, local-first, SQLite.
source: core/mcp
triggers: /code-review-graph, /crg, blast radius, what does this change break, what does this PR affect, review delta, review PR, impact analysis, who is affected by this change, change impact, dependency chain, hotspot detection, monorepo daemon
---

# code-review-graph (CRG)

A locally-built, **incrementally-maintained** code graph. Where graphify is
the *exploration* tool (multi-modal, semantic, Leiden communities), CRG is
the *review* tool — auto-updates on every commit/save, knows the precise
blast radius of any change, and ships 28 MCP tools tuned for the daily
loop: edit, save, ask "what did I just affect?", review.

Source: <https://github.com/tirth8205/code-review-graph> · <https://code-review-graph.com>
License: MIT · Python 3.10+ · 8.2× average token reduction · 2,900-file
re-index in <2s.

## CRG vs graphify — when to reach for which

Both are MIT, local-first, Tree-sitter graphs. They specialize differently:

| Question | Prefer |
|---|---|
| *"What does this codebase look like?"* (cold start, onboarding) | **graphify** |
| *"What does this PR break?"* (review time) | **CRG** |
| *"How do these papers / diagrams relate to the code?"* | **graphify** (multi-modal) |
| *"Which functions are affected if I change `login()`?"* | **CRG** (`get_impact_radius_tool`) |
| *"Are there surprising cross-domain edges?"* | **graphify** (Leiden surprises) |
| *"Risk-score this diff for me"* | **CRG** (`detect_changes_tool`) |
| *"Build a fresh graph and keep it fresh as I edit"* | **CRG** (auto-hooks, <2s incremental) |
| *"Map across multiple repos in a monorepo cluster"* | **CRG** (`crg-daemon`) |

The headline split: **graphify answers "what is this?"**, **CRG answers
"what changed and what does it touch?"**. They cost almost nothing to keep
both wired — they're MCPs we declare, not background daemons we run.

When the user asks a structural question:
- Cold-start / first-time-in-repo → graphify
- Inside an active editing/review loop → CRG
- Truly multi-modal (code + PDFs + diagrams) → graphify only

## When to use

Reach for CRG specifically when the question is **change-shaped**:

- *"Review this diff."* → `detect_changes_tool` + `get_review_context_tool`
- *"What's the blast radius of changing `parse_invoice`?"* → `get_impact_radius_tool`
- *"What flows are affected by my staged changes?"* → `get_affected_flows_tool`
- *"Give me the ultra-compact context first."* → `get_minimal_context_tool` (~100 tokens)
- *"Find the architectural chokepoints / hub nodes."* → `get_bridge_nodes_tool`, `get_hub_nodes_tool`
- *"Is anything untested in the impact radius?"* → `get_knowledge_gaps_tool`
- *"Help me onboard a developer to this repo."* → MCP prompt `onboard_developer`
- *"Pre-merge check."* → MCP prompt `pre_merge_check`

## When NOT to use

- **Trivial single-file changes.** CRG's structural metadata can exceed
  the raw file size on tiny edits (the README's `express` benchmark shows
  this honestly — 0.7× reduction on a small package). Just `Read` the file.
- **Questions about libraries / external APIs.** Use `context7-mcp`.
- **Questions about prior conversations.** Use `brain-mcp`.
- **Pure structural exploration without a change in mind.** Use `graphify`.
- **Greenfield with <50 files** — the graph is bigger than the project.
  Wait until building phase.

## Setup (one-time per machine)

```bash
pip install code-review-graph    # or: pipx install code-review-graph
code-review-graph install        # auto-detects 11 agents and configures each
```

`code-review-graph install` writes the right MCP config + slash-command
manifest for every agent on the machine: Codex, Claude Code, Cursor,
Windsurf, Zed, Continue, OpenCode, Antigravity, Qwen, Qoder, Kiro. To
target one specifically:

```bash
code-review-graph install --platform claude-code
```

After install, restart your editor and ask the agent:

```
Build the code review graph for this project
```

Initial build: ~10 s for a 500-file project. After that, every save and
every commit fires an auto-update — typically <2 s for a 2,900-file repo.

### Incremental hooks vs daemon

CRG keeps the graph fresh in two ways:

1. **In-editor hooks** (Claude Code, Codex with hook support, etc.) —
   trigger on file save and `git commit`. SHA-256 diff + selective
   re-parse.
2. **`crg-daemon`** — background watcher process. Use this when:
   - Your editor doesn't support hooks (Cursor, OpenCode in some modes).
   - You want monorepo coverage — daemon watches multiple repos in
     parallel with health checks and auto-restart.

```bash
crg-daemon add ~/project-a --alias proj-a
crg-daemon add ~/project-b
crg-daemon start
crg-daemon status
crg-daemon logs --repo proj-a -f
```

Config lives at `~/.code-review-graph/watch.toml` and is monitored for
hot-reload. No external deps.

## The 28 MCP tools (cheat sheet)

Your agent uses these automatically. The high-leverage ones to know by
name:

| Tool | Use it for |
|---|---|
| `get_minimal_context_tool` | **First call** — ~100 tokens, sets the scene |
| `detect_changes_tool` | Risk-scored diff analysis (the PR-review primary) |
| `get_impact_radius_tool` | Blast radius of named files / functions |
| `get_review_context_tool` | Structural summary tuned for review |
| `get_affected_flows_tool` | Execution flows touched by a change |
| `get_hub_nodes_tool` | Architectural hotspots (high-degree) |
| `get_bridge_nodes_tool` | Chokepoints (high-betweenness) |
| `get_knowledge_gaps_tool` | Untested hotspots, isolated nodes |
| `get_surprising_connections_tool` | Unexpected cross-community coupling |
| `traverse_graph_tool` | Free-form BFS/DFS with token budget |
| `query_graph_tool` | Callers / callees / tests / imports / inheritance |
| `semantic_search_nodes_tool` | Find code entities by name or meaning |
| `cross_repo_search_tool` | Search across the multi-repo registry |

Plus 5 MCP **prompts** (workflow templates) — invoke by name from your
agent: `review_changes`, `architecture_map`, `debug_issue`,
`onboard_developer`, `pre_merge_check`.

### Tool filtering when context is tight

CRG exposes 28 tools by default. To trim:

```bash
code-review-graph serve --tools query_graph_tool,detect_changes_tool,get_review_context_tool
# or via env:
CRG_TOOLS=query_graph_tool,detect_changes_tool,get_review_context_tool code-review-graph serve
```

Useful inside MCP client config:

```json
{
  "mcpServers": {
    "code-review-graph": {
      "command": "code-review-graph",
      "args": ["serve", "--tools", "detect_changes_tool,get_review_context_tool,get_impact_radius_tool,get_minimal_context_tool"]
    }
  }
}
```

## Slash commands

CRG ships three of its own:

- `/code-review-graph:build-graph` — build or rebuild from scratch.
- `/code-review-graph:review-delta` — review changes since last commit.
- `/code-review-graph:review-pr` — full PR review with blast-radius.

Wire these into your daily loop. `dotclaude`'s `pr-review` skill knows
to delegate to `:review-pr` when CRG is detected.

## Configuration

Exclude paths via `.code-review-graphignore` in repo root:

```
generated/**
*.generated.ts
vendor/**
node_modules/**
```

Note: in git repos CRG only indexes tracked files (`git ls-files`), so
`.gitignore` is honored automatically. Use `.code-review-graphignore` for
tracked files you want excluded, or when git isn't available.

Optional dependency groups:

```bash
pip install code-review-graph[embeddings]          # local sentence-transformers
pip install code-review-graph[google-embeddings]   # Gemini
pip install code-review-graph[communities]         # Leiden via igraph
pip install code-review-graph[wiki]                # LLM-summary wiki gen
pip install code-review-graph[all]                 # everything
```

For OpenAI-compatible self-hosted embedding endpoints (vLLM, LocalAI,
LiteLLM, Ollama in openai mode), set `CRG_OPENAI_BASE_URL`,
`CRG_OPENAI_API_KEY`, `CRG_OPENAI_MODEL`. Cloud-egress warning is
auto-skipped for `localhost` / `127.0.0.1` / `::1`.

**Stable embedding model warning.** Avoid `-preview` / `-beta` / `-exp`
model IDs for anything you'll keep — preview models can change weights
(different dimension → full re-embed). Prefer GA stable releases.

### Windows MCP gotcha

If you see `Invalid JSON: EOF while parsing` or
`MCP error -32000: Connection closed` on Windows: do **not** use a
`cmd /c` wrapper. Ensure `fastmcp >= 3.2.4`. Then point the config at
the `.exe` directly with the UTF-8 env var:

```json
"code-review-graph": {
  "command": "C:\\path\\to\\your\\venv\\Scripts\\code-review-graph.exe",
  "args": ["serve", "--repo", "C:\\path\\to\\your\\project"],
  "env": { "PYTHONUTF8": "1" }
}
```

## Output discipline (when synthesizing CRG results)

Same rule as graphify and brain-mcp: **synthesize, don't dump 28 tools'
worth of JSON.**

- Lead with **risk score** if `detect_changes_tool` returned one.
- Lead with **knowledge gaps** if the change touches an untested hotspot.
- Cite **named symbols** the user will recognize (function/file names),
  not internal node IDs.
- Quantify when proposing risk: *"This change touches 3 files but the
  blast radius is 47 callers across 6 modules — recommend a smoke test
  on the auth flow."*
- When suggesting tests, point to the **specific gap** (`get_knowledge_gaps_tool`
  identified it), not a generic "add tests."

## Pitfalls

- **Stale graph after `git pull`.** If you didn't commit your own
  changes, the auto-hook didn't fire. Run `code-review-graph update`
  or just save a file.
- **Single-file change overhead.** Cited honestly in the CRG README:
  on tiny edits to small packages the structural context can exceed
  the raw file. Default to reading the file directly for one-line edits.
- **Conservative impact analysis.** CRG over-predicts (precision ~0.38,
  recall 1.0 in benchmarks). It will flag files that *might* be affected.
  This is the safer trade-off — better a false alarm than a missed break.
- **Search ranking is the weakest link.** MRR ~0.35 — the right answer
  is usually in top-4 but not always #1. Don't trust rank-1 blindly on
  ambiguous queries; eyeball the top several.
- **Flow detection is uneven across languages.** Reliable on Python
  (FastAPI / httpx framework patterns recognized). JavaScript and Go
  flow detection is partial.
- **Don't double-wire.** If CRG is already installed globally via
  `code-review-graph install`, you do NOT need the project-scoped
  `.mcp.json` entry too. Pick one.

## When to use the project-scoped `.mcp.json` entry instead

`core/mcp/optional/code-review-graph.mcp.json` registers
`code-review-graph serve` as an MCP server scoped to this project. Use
it when:

- You want to **filter the 28 tools** for this repo specifically (via
  `--tools` arg in the entry).
- You want a **specific repo** wired (via `--repo` arg).
- You're on an agent that didn't get auto-configured by
  `code-review-graph install`.

For the common case the global install is simpler — the project-scoped
entry is opt-in.

## See also

- `core/mcp/skills/graphify/SKILL.md` — the exploration counterpart.
- `core/skills/pr-review/SKILL.md` — delegates to CRG's review tools when wired.
- `core/skills/legacy-modernizer/SKILL.md` — uses CRG for safe refactor blast-radius.
- `core/hooks/conductor-brief.sh` — surfaces CRG availability + DB freshness on cold start.
