---
name: graphify
description: Build and query a knowledge graph of the project — code, docs, papers, diagrams. Tree-sitter AST + LLM semantic extraction + Leiden community clustering. Use to understand unfamiliar repos, find god nodes and surprising cross-domain edges, plan large refactors, and answer structural questions in ~2k tokens instead of ~123k. MIT, local-first, multi-modal.
source: core/mcp
triggers: /graphify, build a graph, knowledge graph, code graph, repo map, repository map, god nodes, who calls this, who depends on, structural overview, what does this codebase look like, where should I look, surprising connections
---

# graphify

Turns the whole project — `.py`/`.js`/`.go`/`.java` source, `README` and
docstrings, PDFs, diagrams — into one queryable graph. Use it before any task
that needs to *see the shape of the codebase*, not just a few files.

Source: <https://github.com/safishamsi/graphify> · <https://graphify.net>
License: MIT · Python 3.10+ · Local-first · 71.5× token reduction reported.

## When to use

Reach for graphify when the question is **structural** rather than local:

- *"Where do I even start in this repo?"* → run graphify, read `GRAPH_REPORT.md`.
- *"What are the core abstractions?"* → graphify's god-node analysis.
- *"Who depends on `Foo`?"* → BFS subgraph from `Foo`.
- *"Which files would a refactor of `X` touch?"* → reverse-edges from `X`.
- *"Are there surprising cross-domain edges I should know about?"* → graphify's surprises section.
- *"How do these papers relate to the code?"* → multi-modal extraction across `papers/` + `src/`.
- *"This change feels load-bearing. Is it?"* → check the node's PageRank / degree.

Use it *once* at the start of a substantive task, then query the resulting
graph as you work. Don't rebuild on every turn.

## When NOT to use

- One-file edits where you already know the call site.
- Questions answerable by `grep`, `Glob`, `Read`, or the IDE's "find usages".
- Trivial repos (a handful of files) — overhead beats benefit.
- Anything outside the working tree (use brain-mcp for past conversations).
- During a hot debugging loop — use it before the loop, not inside it.

## Pick the right tool: graphify vs grep vs brain-mcp vs context7

| Task | Prefer |
|---|---|
| "Show me the shape of this codebase" | **graphify** |
| "Who calls `process_payment`?" | **graphify** (BFS) > grep |
| "What does this one function do?" | `Read` > grep |
| "Where is `MyClass` defined?" | `Grep` / `Glob` |
| "What did I decide about this last month?" | `core/mcp/skills/brain-mcp` |
| "How do I use Prisma's new migration API?" | `core/mcp/skills/context7-mcp` |

graphify is for *structure*. brain-mcp is for *history*. context7 is for
*external docs*. Don't mix them up.

## How to use

### Build the graph (once per project, refresh after large changes)

```bash
# Inside the project root
graphify ./
# or, with a bigger corpus including docs/papers
graphify ./src ./docs ./papers
```

Outputs land in `graphify-out/`:

- `GRAPH_REPORT.md` — human-readable audit report. **Read this first.** It
  lists god nodes, communities, surprises, and suggested questions.
- `graph.html` — interactive visualization (open in a browser).
- `graph.json` — persistent, queryable graph for tooling.
- `cache/` — incremental cache; safe to keep in `.gitignore`.

Add `graphify-out/cache/` (or all of `graphify-out/`) to `.gitignore` unless
you want the report committed.

### Query without rebuilding

Once the graph exists, use the slash commands graphify ships in its
own skill manifest:

- `/graphify query "<question>"` — natural-language question answered against the graph.
- `/graphify path <A> <B>` — shortest path between two nodes (e.g., function → function).
- `/graphify explain <node>` — explanation of a node's role and neighbors.

These work in Claude Code, Codex, and OpenCode out of the box. Other agents
that can shell out can call `graphify query "..."` directly.

### Read the report before diving in

The structure of `GRAPH_REPORT.md`:

1. **God nodes** — highest-degree symbols. These are the load-bearing pieces.
   Touching them is high-impact and high-risk; reading them is high-value.
2. **Communities** — Leiden-detected clusters. Each community is a "subsystem".
   Mention them by community label when talking to the user (*"the auth
   community"*, *"the ingestion community"*) — it gives them a shared map.
3. **Surprises** — unexpected cross-community edges. These are the most
   valuable diagnostic output. A `DigestAuth → Response` edge means
   something is leaking across boundaries; surface it.
4. **Suggested questions** — graphify's own hint at what to ask next. Use
   them as conversation starters when planning a refactor.

## Setup (one-time per machine)

```bash
# Note the double 'y' in the package name; CLI command is still `graphify`
pip install graphifyy
graphify install
```

`graphify install` writes the skill manifest (`skill-claude-code.md`,
`skill-codex.md`, `skill-opencode.md`) into your agent's skills directory so
the slash commands are immediately available.

Graphify needs an LLM for the semantic-extraction step but **does not bundle
one** — it uses whatever API key is already configured for the active agent.
Per Graphify's docs, only **semantic descriptions** of files are sent
upstream, never raw source. If your repo is sensitive enough that even
descriptions are a concern, run graphify against a local model (Ollama,
vLLM) — see `homelab-infra` and `llm-serving` skills.

### When to use the project-scoped `.mcp.json` entry instead

`core/mcp/optional/graphify.mcp.json` registers `graphify serve` as an MCP
server. Use it if you want graphify queries to flow through the MCP protocol
rather than through the CLI / slash commands. For most projects the CLI
path is simpler — the MCP entry is opt-in.

## Output discipline

When you've queried graphify, present results the same way you would for
brain-mcp: **synthesize, don't dump.**

- Quote the god nodes by name; they're the user's mental anchor points.
- Lead with surprises. *"Heads-up: graphify flagged a `Logger → DBSession`
  edge that crosses your auth and persistence communities. Probably worth a
  look before the refactor."*
- Translate community labels into the user's language. *"The 'inference'
  community is your `serving/` package."*
- Cite numeric weight when proposing risk: *"This function has incoming
  degree 47. Changing its signature will ripple."*

## Pitfalls

- **Stale graph.** After a large refactor, rebuild. Cached graphs lie.
- **Tiny repos.** Don't run graphify on a 5-file project — overhead beats
  benefit, and the LLM cost isn't free.
- **Misleading god nodes.** A god node can be a util module that *should* be
  central. Confirm before flagging it as a problem.
- **Graphify is not a code reader.** It surfaces structure; you still have
  to `Read` the actual file to make a change.
- **Don't double-wire.** If the user has graphify wired both via the CLI
  skill manifest and via the project's `.mcp.json`, pick one. Two doors
  to the same room is just confusing.

## Worked-example sanity numbers

From graphify's own corpus, useful as ballpark:

- Small library (httpx, ~6 files) → 144 nodes, 330 edges, 6 communities. Build is seconds.
- Mixed code+papers corpus (~52 files, ~92k words) → 285 nodes, 340 edges, 53 communities. ~1.7k tokens per query vs ~123k naive (71.5× reduction).
- Large corpus (~500k words) → BFS subgraph queries stay around ~2k tokens vs ~670k naive.

If your numbers are wildly off these (e.g., 10k nodes from a small repo, or
a 30k-token query), something is misconfigured — usually graphify is
crawling a `node_modules/`, `.venv/`, or build output that should be in the
ignore list.
