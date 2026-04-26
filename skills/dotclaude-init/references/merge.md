# Merge rules

Deterministic. Re-running init with the same inputs (repo state + answers)
produces a byte-identical `.claude/`.

## File-by-file behavior

| Source | Target | Strategy |
|---|---|---|
| `core/rules/*.md` | `.claude/rules/*.md` | Copy, inject `source: core` into frontmatter |
| `stacks/<s>/rules/*.md` | `.claude/rules/*.md` | Copy, inject `source: stacks/<s>` |
| `core/skills/**` | `.claude/skills/**` | Recursive copy, preserve folder-per-skill shape |
| `stacks/<s>/skills/**` | `.claude/skills/**` | Recursive copy |
| `core/mcp/skills/**` | `.claude/skills/**` | Copy only if MCP opted in |
| `stacks/<s>/mcp/skills/**` | `.claude/skills/**` | Copy only if MCP opted in |
| `core/agents/*.md` | `.claude/agents/*.md` | Copy + source tag |
| `stacks/<s>/agents/*.md` | `.claude/agents/*.md` | Copy + source tag |
| `core/hooks/*` | `.claude/hooks/*` | Copy, preserve executable bit |
| `stacks/<s>/hooks/*` | `.claude/hooks/*` | Copy, preserve executable bit |
| `core/settings.partial.json` + `stacks/<s>/settings.partial.json` | `.claude/settings.json` | Deep-merge (see below) |
| `core/mcp/mcp.partial.json` + opted-in optionals + `stacks/<s>/mcp/*.mcp.json` | `.mcp.json` at project root | Deep-merge `mcpServers` map |
| `core/CLAUDE.base.md` + `stacks/<s>/CLAUDE.stack.md` + interview | `.claude/CLAUDE.md` | Template render with three sections |

## Deep-merge rules

