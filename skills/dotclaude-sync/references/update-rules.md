# Update rules

How to apply each category of proposed change. Classification tells you
*what* a file is; this tells you what *to do*.

## The operation matrix

| Category | `add` | `update` | `delete` | `drift` | `stack-removed` |
|---|---|---|---|---|---|
| `upstream` (simple file) | Copy + tag | Overwrite with tag | Remove | See drift-handling.md | Confirm + remove |
| `template-seeded` | N/A (init-only) | Never update | Never delete | N/A | N/A |
| `merged` | N/A | Re-merge + diff + overwrite | N/A | N/A | Re-merge (affected stack gone) |
| `project-owned` | N/A | Never update | Never delete | N/A | N/A |

## Simple upstream file — `add`

A file exists in `$DOTCLAUDE_HOME/<source>/...` and the target doesn't have it yet.

```
read upstream file
inject `source:` tag
  - for markdown: insert/ensure `source: <value>` in frontmatter
  - for JSON: set/ensure `_comment` starts with `source: <value>`
  - for shell: ensure header comment line `# source: <value>` in first 5 lines
write to target path
preserve executable bit for scripts (chmod +x if upstream has it)
```

New file always carries the correct `source:` tag so future sync recognizes it.

## Simple upstream file — `update`

Target file exists, upstream version differs, no drift detected.

```
show diff (target → upstream) if user selected per-file review; else bulk
overwrite target with upstream + source tag
preserve executable bit
```

The `source:` tag stays the same. The **body** is replaced.

### Special case: tag-only change

If the only diff between target and upstream is the `source:` line itself (e.g., path was reorganized upstream and the source value changed), that's a tag normalization — auto-apply without showing a diff.

## Simple upstream file — `delete`

Target has an upstream-tagged file whose source no longer exists in `DOTCLAUDE_HOME`. Example: `core/rules/legacy-thing.md` was removed in a recent dotclaude commit.

```
confirm with user (default grouped confirmation for all deletes)
remove the file
if its parent directory is now empty AND the directory was created by init
(rules/, skills/<foo>/, etc.), remove the empty dir
```

Never delete without confirmation. Never delete a parent dir that contains project-owned files.

## Simple upstream file — `stack-removed`

The project no longer uses this stack, but files from it are still in the target.

Example: `.claude/rules/python-style.md` with `source: stacks/python`, and `python` no longer appears in the project's active stack list.

```
group these together under one confirmation ("remove all python stack artifacts?")
if confirmed: delete as in `delete` category
if not confirmed: leave in place BUT warn; these files will be flagged
again on next sync run
```

**Alternative user choice**: convert to project-owned by stripping the `source:` tag. Useful when the stack has been removed at project level but the rule is genuinely still wanted as a project rule. Sync should offer this as a secondary option: `(d)elete / (k)eep / (c)onvert to project-owned`.

## Template-seeded — always no-op

Sync **never** touches files whose `source:` is `core/templates` (or whose path matches a template's target path and content is "close enough to the template seed").

The rationale: templates are starting points. A developer has edited them. Overwriting would destroy local customization that was the whole point of the template.

If the upstream template changes, that's a note in sync's output ("core/templates/CLAUDE.local.md.example has changed; you may want to diff it against your local copy manually"), not an action.

## Merged files — the three composites

### `.claude/settings.json`

Re-merge deterministically:

1. Start with `core/settings.partial.json`.
2. For each active stack, deep-merge `stacks/<name>/settings.partial.json`.
3. Apply the same merge rules used by init (see `skills/dotclaude-init/references/merge.md#deep-merge-rules`):
   - `permissions.allow` — union, deduped, sorted.
   - `permissions.deny` — union, deduped.
   - `hooks.<event>` — entries with matching `matcher` concatenate their `hooks` arrays; otherwise list concat.
   - Everything else — stack > core (last-writer-wins).

Then:

4. **Preserve any top-level key the target has that exists in neither core nor active stacks.** That's a project addition — keep it unless the user opts to prune. Flag it in the diff.
5. Show a unified diff of the re-merged result vs the current `settings.json`.
6. Write on confirmation.

### `.mcp.json` at repo root

Same model:

1. `core/mcp/mcp.partial.json` is the always-on base.
2. Add each opted-in optional under `core/mcp/optional/`.
3. Add each opted-in stack-scoped `stacks/<s>/mcp/optional/*.mcp.json`.
4. Deep-merge `mcpServers`; stack servers win over core on name collision.

**Preserve project additions** (a `mcpServers` entry with no upstream equivalent). Warn about them in the diff; don't silently remove.

### `.claude/CLAUDE.md`

CLAUDE.md is the trickiest because it's a composite with a literally-preserved project section.

Init writes this structure:

```markdown
# Claude Code instructions for <project>

<!-- source: core -->
<core/CLAUDE.base.md content>

<!-- source: stacks/<name> -->
<stacks/<name>/CLAUDE.stack.md content>
(repeat for each active stack)

<!-- project-start -->
## Project context

<user's interview answers and manual edits go here>
<!-- project-end -->
```

Sync's job:

1. Locate `<!-- project-start -->` and `<!-- project-end -->` markers in the target.
2. **Extract everything between them** (inclusive of the markers, to preserve them) — this is the project-owned section.
3. **Re-render** the upstream-owned sections (above project-start) from current `core/CLAUDE.base.md` + each active stack's `CLAUDE.stack.md`.
4. **Reassemble**: rendered-upstream + preserved-project-section.
5. Show diff (of the new file vs current).
6. Write on confirmation.

If the markers are missing:

- The file was likely hand-written or pre-init. Stop. Refuse to touch `CLAUDE.md`. Advise the user to insert the markers around whatever section they consider project-owned, or to re-run init.

If content exists **after** `<!-- project-end -->`:

- That's unusual but possible. Treat as project-owned (preserve). Warn.

## Executable bit

For hook scripts:

- Upstream has exec bit → target must have exec bit after sync.
- Upstream doesn't → target's bit is preserved as-is (don't strip a bit the user set).

On Windows, git handles this via `core.filemode`; the copy step shouldn't block on it. Always include the chmod attempt but don't fail the sync if it no-ops.

## Write discipline

- **Atomic writes.** Write to `<path>.tmp` then rename. Prevents half-written files if the agent gets killed mid-sync.
- **Preserve line endings.** Respect the target repo's `.gitattributes` / `core.autocrlf`. Don't convert LF→CRLF (or vice versa) silently.
- **Preserve file ordering in JSON.** Serialize with sorted keys so diffs are stable across runs.

## Rollback

- Every sync run should leave a `.claude/.dotclaude-sync-<timestamp>.backup.tar` in a gitignored path (or rely on git itself — if the user followed the clean-tree rule, `git restore .claude/` reverts everything).
- Prefer git for rollback; only write a backup archive if the user explicitly asks.
- Include the pre-sync state summary in the final report so the user knows what `git restore` would take them back to.
