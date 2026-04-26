---
name: learnings-log
description: Append-only project memory written by the agent for the next agent. Captures gotchas, dead ends, non-obvious decisions, and "this looks wrong but is intentional because..." in `.claude/learnings.md`. Zero deps, plain markdown, in git. Composes with project-state.md (current snapshot) and brain-mcp (full history) to keep continuity high even when no MCPs are installed.
source: core
triggers: log a learning, write this down, remember this, gotcha, capture insight, /learn, /learning, dont let me forget, this surprised me, future me, ralph, learning log
---

# learnings-log

A Ralph-style append-only log of what the agent learned the hard way,
stored as plain markdown at `.claude/learnings.md`. Read on cold starts
by every agent. Written when a session uncovers something the next
agent would otherwise re-discover (and re-suffer through).

## The three-file model

dotclaude's continuity layer has three artifacts. Don't mix them up:

| File | Purpose | Lifecycle |
|---|---|---|
| `.claude/project-state.md` | "Where am I right now? What's next?" | Snapshot — overwritten each conductor pass |
| `.claude/learnings.md` (this skill) | "What did I learn that the next agent should know?" | Append-only — entries accumulate |
| `brain-mcp` (optional) | "Everything I've ever discussed, searchable" | Auto-indexed conversations |

`project-state.md` answers *what to do next*.
`learnings.md` answers *what not to fall into again*.
`brain-mcp` answers *what did I think about X six weeks ago*.

When `brain-mcp` is **not** installed, the learnings log carries the
full weight of "remember non-obvious things across sessions." It's the
zero-dependency version of cross-session memory.

When `brain-mcp` **is** installed, brain-mcp will index this file like
any other markdown — so the entries become both directly readable
(cheap, deterministic) and semantically searchable (rich). Both wins,
no conflict.

## When to append an entry

Append when **any of these are true**:

1. **You learned the codebase has a non-obvious convention.**
   - "Tests in `tests/integration/` need `RUN_INTEGRATION=1`."
   - "The `_v2` suffix means migration target, not deprecated."
2. **You hit a dead end that the next agent might repeat.**
   - "Tried fixing `X` by patching `Y` — actually broke `Z`. Real fix lives in `W`."
3. **You discovered a hidden coupling.**
   - "Touching `User.email` requires reindexing in `search/users.py`."
4. **The user corrected you in a way that generalizes.**
   - "Don't use `print()` for diagnostics in this repo — it goes to the customer's console."
5. **You found a stale doc / config / comment.**
   - "`.env.example` says 30d session TTL — actual default is 7d."
6. **Something looks wrong but is intentional.**
   - "The double-encoding in `legacy/serializer.py` is required for the iOS client."

## When NOT to append

- **Don't log normal progress.** "Implemented function `foo`" is not a learning. That's a commit message and lives in `project-state.md` under "Current focus".
- **Don't log noise.** "Fixed a typo." "Renamed a variable." Skip it.
- **Don't log things grep would have found.** "There's a function called `parseInvoice`." That's discoverable. A learning is what's *not* obvious from reading the code.
- **Don't log secrets.** Ever. No tokens, keys, internal URLs, customer data, even in examples.
- **Don't log "the user prefers tabs" once and forget about it.** That's a `core/rules/` concern — promote it to a project rule instead.
- **Don't log what's already in `.claude/rules/`.** Rules are prescriptive. Learnings are descriptive of discovered reality.

If you're unsure whether something belongs, default to skipping. The
log is high-signal because the bar to add is high.

## Entry format

```markdown
## YYYY-MM-DD — short topic phrase

One-to-three lines on what was learned and why it matters. Be specific
— filenames, symbols, function names, PR numbers if relevant.

tags: area, area, area
```

