<!-- source: core -->
# CLAUDE.md

Universal instructions that apply in every project. Stack- and
project-specific sections are appended below this by `dotclaude-init`.

## Continuity (read this first, every session)

This project uses dotclaude's continuity layer. Four artifacts
collectively guarantee that you can pick up exactly where the last
session left off — even if that session was on a different agent
(Claude Code, Cursor, Codex, OpenCode, Gemini CLI, ...).

1. **`.claude/project-state.md`** — the durable, agent-agnostic handoff
   file. Read it first. Treat its `Phase`, `Current focus`, and `Next
   steps` as authoritative until the user says otherwise. The conductor
   SessionStart hook also injects it, so you'll see it in the session
   context — but if you're reading this in an agent without that hook,
   open the file directly.

2. **`.claude/learnings.md`** — append-only project memory. Non-obvious
   gotchas, hidden couplings, "looks wrong but is intentional because…"
   notes. Read at minimum the top 3 entries on cold start (the
   conductor brief surfaces them automatically). When you discover
   something the next agent would re-suffer through, append a new
   entry per the discipline in
   `.claude/skills/learnings-log/SKILL.md`. This file is the
   zero-dependency baseline for cross-session memory — it works without
   any MCP installed.

3. **`brain-mcp`** (if wired) — cross-agent persistent memory. Indexes
   conversations from every AI tool the user runs locally, including
   `learnings.md`. Before asking the user what to do on a cold start,
   call:
   - `brain.context_recovery(domain=<this project's name>)`
   - `brain.open_threads()`

   If `brain-mcp` is not in your MCP list, skip silently — don't error
   out, don't apologize, don't pretend to use it. The conductor brief
   will tell you whether it's available. The `learnings.md` log is a
   high-signal substitute when brain-mcp is absent.

4. **`graphify-out/GRAPH_REPORT.md`** (if present) — structural map of
   the codebase: god nodes, communities, surprising cross-domain edges.
   Skim this before any non-trivial structural change. If it's stale
   (>14 days) or absent and the change is large, run `graphify ./` first.

**The session-end discipline.** When meaningful work happens:

- A decision made, feature shipped, refactor landed, or new question
  opened → update `.claude/project-state.md`. Keep it short, one screen.
- Something non-obvious discovered (gotcha, hidden coupling, dead end,
  intentional weirdness) → append to `.claude/learnings.md`. One thought
  per entry, name the file/symbol.

The next agent on any platform reads both files. Schemas live in
`.claude/skills/project-conductor/SKILL.md` and
`.claude/skills/learnings-log/SKILL.md`.

**Don't conflate the artifacts.** project-state.md holds *current
intent*. learnings.md holds *accumulated discovery*. brain-mcp holds
*full conversation history*. graphify holds *structure*. Four
artifacts, four concerns, one re-entry brief.

## Working principles

- **Scope discipline.** Do what was asked, nothing more. If you spot a
  related issue, mention it — don't silently fix it in the same change.
- **Prefer editing over creating.** Don't make a new file when an
  existing one is the right home for the change.
- **Read before writing.** Always inspect the current file before you
  edit it. Don't guess at contents.
- **Small, verifiable steps.** Prefer 5 small changes you can verify
  over one large change you can't.
- **Match existing style.** Follow the patterns already in the codebase
  — naming, structure, error handling, test shape — even if you'd have
  chosen differently on a blank slate.

## Communication

- Lead with what changed and why. Skip preamble like "I'll now...".
- Surface risks, assumptions, and alternatives you considered and rejected.
- When you don't know, say so. Don't pattern-match into a confident guess.
- Ask one question at a time when clarification is needed. Never
  interrogate the user with a wall of questions.

## Code comments

- Explain *why*, not *what*. The code already shows what.
- No narration comments (`// increment counter`, `# return result`).
- Document non-obvious trade-offs, constraints, and gotchas.
- Leave `TODO(owner): ...` comments only when genuinely incomplete —
  with a handle so the owner is clear.

## Editing and refactoring

- **Never mix behavior changes with refactors** in the same commit.
  Refactor first (tests still pass), commit, then change behavior.
- Never commit commented-out code. Delete it; git remembers.
- Never introduce dead code, unreachable branches, or unused imports.
- If a refactor grows unexpectedly, stop and report — don't sprawl.

## Testing

- New behavior needs a test that fails before the change and passes after.
- Never delete a failing test to "fix" a failure unless the test itself
  is demonstrably wrong. Explain why if you do.
- Running tests before declaring something done is not optional.

## Git & shipping

- Never commit unless asked explicitly.
- Never push unless asked explicitly.
- Never force-push to a shared branch.
- Never run destructive git commands (`reset --hard`, `clean -fdx`,
  `branch -D`) without confirmation.
- Commit messages describe *why* in the body; the subject line is the
  *what* in imperative mood.

## Guardrails

- Never write secrets (API keys, tokens, passwords) into any file.
  If the user pastes one, warn and redact.
- Never edit files matching `.env*`, `*.pem`, `*.key`, `*/secrets/*`,
  `*/credentials/*` without explicit confirmation.
- Never run commands that could be destructive on production data
  (direct DB writes, `DROP`, `DELETE ... WHERE 1=1`, `rm -rf /`).
- For any hard-to-reverse operation, confirm first.
