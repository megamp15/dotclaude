---
name: brain-mcp
description: Cross-agent persistent memory. Searches the user's accumulated conversations across Claude Code, Claude Desktop, Cursor, Windsurf, Gemini CLI in 12ms via 25 MCP tools (semantic_search, tunnel_state, what_do_i_think, context_recovery, open_threads, thinking_trajectory, ...). Use to recover prior context, surface dropped threads, and keep continuity when the user switches agents. 100% local, MIT.
source: core/mcp
triggers: where did I leave off, pick up where I left off, what was I working on, what do I think about, last week / last month I was, I keep forgetting, switching from claude to cursor, context recovery, open threads, brain
---

# brain-mcp

The user's brain across every AI tool they use. brain-mcp watches Claude
Code/Desktop, Cursor, Windsurf, and Gemini CLI conversation files and serves
their accumulated history as 25 MCP tools — locally, in milliseconds. This is
the dotclaude answer to "0 context loss when I move between agents."

Source: <https://github.com/mordechaipotash/brain-mcp> · <https://brainmcp.dev>
License: MIT · Local-only · No cloud, no accounts, no API costs.

## When to use

Reach for it whenever the user implies *"this is not the first time I've
thought about this"* or *"I'm coming back to this":*

| User signal | Tool to call |
|---|---|
| "Where did I leave off with X?" | `tunnel_state(domain="X")` |
| "What was I doing last week / on Tuesday?" | `conversations_by_date(date_or_range)` |
| "I keep forgetting to..." | `open_threads()` |
| "I was working on something about X..." | `semantic_search(query="X")` |
| "What do I think about X?" | `what_do_i_think(topic="X")` |
| "Should I switch to Y?" / committing to a direction | `context_recovery(domain="X")` then `alignment_check(decision="...")` |
| "Has my thinking on X changed?" | `thinking_trajectory(topic="X")` |
| Starting any new topic | One light `semantic_search(topic)` first — they may have already explored it |
| User seems stuck or repeating themselves | `thinking_trajectory(topic)` — show the prior arc |
| Returning after silence on a project | `context_recovery(domain)` for a re-entry brief |

Also call **proactively, without being asked**, in two situations:

1. The user mentions a project, person, library, or decision the model has no
   in-session context for. Do one `semantic_search` before asking clarifying
   questions — they may have explained it in a past session.
2. The session opens cold ("/clear" or fresh window) on an existing repo.
   Run `context_recovery(domain=<repo or project name>)` to bootstrap the
   re-entry brief before doing anything else.

## When NOT to use

- For every single message — context-poll once per topic, not per turn.
- For factual questions answerable from current files or web docs.
- To replace `core/skills/explain` for code that's right in front of you.
- For storing things the user *just* said in this session — that's working
  memory, not brain.

## The 25 tools, grouped

**Search (find by content):**
- `semantic_search(query)` — by meaning across all conversations.
- `search_conversations(query)` — keyword search, when the exact phrase matters.
- `unified_search(query)` — combined keyword + semantic.
- `search_docs(query)` — knowledge files / docs the user has indexed.
- `search_summaries(topic)` — search prior conversation summaries.

**Browse (find by location):**
- `get_conversation(id)` — read one conversation by id.
- `conversations_by_date(date_or_range)` — browse by time.

**Prosthetic (the high-leverage ones):**
- `tunnel_state(domain)` — *the load-game screen.* Mental save state for that domain: stage, open questions, decisions, recent activity.
- `tunnel_history(domain)` — full evolution of a domain.
- `switching_cost(from, to)` — quantified cost of switching focus.
- `dormant_contexts()` — topics they were working on and silently dropped.
- `thinking_trajectory(topic)` — how their views evolved (doubt → clarity, or reverse).
- `what_do_i_think(topic)` — synthesize their views from many conversations.
- `alignment_check(decision)` — check a proposed decision against their stated principles.
- `context_recovery(domain)` — full re-entry brief: recent activity, questions, key messages.

**Synthesis:**
- `open_threads()` — every unfinished thread, everywhere.
- `unfinished_threads(domain)` — detailed unfinished work per domain.
- `what_was_i_thinking(span)` — stream-of-consciousness reconstruction.