**Required:**
- ISO date heading prefixed with `## ` (so it's grep-able and renders).
- Short topic — like a commit subject. Title-case optional, lower-case fine.
- Body that names actual files or symbols when applicable.

**Optional:**
- `tags:` line at the end, comma-separated. Helps later grep / brain-mcp queries.

**Newest entries go at the top.** This is opposite of a chronological
journal — but it's how `conductor-brief.sh` shows recent entries
cheaply, and it's how the user reads the file when they open it.

### Good examples

```markdown
## 2026-04-22 — auth: refresh tokens are 7-day, not 30-day

The `.env.example` says 30d but the actual TTL is `REFRESH_TTL_SECONDS`
env var, default 604800. See `apps/api/auth/refresh.py:42`. Code that
hard-codes 30d (search:  grep -rn "30 \* 24") will silently issue
sessions that outlive the cookie.

tags: auth, security, env-vars
```

```markdown
## 2026-04-19 — never call `pip install` inside the airflow container

The container has a frozen lockfile baked at build time. `pip install`
"succeeds" but installs to a layer that's discarded on next start.
Add deps to `requirements.airflow.txt` and rebuild the image instead.
Lost ~2h on this. Hit on PR #418.

tags: airflow, docker, deps
```

```markdown
## 2026-04-15 — graphify community 4 is the auth boundary, not "auth"

The Leiden cluster labeled "auth" actually spans auth + RBAC + audit
logging because the audit middleware imports the user model. Don't
refactor "auth" assuming community 4 is just authentication — touch
audit code and you'll re-cluster the whole community.

tags: graphify, auth, refactor
```

### Bad examples (don't do these)

```markdown
## 2026-04-22 — fixed bug

What bug? Where? Why is this a learning vs a commit message? Skip.
```

```markdown
## 2026-04-22 — user's API key is sk-abc...

Never. Don't log secrets, even in "I tried this and it didn't work" notes.
Redact to `<redacted>` before writing.
```

```markdown
## 2026-04-22 — there is a function called processInvoice

Grep finds this. Not a learning. Skip.
```

## Reading the log on cold start

The conductor brief auto-prints the **most recent 3 entries** on every
SessionStart (via `conductor-brief.sh`). For older entries, the agent
opens the file directly:

- "What's stuck in this repo?" → grep `tags:` lines.
- "Has anyone hit X before?" → grep the topic word across `## ` headings.
- "What did we learn about auth?" → grep `tags: auth` or topic phrases.

If the user is on an agent without SessionStart hooks, `CLAUDE.base.md`
instructs the agent to read `.claude/learnings.md` directly on cold
start (top 3 entries minimum).

## Pruning

The log is append-only **in spirit**, not absolutely. Prune when:

- An entry is **superseded** — the gotcha was fixed at the source. Move
  it to a `## Archived (no longer current)` section at the very bottom
  of the file with a one-line note on why it was archived.
- The log exceeds **~200 entries** or **~30 KB**. Then:
  - Move entries older than 6 months whose `tags:` haven't been
    referenced in any recent commit/PR into `archived` section.
  - Or split: `.claude/learnings.md` (recent), `.claude/learnings.archive.md`.

Never silently delete entries. Archived is fine; deleted is amnesia.

## Composing with brain-mcp

When `brain-mcp` is installed, it indexes `.claude/learnings.md`
automatically (it indexes all conversation + markdown logs in standard
locations). You then have two retrieval paths:

- **Fast & deterministic:** `cat .claude/learnings.md | head -n 80`
  — grabs ~10 most recent entries, never lies, no LLM in the loop.
- **Rich & semantic:** `brain.semantic_search("auth refresh token gotchas")`
  — pulls related entries from this log *and* prior conversations
  across all your projects, with similarity ranking.

Use both. The log is the *curated, dense* memory; brain-mcp is the
*comprehensive, raw* memory. The conductor synthesizes both.

## Writing discipline

- **One thought per entry.** If you've got two things to log, write two
  entries. Helps grep, helps pruning, helps the next agent skim.
- **Past tense.** "Discovered X." "Tried Y, broke Z." Not "X is the case."
  This file documents *what was learned*, which is inherently historical.
- **Name the file/symbol.** If your entry doesn't name a file path or
  symbol, ask yourself: is this actually a project rule? Promote to
  `.claude/rules/project.md` if so.
- **Surface the cost.** "Lost 2h on this" or "broke prod" or "trivially
  reproducible by..." — gives the next agent a sense of how seriously
  to take the entry.

## Ask permission for big appends

Single-entry appends during a session: just do it (and mention it
briefly in your reply: "logged a learning about X"). For bulk
appends — say, the user just walked you through 5 things at once —
draft the entries, show them to the user, and ask before writing.

The log is high-trust. Don't fill it with junk.

## Reference

- `references/learnings-template.md` — canonical template + a worked
  example of a populated file with several entry styles.

## See also

- `core/skills/project-conductor/` — owns the cold-start brief that
  surfaces the top-N learnings.
- `core/mcp/skills/brain-mcp/` — semantic retrieval across all your
  conversation history (when installed). Composes with this log.
- `.claude/rules/project.md` — for things that are *prescriptive*
  rather than discovered (style preferences, naming conventions).
