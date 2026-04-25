# `.claude/project-state.md` — schema and example

The canonical, agent-agnostic handoff file. Lives in every project's
`.claude/project-state.md`. Plain Markdown. No tool-specific syntax. The
whole point: a different agent on a different platform can read this file
and pick up where the last agent left off.

## Why a flat file (and not a database)

- **Portable.** Claude Code, Cursor, Codex, OpenCode, Gemini CLI, Aider —
  every agent already reads files in `.claude/`. No MCP required.
- **Diffable.** Lives in git. Every change is a commit. You can see how
  the project's state evolved.
- **Trivially mergeable.** Two agents on two branches can both update it;
  conflicts are obvious.
- **Survivable.** No service to run. No DB to migrate. No format upgrade
  to worry about in a year.
- **Composable with brain-mcp / graphify.** This file holds *intent*.
  brain-mcp holds *conversation*. graphify holds *structure*. Three
  artifacts, three concerns. Don't conflate.

## Where it lives

```
<repo root>/
└── .claude/
    └── project-state.md
```

Commit it. Treat it like a CHANGELOG that's about *the future* instead of
the past.

## The schema

```markdown
# Project state

- **Phase:** <greenfield | building | established | maintenance | migration>
- **Updated:** <ISO 8601 date> by <agent name and model, e.g. "Claude Code · sonnet-4.5">
- **Driver skill:** <name of the skill that drove the most recent substantive work>
- **Brain domain:** <the domain string used with brain-mcp's tunnel_state for this project, if applicable>

## Current focus

<1-3 sentences. What is actively being worked on RIGHT NOW. Not "the project's purpose" — the immediate next thing.>

## Recent decisions

- [YYYY-MM-DD] <decision> — <one-line rationale>
- [YYYY-MM-DD] <decision> — <one-line rationale>

(Keep ~5 most recent. Older decisions move to git log / brain-mcp.)

## Open questions

- <question> — <whose call this is, what it's blocking>
- <question> — <…>

## Next steps

1. <next concrete action — small enough to act on>
2. <…>
3. <…>

## Don't lose

<gotchas, half-finished migrations, sleeping bugs, environment quirks, things-that-look-broken-but-aren't. The "if you do nothing else, read this" section.>

## Areas (optional)

Use only when the repo has multiple phases at once.

| Area | Phase | Notes |
|---|---|---|
| `core/` | established | … |
| `auth/v2/` | migration | … |

## Handoff

<Anything an agent on a DIFFERENT tool — moving from Claude Code to Cursor,
or vice versa — needs to know that isn't already covered above. Tool-specific
gotchas, MCP server status, expected commands, etc.>

---
_Last conductor pass: <ISO date>_
```

## A worked example

```markdown
# Project state

- **Phase:** building
- **Updated:** 2026-04-25 by Claude Code · sonnet-4.5
- **Driver skill:** ship
- **Brain domain:** invoice-service

## Current focus

Wiring the invoice PDF generator into the existing email pipeline.
PDF generation works in isolation; integration into `EmailQueueWorker`
is half-done — the worker reads the right job but the renderer hasn't
been called yet.

## Recent decisions

- [2026-04-23] Use `xlsxwriter` for spreadsheet exports, not openpyxl — perf at 50k rows.
- [2026-04-22] Render PDFs synchronously in the worker, not in a separate service. Latency is fine; cross-service complexity isn't worth it.
- [2026-04-20] Adopt EARS-format functional reqs going forward (per `feature-forge`).

## Open questions

- Do we cache rendered PDFs by content hash, or re-render every time? — Performance call. Blocks deciding on storage.
- Should failed renders retry? If yes, how many times? — Ops call. Blocks merging the worker change.

## Next steps

1. Call `InvoicePdfRenderer.render(job.invoice_id)` inside `EmailQueueWorker.process()`.
2. Decide caching policy (open question above) and either add S3 lookup or skip.
3. Add an integration test that exercises the worker → renderer → email path end-to-end.
4. PR.

## Don't lose

- The `pyseto` token expiry is hardcoded to 24h in `auth/tokens.py`. We meant to make it configurable but punted. Bites people who run the worker overnight.
- Local dev: `redis-server` must be on `:6380`, NOT `:6379` — a docker-compose conflict with the analytics stack.
- The PDF templates use Jinja-async (`starlette_async_jinja`); calling them from sync code will look like it works in tests and silently truncate output in prod. Always `await render()`.

## Handoff

If you're picking this up in Cursor: brain-mcp is wired globally on this
machine, so `tunnel_state(domain="invoice-service")` should give you the
last ~3 sessions of context. graphify-out/ is fresh as of 2026-04-23 —
god nodes are `EmailQueueWorker`, `InvoicePdfRenderer`, `JobRepo`. If you
rebuild graphify, exclude `vendor/` (we accidentally indexed it once and
the report became useless).

---
_Last conductor pass: 2026-04-25_
```

## Conventions

- **Length.** One screen. If it's longer, prune. Old decisions go to git
  log / brain-mcp.
- **Updated by every agent that does substantive work.** A single typo fix
  doesn't need an update. A merged feature does.
- **The `Updated:` line is mandatory.** Says who/what last touched it. The
  next agent uses this to decide how much to trust the file.
- **Don't predict.** "Next steps" is what's *up next*, not a roadmap. Three
  to five items, max. The roadmap belongs in `ROADMAP.md` or your tracker.
- **Don't editorialize.** This file is operational. Save the discussion for
  the chat or for an ADR.

## Keeping it honest

The conductor should re-read this file at the start of every session and
ask: *"Does the user agree with this snapshot?"* If they say no, update it
before doing anything else. A stale `project-state.md` is worse than none —
it gives the next agent false confidence.

## Per-language `.gitignore` interaction

Don't add `.claude/project-state.md` to `.gitignore`. Commit it. The whole
point is that it travels with the repo — through clones, through agent
switches, through new contributors.

If your team objects to committing files in `.claude/`, move it to
`docs/project-state.md` and tell every agent (via the project's CLAUDE.md
/ AGENTS.md / .cursorrules) to look there instead. The location is
configurable; the discipline isn't.
