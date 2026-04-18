---
name: dotclaude-sync
description: Refresh an existing project's .claude/ directory with upstream updates from DOTCLAUDE_HOME, preserving project-owned files. Use when pulling latest core/stack changes into a repo already bootstrapped with dotclaude-init.
triggers: dotclaude-sync, sync dotclaude, refresh claude code, update .claude, pull upstream rules, /dotclaude-sync
---

# dotclaude-sync

The update flow. Init creates `.claude/`; sync keeps it fresh without
clobbering the customizations a project has accumulated since.

## When to use

- Pulling in new rules/skills/hooks added to `core/` or `stacks/` upstream.
- After editing dotclaude itself locally and wanting the change in a consuming repo.
- Periodic maintenance ("quarterly dotclaude refresh").
- After removing a stack from `dotclaude` that this target still carries source-tagged files from.

Not for:

- **First-time setup** — use `dotclaude-init` instead.
- **Fixing local edits to an upstream file** — sync will notice and ask; you decide.
- **Changing what stacks a project uses** — re-run `dotclaude-init` with the new stack set.

## Prerequisites

- `DOTCLAUDE_HOME` env var points at the local dotclaude repo.
- Target repo has a `.claude/` directory that was created by `dotclaude-init` (or follows the same conventions — `source:` tags on upstream files).
- **Git working tree is clean.** Sync writes multiple files; a clean baseline makes review and rollback trivial. Refuse to run if dirty.

## Guiding principles

1. **`source:` tags are the source of truth.** Presence of `source:` means "dotclaude owns this." Absence means "project owns this." The tag decides; there is no other heuristic.
2. **Never surprise the user with a destructive change.** Every delete or overwrite is confirmed, by default grouped (so you can approve 40 small rules updates with one "yes").
3. **Show diffs, not assertions.** When updating a file, the user sees the diff. When the diff is trivial (only the `source:` line / whitespace), auto-apply and log it.
4. **One-way: upstream → target.** Sync never pushes target changes back to `DOTCLAUDE_HOME`. If you improved a rule locally and want it upstream, contribute it there explicitly.
5. **Idempotent.** Running sync with no upstream changes and no local drift produces zero writes.

## Workflow

### Phase 1 — scan and classify

1. **Resolve `DOTCLAUDE_HOME`.** Error out clearly if unset.
2. **Confirm clean git tree** in the target repo. If dirty, refuse and list the dirty files.
3. **Read every file under `.claude/`** (and `.mcp.json` at repo root if present). For each, classify via `references/classification.md`:
   - `upstream` — has `source:` tag.
   - `project-owned` — no tag.
   - `template-seeded` — matches a `core/templates/*.example` name.
   - `merged` — `settings.json`, `.mcp.json`, `CLAUDE.md`. Special handling.
4. **Detect active stacks** — from `CLAUDE.md` stack section, or by reading the set of `source:` paths that appear on upstream files. The set of stacks in use dictates what upstream looks like.
5. **Compute a plan**, a list of proposed operations, each one of:
   - `add` — upstream has this file, target doesn't.
   - `update` — target has this file, upstream version differs (and target hasn't diverged — see phase 2).
   - `delete` — target has an upstream-tagged file whose source no longer exists in `DOTCLAUDE_HOME`.
   - `drift` — target has an upstream-tagged file that was edited locally; upstream has also changed (or not).
   - `stack-removed` — files whose `source:` points at a stack no longer active in this project.

### Phase 2 — detect drift

For every `update` candidate, compare three things:

- **A** — upstream content as it would be rendered right now (with `source:` injected).
- **B** — the content init would have written **at the time the target file was created**, i.e. the version the user started from. We don't have this exactly, but we have a reasonable proxy: **if target content minus the `source:` line matches the current upstream source minus any rendering, there's no drift.** Otherwise drift is possible.
- **C** — what's in the target right now.

Practical rule:

- If `C == A` → up to date, no action.
- If `C == A` after ignoring trivial whitespace/frontmatter noise → auto-apply.
- If `C ≠ A` and target has no local modifications we can detect → reclassify as `update` (user installed, upstream changed).
- If `C ≠ A` and target has edits that look intentional (content diverges in meaningful ways from anything upstream ever produced) → classify as `drift`. See `references/drift-handling.md`.

Be conservative: when unsure, treat as `drift` and ask the user.

### Phase 3 — present the plan

Print the plan grouped by operation, **highest-risk first**:

```
## dotclaude-sync plan

DRIFT (your edits differ from upstream, upstream also changed)  [2]
  .claude/rules/python-style.md     source: stacks/python
  .claude/hooks/block-dangerous-commands.sh   source: core

STACK REMOVED (no longer in this project's stack list)          [3]
  .claude/rules/go-style.md         source: stacks/go (inactive)
  .claude/agents/go-reviewer.md     source: stacks/go (inactive)
  .claude/hooks/gofmt.sh            source: stacks/go (inactive)

DELETE (source no longer in DOTCLAUDE_HOME)                     [1]
  .claude/rules/legacy-thing.md     source: core (removed upstream)

UPDATE (content differs, no local drift detected)               [12]
  .claude/rules/code-quality.md     source: core
  .claude/rules/testing.md          source: core
  ... (10 more)

ADD (new upstream file, not yet in target)                      [4]
  .claude/rules/observability.md    source: core
  .claude/skills/hotfix/SKILL.md    source: core
  ...

MERGED (needs re-merge; diff will be shown)                     [2]
  .claude/settings.json
  .mcp.json

UNCHANGED                                                       [31]

SKIPPED (project-owned, not touched)                            [6]
```

Ask per group: proceed, skip, review individually.

### Phase 4 — apply

Apply in a safe order:

1. **`add`** — new files never conflict; apply first.
2. **`update`** — bulk apply (or individually if user chose review).
3. **`merged`** — re-merge + show diff + apply (see `references/update-rules.md`).
4. **`delete`** — always confirmed; apply last.
5. **`stack-removed`** — each requires explicit confirmation (stack really gone, or sync misdetected?).
6. **`drift`** — never applied automatically; each resolved per `references/drift-handling.md`.

After each phase, print a short summary of what ran.

### Phase 5 — report

Print a single final summary:

```
dotclaude-sync complete.

  added:      4 files
  updated:   12 files
  merged:     2 files (settings.json, .mcp.json)
  deleted:    1 file
  drift:      2 files  (kept as-is; see <listed paths>)
  skipped:    6 files  (project-owned)

  stacks detected: python, docker
  dotclaude commit: <sha> (<subject>)
```

## Reference guide

| Topic | Reference | Load when |
|---|---|---|
| How to classify every target file | `references/classification.md` | Phase 1 |
| Per-category apply rules | `references/update-rules.md` | Phase 4 |
| Drift detection & 3-way resolution | `references/drift-handling.md` | Phase 2, 4 |

## Do not

- Do not touch files without a `source:` tag. Ever.
- Do not touch `core/templates/*` seed files (`CLAUDE.local.md`, `settings.local.json`) after initial copy — these are one-shot.
- Do not silently resolve drift. Always show the user.
- Do not run if the git tree is dirty.
- Do not sync across `DOTCLAUDE_HOME` versions without showing which commit the target last synced against (if known) and which commit is being synced to now.
- Do not delete files outside `.claude/` or the root `.mcp.json`.
- Do not modify `.gitignore` — init handles that; sync doesn't re-touch.