**Analytics / stats:**
- `cognitive_patterns()` — when and how the user thinks.
- `query_analytics()` — query-level usage analytics on their brain.
- `brain_stats()` — overview: counts, domains, sources.
- `trust_dashboard()` — data quality and coverage.

**Principles (the user's stored convictions):**
- `get_principle(key)` — retrieve a stored principle by key.
- `list_principles()` — list all stored principles.

**Integrations:**
- `github_search(query)` — search the user's GitHub activity.

## How to present results

Synthesize, don't dump. brain-mcp returns search hits; you turn them into
insight. The README is explicit about this and you should treat it as binding:

**Do:**
- Synthesize across hits: *"You explored this across 8 conversations and landed on X."*
- Be specific about provenance: *"In your March 12 Cursor session, you decided ..."*
- Surface contradictions: *"You said X in January, Y in March — want to reconcile?"*
- Connect dots: *"This relates to what you concluded about pricing last month."*
- Cite the source agent when relevant: *"Across 15 ChatGPT + 8 Claude + 3 Claude Code sessions ..."*

**Don't:**
- Don't say *"I searched brain-mcp"* — present the insight, not the plumbing.
- Don't expose tool names to the user.
- Don't dump 15 raw hits — 2-3 relevant findings beats a wall.
- Don't search for every message — only when context would genuinely help.

## Setup (one-time, per machine)

The recommended install is **global**, not per-project, because the whole
point is cross-project memory:

```bash
pipx install brain-mcp
brain-mcp setup
```

`brain-mcp setup` discovers your existing conversation directories
(Claude Code at `~/.claude/projects/...`, Cursor at the platform-specific
path, Windsurf, Gemini CLI), imports them, generates embeddings locally, and
writes the MCP entry into each agent's native config file (Claude Desktop,
Claude Code, Cursor, Windsurf). After that, restart each agent — done.

You can also wire specific clients only:

```bash
brain-mcp setup claude     # Claude Desktop + Code
brain-mcp setup cursor
brain-mcp setup windsurf
```

### When to use the project-scoped `.mcp.json` entry instead

This repo's `core/mcp/optional/brain-mcp.mcp.json` configures brain-mcp for a
single project's `.mcp.json`. Use it only if you want **a project-isolated
brain** (one repo, one brain, won't see other projects). In 95% of cases the
global install via `brain-mcp setup` is the right answer — don't double-wire
it or you'll get two brain servers competing.

## Sync

brain-mcp picks up new conversations automatically — no cron, no manual sync:

- On startup, it checks source directories before serving.
- Mid-session, it does a lazy `mtime` check every ~60 seconds when a tool is
  called and re-ingests if anything changed.

You can force a sync with `brain-mcp sync`.

## Privacy

- 100% local. All embeddings, all data, all queries.
- No cloud dependency. Works fully offline after setup.
- Anonymous telemetry can be disabled: `brain-mcp telemetry off`.

## Pitfalls

- **Don't search before listening.** If the user is mid-sentence, let them
  finish before you go fetch their history.
- **Don't recover stale plans verbatim.** `context_recovery` shows where
  they *were*. Confirm it's still where they want to be before acting on it.
- **Avoid memory loops.** If you find a contradiction, surface it as a
  question — don't pick a side silently.
- **Cold-start heuristic.** On the very first session of a project, the
  brain may have nothing useful. That's normal. Don't apologize, just proceed
  and let it accumulate.
- **Two brains is one brain too many.** If brain-mcp is wired both globally
  (via `brain-mcp setup`) and project-scoped (via `.mcp.json`), the agent
  sees two `brain` servers. Pick one.

## Preference vs alternatives

| Need | Prefer |
|---|---|
| Cross-agent conversation history (Claude/Cursor/Codex/Gemini) | **brain-mcp** |
| In-project structured notes / decisions / ADRs | Markdown in repo, then optionally Mem0 / Cognee for graph |
| Codebase structure & symbol relationships | `core/mcp/skills/graphify` |
| Within-session scratchpad | `core/mcp/skills/sequential-thinking-mcp` (`memory` MCP for K/V) |
| User's stated principles (durable rules they expect to be honored) | `brain-mcp.list_principles` / `get_principle` |
