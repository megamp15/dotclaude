# learnings.md template

This is the canonical shape of `.claude/learnings.md`. `dotclaude-init`
seeds a project's file from this template if one doesn't already exist.

## Empty seed (what init writes)

```markdown
# Learnings

Append-only log of non-obvious things discovered while working on this
project. Newest entries on top. One thought per entry. See
`.claude/skills/learnings-log/SKILL.md` for the full discipline.

<!--
Format:
## YYYY-MM-DD — short topic phrase

Body (1-3 lines). Name actual files and symbols.

tags: area, area
-->

## <today> — adopted dotclaude

Project initialized with dotclaude. Continuity layer wired:
project-state.md (snapshot), learnings.md (this file, accumulated
gotchas), and brain-mcp (semantic history, optional). Conductor brief
runs on every SessionStart and surfaces the top 3 entries below.

tags: meta, dotclaude
```

That single seed entry exists for two reasons: (1) it makes the file
non-empty so the conductor brief has something to print, and (2) it's
a small reminder that *this is what an entry looks like* — pattern by
example.

## Worked example (what a mature file looks like)

```markdown
# Learnings

Append-only log of non-obvious things discovered while working on this
project. Newest entries on top. One thought per entry. See
`.claude/skills/learnings-log/SKILL.md` for the full discipline.

## 2026-04-22 — auth: refresh tokens are 7-day, not 30-day

The `.env.example` says 30d but the actual TTL is `REFRESH_TTL_SECONDS`
env var, default 604800. See `apps/api/auth/refresh.py:42`. Code that
hard-codes 30d (search:  grep -rn "30 \* 24 \* 3600") will silently issue
sessions that outlive the cookie.

tags: auth, security, env-vars

## 2026-04-19 — never `pip install` inside the airflow container

The container has a frozen lockfile baked at build time. `pip install`
"succeeds" but writes to a layer that's discarded on next start.
Add deps to `requirements.airflow.txt` and rebuild the image instead.
Lost ~2h on this. Hit on PR #418.

tags: airflow, docker, deps

## 2026-04-15 — graphify community 4 spans auth + RBAC + audit

The Leiden cluster labeled "auth" actually contains audit middleware
because it imports the user model. Refactoring "auth" assuming
community 4 = authentication will re-cluster the whole community.
See `graphify-out/GRAPH_REPORT.md` line ~110.

tags: graphify, auth, refactor

## 2026-04-10 — `User.email` change requires search reindex

`apps/search/users.py` builds an inverted index keyed on email at
import time. Changing `User.email` schema or normalization without
running `python -m apps.search.reindex_users` leaves the index stale.
No error, just wrong search results.

tags: search, users, hidden-coupling

## 2026-04-08 — double-encoding in legacy/serializer.py is intentional

The iOS client (versions <4.2) double-decodes payloads. The matching
double-encode in `legacy/serializer.py:encode_payload` looks like a
bug — leave it. There's a `# do not "fix": iOS <4.2 contract` comment
that's easy to miss. Removing it broke prod in Q3 2025.

tags: legacy, ios, gotcha

## 2026-04-01 — adopted dotclaude

Project initialized with dotclaude. Continuity layer wired:
project-state.md (snapshot), learnings.md (this file, accumulated
gotchas), and brain-mcp (semantic history, optional).

tags: meta, dotclaude

---

## Archived (no longer current)

## ~~2026-03-15~~ — `redis-py` 4.x breaks on async context managers

Resolved on PR #389 by upgrading to `redis-py` 5.1 which fixes the
underlying issue. Keeping for git-archaeology purposes.

tags: redis, archived
```

## Notes on the example

- **Six entries plus one archived.** That's a typical mature file —
  not an empty husk, not a 50-entry wall of text.
- **Topics span auth, infra, structural insight, hidden coupling, and
  intentional weirdness.** Each entry is a thing the next agent would
  re-discover painfully without it.
- **Each names a file/symbol.** Without that, the entry would be a
  vague worry rather than an actionable note.
- **Tags are short and consistent.** A handful of tags reused across
  many entries beats a unique tag per entry.
- **Archived section at the bottom.** Rare. Used when an entry is
  genuinely no longer current but still worth a paper trail.

## Anti-template (what NOT to write)

```markdown
# Learnings

## 2026-04-25 — refactor

Refactored stuff today.

## 2026-04-24 — TODO

Need to fix the auth thing eventually.

## 2026-04-23 — debug

Spent the day debugging.

## 2026-04-22 — meeting notes

Talked with Sarah about the migration.
```

Every entry above is wrong:

- "refactored stuff" — no detail, no file, no learning. This is a
  commit message at best.
- "TODO" — that's `project-state.md`'s "Next steps" section, not here.
- "debug" — what bug? what fix? what learning? skip.
- "meeting notes" — those go in a doc, not in a learnings log. The
  learning would be the *outcome* of the meeting, named concretely:
  "decided to migrate users in batches of 1000 — anything bigger
  trips the rate limiter on the legacy API."

If you find yourself writing entries like the bad examples, stop and
either (a) write a real entry with a file/symbol/cost named, or (b)
skip — it doesn't belong here.