- **`permissions.allow`** — union of all arrays, deduped, sorted.
- **`permissions.deny`** — union, deduped. Deny wins over allow.
- **`hooks.<event>`** — concatenate entries; entries with the same `matcher` have their `hooks` arrays concatenated (not deduped — duplicates are a user's problem).
- **`mcpServers.<name>`** — object merge. If a stack and core both define the same server name, the stack wins.
- **Anything else** — last-writer-wins with stack > core.

## Source tagging

Every file copied from core/ or stacks/ gets `source:` added to its frontmatter (for markdown) or a comment header (for scripts/JSON):

```yaml
---
source: stacks/python
---
```

Files without `source:` are **project-owned**. `/dotclaude-sync` will never touch them.

## Interview output placement

- **Bullet rules** (rate limits, sensitive paths, public API list) → `.claude/rules/project.md` (no `source:`)
- **Narrative** (description, context, owners) → `.claude/CLAUDE.md` "Project context" section, between `<!-- project-start -->` and `<!-- project-end -->` markers so sync can safely regenerate the other sections around it
- **Raw answers cache** → `.claude/.dotclaude-interview.json` (gitignored)

## Continuity layer setup

The continuity layer (project-conductor + the SessionStart conductor
brief + the agent-agnostic state file) is foundational. Init wires
all three:

1. **Skill copy** — `core/skills/project-conductor/` is copied into
   `.claude/skills/` as part of the normal `core/skills/**` recursive
   copy. No special handling.
2. **Hook copy + registration** — `core/hooks/conductor-brief.sh` is
   copied into `.claude/hooks/` and is already registered in
   `core/settings.partial.json` under `SessionStart`. The settings
   deep-merge picks this up automatically.
3. **State file seed** — if `.claude/project-state.md` does **not**
   already exist, init writes a skeleton populated with what's
   knowable from scan + git:

   ```markdown
   # Project state

   - **Phase:** <detected phase from git heuristics>
   - **Updated:** <ISO date> by dotclaude-init
   - **Driver skill:** project-conductor
   - **Brain domain:** <repo name>

   ## Current focus

   <empty — first conductor pass will fill this>

   ## Recent decisions

   - [<today>] Adopted dotclaude — stacks: <stacks>; frameworks: <frameworks>; continuity layer wired (brain-mcp: <on|off>, graphify: <on|off>).

   ## Open questions

   <empty>

   ## Next steps

   1. Run `project-conductor` on next session to refine phase + focus.
   2. <if brain-mcp wired but not installed> Install brain-mcp: `pipx install brain-mcp && brain-mcp setup`.
   3. <if graphify wired but no graph yet> Build initial graph: `graphify ./`.

   ## Don't lose

   <empty — populated as the project accrues gotchas>

   ## Handoff

   <empty>

   ---
   _Last conductor pass: <today> (init)_
   ```

   **Phase detection (init-time, cheap):**
   - `git rev-list --all --count` ≤ 3 → `greenfield`
   - last commit > 90 days ago → `maintenance`
   - any `git tag` exists → `established`
   - otherwise → `building`

   This is intentionally a coarse first guess. project-conductor
   refines it on its first real session.

4. **Existing state file** — if `.claude/project-state.md` already
   exists, do **not** overwrite. Print: "kept existing
   `.claude/project-state.md` — let project-conductor refresh it."

5. **Learnings log seed** — if `.claude/learnings.md` does **not**
   already exist, init writes a minimal seed:

   ```markdown
   # Learnings

   Append-only log of non-obvious things discovered while working on
   this project. Newest entries on top. One thought per entry. See
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
   gotchas), and brain-mcp (semantic history, optional). Conductor
   brief runs on every SessionStart and surfaces the top 3 entries.

   tags: meta, dotclaude
   ```

   The single seed entry exists so the file is non-empty (the conductor
   brief has something to print) and doubles as a worked example of
   what an entry looks like.

   If `.claude/learnings.md` already exists, do **not** overwrite. Print:
   "kept existing `.claude/learnings.md` — append new learnings to it."

Both state file and learnings log are **project-owned** — no `source:`
frontmatter, never touched by `dotclaude-sync`.

## Optional install step (only when user opted in)

If the interview answered "wire AND install now" for brain-mcp or
graphify, run the installs **after** all file writes succeed, never
before. Order matters: file writes are deterministic and reversible;
shell installs are not.

For each opted-in install, follow this contract strictly:

1. **Print** the exact command(s) about to run, one per line:

   ```
   About to run for brain-mcp:
     pipx install brain-mcp
     brain-mcp setup
   ```

2. **Ask one yes/no** before invoking shell. A single confirmation per
   tool is enough — don't ask separately for `pipx install` vs
   `brain-mcp setup`. The user already opted in during the interview;
   this is the safety reconfirmation.

3. **Run, capturing exit codes.** Stream output so the user sees
   progress. Do NOT swallow stderr.

4. **On failure:**
   - Print the failing command and its stderr.
   - Print the manual recovery command verbatim, copy-pastable.
   - Continue init. Don't roll back the wiring — the wiring is
     correct; only the install failed. The user can re-run the
     install later and the wiring will activate immediately.

5. **On success:**
   - For brain-mcp: print "brain-mcp installed and wired into all
     supported agents on this machine. Restart your agent to pick
     it up."
   - For graphify: print "graphify installed. Run `graphify ./` in
     this repo to build the initial graph."

**Never auto-run anything else.** Don't `git commit`, don't restart
agents, don't run `graphify ./` automatically — those are the user's
calls. Init's job ends at: files written, deterministic state, prereqs
installed if asked, clear next-step instructions printed.

### Platform notes

- `pipx` may not be on PATH. If `command -v pipx` fails before the
  brain-mcp install, suggest `python -m pip install --user pipx &&
  pipx ensurepath` as the prerequisite, then continue with the
  brain-mcp install (or skip if the user declines the prereq).
- `pip install graphifyy` works in any active Python env. If the
  user is in a project venv, ask once whether they want graphify in
  the venv or globally (`pipx install graphifyy` for global). Default:
  global (`pipx`), since graphify is a CLI tool used across projects.
- On Windows without WSL, `pipx` paths can be unusual. Print the
  commands; if shell invocation fails outright, fall back to
  print-only and let the user paste them into their terminal.

## Conflict handling on re-init

If a target file exists with `source:` matching current source, and content differs → this is a user edit. Ask:

1. **Overwrite** — lose local edits, take dotclaude version.
2. **Keep local** — remove `source:` so future syncs skip it (file becomes project-owned).
3. **Manual** — print path + diff, skip, let user resolve.

Never silently overwrite user edits.

For a full-fidelity refresh against an already-initialized repo, use
`dotclaude-sync` instead of re-running init. Sync's drift handling is
the authoritative rule set; see
[`skills/dotclaude-sync/references/drift-handling.md`](../../dotclaude-sync/references/drift-handling.md).

## Idempotency guarantees

- Same inputs → same outputs (byte-identical).
- Interview answers cached in `.dotclaude-interview.json` so re-runs don't re-ask.
- File ordering in generated `settings.json` / `.mcp.json` is alphabetized for stable diffs.
