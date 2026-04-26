---
name: project-conductor
description: Lifecycle-aware orchestrator for any project. Detects the current phase (greenfield, building, established, maintenance, migration), routes to the right downstream skill (feature-forge, ship, legacy-modernizer, etc.), and maintains a portable .claude/project-state.md that survives across sessions and across agents (Claude Code, Cursor, Codex, ...). Pairs with brain-mcp (history) and graphify (structure) to deliver a re-entry brief on cold starts.
source: core
triggers: /conduct, /project, /resume, /reentry, /pickup, where am I, where did we leave off, what's the state, project state, lifecycle, phase of this project, switch agent, moving to cursor, moving to codex, coming back to this project
---

# project-conductor

The orchestrator skill. When the user opens a project — fresh, mid-stream,
inherited, or returning after a break — `project-conductor` figures out
**what phase it's in**, **what should happen next**, and **which other skill
should drive**. It also writes the durable handoff file (`.claude/project-state.md`)
that lets a different agent pick up where this one left off.

## Activation (you don't have to ask for it)

This skill is wired in three places:

1. **SessionStart hook** (default for Claude Code): every new session,
   `.claude/hooks/conductor-brief.sh` injects the re-entry brief
   automatically — `.claude/project-state.md`, brain-mcp / graphify
   availability, a phase hint. The agent sees this *before* the user
   types anything.
2. **`CLAUDE.md` Continuity section**: every agent (Claude Code, Cursor,
   Codex, OpenCode, Gemini CLI, ...) is instructed to read
   `.claude/project-state.md` and call `brain-mcp` on cold start. This
   is the cross-agent guarantee — if a hook isn't supported, the
   instruction is.
3. **`/dotclaude-resume` command** + `scripts/dotclaude-resume.sh`:
   manual fallback for agents without SessionStart hooks, or for the
   user when context drops mid-session.

So: the conductor *brief* runs automatically. The conductor *skill*
(this file) drives when the user explicitly asks "where are we", or
when phase ambiguity needs a real conversation, or when state needs
updating at the end of substantive work.

> **See also:**
>
> - `core/mcp/skills/brain-mcp/` — cross-agent conversation history
> - `core/mcp/skills/graphify/` — structural codebase graph
> - `core/skills/feature-forge/` — greenfield workshop
> - `core/skills/spec-miner/` — reverse-engineer specs from code
> - `core/skills/legacy-modernizer/` — evolve untrusted code
> - `core/skills/ship/` — daily shipping discipline
> - `core/skills/pr-review/`, `core/skills/refactor/`, `core/skills/debug-fix/`

## When to use

- **Cold start on any repo** — including ones you've been in before.
- **User asks "where are we?"** or any variant ("where did we leave off",
  "what's left", "pick up where we left off").
- **Switching agents** — the user moves from Claude Code to Cursor to Codex
  and wants continuity. Run conductor at the start of the new session.
- **Phase ambiguity** — the user says "I'm not sure if we're still in design
  or already implementing" or you can't tell whether to use `feature-forge`
  or `ship`.
- **Returning after silence** — repo is the same, but it's been a week+ and
  context evaporated.
- **Inherited code** — first time touching a repo someone else built.

## When NOT to use

- Mid-task. Once a downstream skill is running, don't keep conducting — let
  it work.
- Trivial one-off scripts (write the script, move on).
- Pure questions about external libraries (use `context7-mcp` directly).

## Core workflow

### 1. Re-entry brief (always, on a cold start)

Before doing anything substantive, build a re-entry brief from three sources
in parallel:

1. **Local state** — read `.claude/project-state.md` if it exists.
2. **History** (if brain-mcp wired) — `context_recovery(domain=<repo name>)`
   and `open_threads()`. See `core/mcp/skills/brain-mcp/SKILL.md`.
3. **Structure** (if graphify wired and graph is fresh) — read
   `graphify-out/GRAPH_REPORT.md` if present. See `core/mcp/skills/graphify/`.

Synthesize these into a 5-7 line brief and surface it to the user *before*
asking what they want to do. Never dump three raw outputs — pick the 2-3
things that actually matter.

If none of those sources exist, that's fine — note it ("first session on
this repo, no prior state") and proceed to phase detection.

### 2. Phase detection

Use cheap, deterministic heuristics — **not** LLM judgment when you can
avoid it. Full table in `references/lifecycle-phases.md`. Quick decision:

```
git log --oneline | wc -l        →  commit count
git tag                          →  any release tags?
ls tests/ test/ __tests__/       →  is there a test suite?
date of last commit              →  staleness
```

| Signal | Phase |
|---|---|
| ≤3 commits, no tests, mostly README | **greenfield** |
| Active commits, growing tests, no release tag | **building** |
| Release tags exist, regular commits, healthy CI | **established** |
| Last commit > 90 days, sparse tests, old deps | **maintenance** |
| Parallel `_v2` / `_new` paths, feature-flag clusters, in-flight rewrite | **migration** |

Edge cases (a `_v2` directory in a greenfield repo, an established repo in
maintenance mode) live in the reference. When two phases tie, surface that
ambiguity to the user — *don't* silently pick one.

