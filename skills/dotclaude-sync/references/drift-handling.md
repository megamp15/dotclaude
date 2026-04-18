# Drift handling

The interesting case: a file carries a `source:` tag, so sync thinks
dotclaude owns it, but the content has diverged from upstream. The user
edited it. That's legitimate — sometimes you want a project-specific
version of a universal rule. Sync must never clobber those edits
silently.

## The challenge

Without a 3-way baseline (what init originally wrote), we can't always
know *whether* a diff represents local edits or just an upstream update
the target hasn't received yet. Two scenarios produce the same diff:

- **A**: user edited locally. Upstream didn't change since init. Current target ≠ current upstream because of the local edit.
- **B**: user didn't edit. Upstream changed since init. Current target ≠ current upstream because of the upstream update.

Mechanically identical; semantically opposite. Sync cannot be 100%
certain. So: when unsure, **ask**.

## Heuristics for auto-deciding

When we can be confident enough to avoid asking, save the user the prompt:

### Safe to treat as `update` (no drift)

- **Target file is byte-for-byte `source:`-line-plus-upstream-body.** Init just ran, upstream changed, user hasn't touched anything. Applies when the target contains exactly what init would have written at some upstream revision.
- **Diff is whitespace-only** (trailing whitespace, end-of-file newline). Whitespace drift from line-ending normalization isn't a user edit.
- **Diff is only the `source:` line** (upstream reorganized and the tag changed). Re-tag and move on.

For these, auto-apply the update and log it in the summary ("re-tagged", "whitespace normalized"). No prompt.

### Treat as `drift` — ask the user

Anything beyond whitespace or tag normalization. In particular:

- Changed wording in any rule body.
- Added or removed sections.
- Changed frontmatter fields (`name`, `description`, `triggers`, `globs`).
- For JSON: any value diff, any key added/removed.
- For shell: any executable logic diff.

Even a small edit counts. Small edits are often the ones users care about most — a targeted carve-out they made a week ago and forgot about.

## Prompting the user for drift

Show, per file:

```
DRIFT: .claude/rules/python-style.md
  source: stacks/python

Your current file vs upstream:

  <unified diff, max ~60 lines, truncate with a note if longer>

Options:
  (u) take upstream — your local edits will be lost
  (k) keep local    — skip sync for this file (stays as-is)
  (c) convert to project-owned — remove `source:` tag, sync will
      never notice this file again
  (s) show full diff
  (q) quit sync

What would you like to do? [u/k/c/s/q]
```

**Default (if unclear)**: `k` — keep local. Sync is *additive* by intent; when in doubt, preserve.

### Group drift prompts

If several files are drifted and the user clearly wants the same decision on all of them, offer a group action:

```
7 drifted files. Apply the same choice to all? [yes/no/per-file]
```

## Three options in detail

### `u` — take upstream

- Back up current file to `<path>.drift.bak.<timestamp>` in the same directory (gitignored via the `.claude/*.bak` pattern that init should already have added; if not, warn).
- Or rely on git — if the user kept the tree clean, `git restore <path>` is the backup. Prefer this; no side-effect files.
- Overwrite with upstream content + `source:` tag.
- Log in summary: "took upstream, prior content recoverable via git".

### `k` — keep local

- Do nothing. File stays as-is.
- Log in summary: "drift preserved".
- **Consequence**: every future sync will re-prompt. That's intentional — drift is a state worth revisiting. If the user is tired of being asked, the answer is `c`, not suppressing the warning.

### `c` — convert to project-owned

- Remove the `source:` line from the file.
- For markdown: strip the `source:` key from frontmatter. If frontmatter becomes empty, remove the frontmatter block entirely.
- For JSON: remove `_comment` if the only content was the source line. If `_comment` has other content, strip the `source: <path>` prefix.
- For shell: remove the `# source: <path>` comment line.
- File is now project-owned. Future sync treats it as `project-owned` (no action).

This is the "fork it" option. Use when the divergence is permanent by design.

## Detecting drift programmatically

The sync skill's actual algorithm (rough):

```
for each target file classified as `upstream`:

  upstream_path = $DOTCLAUDE_HOME + source value + relative path under .claude/

  if not upstream_path.exists():
    classify as `delete`
    continue

  upstream_content_tagged = render_with_source_tag(upstream_path)

  if target.content == upstream_content_tagged:
    classify as `unchanged`
    continue

  if diff_is_whitespace_only(target, upstream_content_tagged):
    classify as `update` (auto, "whitespace")
    continue

  if diff_is_only_source_line(target, upstream_content_tagged):
    classify as `update` (auto, "retag")
    continue

  # Genuine content difference.
  # We cannot distinguish "user edited" from "upstream changed" without
  # a baseline. Treat as drift and let the user decide.
  classify as `drift`
```

## If dotclaude tracked a `sync-baseline` (advanced, optional)

A future enhancement: sync could record each upstream file's SHA at the
time it last synced, in `.claude/.dotclaude-sync.state.json`:

```json
{
  "synced_at": "2026-04-17T12:00:00Z",
  "dotclaude_commit": "431662b",
  "files": {
    "rules/python-style.md": "sha256-of-upstream-at-last-sync"
  }
}
```

With this baseline, drift becomes a proper 3-way compare:

- **baseline** (what the user received last time)
- **upstream-now** (what's in DOTCLAUDE_HOME today)
- **target-now** (what's in the project today)

Cases:

- `baseline == upstream-now`, `target-now != baseline` → **user edited, upstream didn't change.** It's drift; confirm.
- `baseline != upstream-now`, `target-now == baseline` → **upstream changed, user didn't edit.** Safe `update`, no prompt.
- `baseline != upstream-now`, `target-now != baseline` → **both changed.** Real 3-way merge or user decision required.

This is the right long-term design. For now, the simpler heuristic above is good enough.

## What the user sees

Keep drift prompts short. One screen, one file, one diff (truncated if
needed), five options. If the diff is enormous (> ~60 lines), show the
first 30 and last 10, with a `(s)` option to see the full thing.

Never dump a 2000-line diff into the terminal. That's not review; that's
user-hostile output.