### 3. Route to the driver skill

Once the phase is clear, the conductor steps aside and the right downstream
skill drives. The conductor doesn't do the work — it picks who does.

| Phase | Default driver | Common companions |
|---|---|---|
| **greenfield** | `feature-forge` | `architecture-designer`, `api-designer` |
| **building** | `ship` (with `tdd` if test-first) | `pr-review`, `commit`, `refactor` |
| **established** | task-dependent: `ship` / `pr-review` / `refactor` / `debug-fix` | domain skill (`postgres-pro`, `react-expert`, …) |
| **maintenance** | `legacy-modernizer` | `spec-miner`, `test-master`, `debug-fix` |
| **migration** | `legacy-modernizer` | `chaos-engineer`, `pr-review`, domain skill |

If the user has stated an explicit task, route directly to the task's skill
and skip the routing offer.

### 4. Update `.claude/project-state.md`

At the end of any session that produced meaningful change (a decision, a
shipped feature, a refactor, a new question), update the state file. Schema
is fixed — see `references/project-state-template.md`. The point is that
*the next agent, on any platform, can pick up by reading this one file.*

This file is **agent-agnostic by design.** It's plain Markdown, lives in
`.claude/` because that's where every agent already looks, and contains no
tool-specific syntax.

## The `.claude/project-state.md` schema (summary)

Full template lives in `references/project-state-template.md`. The shape:

```markdown
# Project state

- **Phase:** <greenfield|building|established|maintenance|migration>
- **Updated:** <ISO date> by <agent name + model>
- **Driver skill:** <last skill that drove substantive work>

## Current focus

<1-3 sentences on what's actively being worked on right now>

## Recent decisions

- [date] <decision> — <one-line rationale>

## Open questions

- <question> — <whose call, blocking what>

## Next steps (in order)

1. <next concrete action>
2. ...

## Don't lose

<gotchas, half-finished migrations, sleeping bugs the next agent must know about>

## Handoff

<anything the next agent — possibly on a different tool — needs to know>
```

Keep it short. If it grows past one screen, prune. Long-tail history goes
in brain-mcp (via natural conversation) or in commit messages — not here.

## Cross-agent handoff (the headline use case)

When the user says *"I'm switching from Claude Code to Cursor"* or vice
versa, the conductor's job is to make the switch invisible:

1. **Before the switch** (in the source agent):
   - Update `.claude/project-state.md` with the latest decisions, open
     questions, and explicit next steps.
   - If brain-mcp is wired, the source agent's session is already being
     captured automatically — no extra step.
   - Commit `project-state.md` (one line: `chore: update project state`).
2. **After the switch** (in the new agent):
   - Conductor runs the re-entry brief (step 1 above).
   - Reads `.claude/project-state.md`. Confirms the brief with the user
     in 1-2 sentences.
   - Routes to the driver skill named in the state file unless the user
     overrides.

That's the "0 context loss" loop. brain-mcp keeps the *conversational*
context. graphify keeps the *structural* context. `project-state.md` keeps
the *intent* context. Three files, three concerns, one re-entry.

## Defaults

- **Always check `.claude/project-state.md` first** on a cold start. If
  absent, that's fine — note it and proceed.
- **Phase detection is deterministic.** Run the heuristics, don't guess.
- **Surface ambiguity.** If two phases tie, ask. Don't lock in by accident.
- **Route, don't drive.** Conductor's job ends when the right downstream
  skill takes over.
- **Update state at the end of substantive sessions.** Not after every
  message — but if a decision was made or a milestone hit, capture it.

## Anti-patterns

- **Re-conducting mid-task.** The user is implementing; you're asking *"are
  we sure we're in the building phase?"*. Stop. Get out of the way.
- **Inventing phases.** Stick to the five. Don't mint "early-building" or
  "pre-greenfield" — pick the closest standard phase.
- **Treating `project-state.md` as a journal.** It's a snapshot, not a log.
  Old decisions move to the bottom or get pruned. Keep the file readable
  in 30 seconds.
- **Skipping the state update because "the user knows".** They don't, and
  neither does the next agent. Update the file.
- **Routing to graphify or brain-mcp as the "driver".** They're context
  sources, not drivers. The driver is always a skill that *does work*.
- **Pretending you have brain-mcp / graphify when you don't.** If they're
  not installed, say so — degrade gracefully to local-only.

## Output format on a cold start

After the re-entry brief and phase detection, emit one short block:

```
📍 <project name> — <phase>
Last work: <one line of what happened most recently>
Open: <top 1-2 open items from project-state + brain-mcp open_threads>
Next: <the first concrete action from the state file, or "ask user">
Driver: <skill name that should run next>

Want me to <action that follows from "Next">?
```

Six lines, one question. Then wait for the user.

## Reference

- `references/lifecycle-phases.md` — full phase heuristics, edge cases, and
  per-phase routing decisions.
- `references/project-state-template.md` — the canonical schema for
  `.claude/project-state.md` plus a worked example.
