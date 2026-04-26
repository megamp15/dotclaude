# Classification

How to decide what every file in a target's `.claude/` tree *is* before
you propose doing anything with it. Classification is the hardest step;
the rest is bookkeeping.

## The four categories

Every file in `.claude/` (and `.mcp.json` at root) falls into exactly one:

| Category | Detection | Sync behavior |
|---|---|---|
| `upstream` | Has `source:` in frontmatter or header comment | Eligible for update / delete |
| `project-owned` | No `source:` tag | Never touched |
| `template-seeded` | Was seeded from `core/templates/*.example` | Never touched |
| `merged` | One of the three composite files | Re-merged, not copy-replaced |

Nothing else. If a file defies classification, default to `project-owned` and warn.

## Detecting `source:` tags

Files that carry metadata:

### Markdown (`.md`) — YAML frontmatter

```yaml
---
source: stacks/python
name: python-style
---
```

Look for `source:` as a top-level key in the frontmatter block (lines 1..end-of-second-`---`).

### JSON — `_comment` field

```json
{
  "_comment": "source: core/mcp/optional — Context7 MCP. ...",
  "mcpServers": { ... }
}
```

Look for `"_comment"` at top level, string value starts with `source: ` (or contains `source:` as a prefix after optional whitespace).

### Shell / scripts — header comment

```bash
#!/usr/bin/env bash
# source: core — Format files after edit ...
```

Look within the first 5 lines (past the shebang) for `# source:`.

### Other file types

For any extension where an obvious comment style exists (`/* source: */` for CSS, `// source:` for JS), apply the analogous pattern. If a file type has no conventional comment syntax (images, binaries), treat as `project-owned` — we should never be copying those from upstream anyway.

## Extracting the source path

The `source:` value is one of:

- `core` — from `core/`, flat rules/skills/agents/hooks
- `core/templates` — seed template
- `core/mcp/optional` — opt-in MCP config
- `stacks/<name>` — from a language/infra stack
- `stacks/<name>/mcp/optional` — stack-scoped opt-in MCP

The path after `source:` is the upstream **category directory**, not the upstream file. To find the upstream file: combine the `source:` value with the target file's **position under `.claude/`**.

Example:

- Target file: `.claude/rules/python-style.md`
- Its `source:` value: `stacks/python`
- Upstream file: `$DOTCLAUDE_HOME/stacks/lang/python/rules/python-style.md`

Rule: strip `.claude/` from the target path, then resolve the source root:

- `core` sources map directly to `$DOTCLAUDE_HOME/core/...`.
- `stacks/<name>` sources map through the categorized stack layout
  (`stacks/<category>/<name>/...`).

Do not rewrite target `source:` tags to include the category. The category is
an upstream storage detail.

### Edge cases for path resolution

- **Skills** live under `<source>/skills/<name>/SKILL.md` (folder form) or `<source>/skills/<name>.md` (flat form). Look for folder form first, fall back to flat. `dotclaude-init` normalizes skills into one or the other — respect whichever shape the upstream currently uses.
- **MCP skills** live under `<source>/mcp/skills/<name>/SKILL.md`. Their `source:` is `core` or `stacks/<name>`, but the upstream path includes the extra `mcp/skills/` segment. Use the target's relative path (`skills/<mcp-name>/SKILL.md`) combined with the knowledge that the source layer is the MCP layer.
- **`core/templates/*`** always becomes `.claude/<basename-without-.example>`. Going the other way: if a target file's source is `core/templates`, classify as `template-seeded` regardless of anything else.

## The three `merged` files

These are not simple copies; they're composites. Sync treats them differently (see `update-rules.md`):

1. **`.claude/settings.json`** — deep-merge of `core/settings.partial.json` + every active stack's `settings.partial.json`.
2. **`.mcp.json`** at the repo root — deep-merge of `core/mcp/mcp.partial.json` + opted-in `core/mcp/optional/*.mcp.json` + opted-in stack-scoped MCP configs.
3. **`.claude/CLAUDE.md`** — rendered from `core/CLAUDE.base.md` + each active stack's `CLAUDE.stack.md` + the project-owned section between `<!-- project-start -->` / `<!-- project-end -->` markers.

These don't carry a single `source:` because they have several. Sync identifies them by path, not tag.

## Detecting active stacks

To classify `stack-removed` files, sync needs to know which stacks the project is still using. Three signals, in order of trust:

### 1. Explicit list in `.claude/CLAUDE.md`

If `CLAUDE.md` has a `## Stacks` section (init writes this):

```markdown
## Stacks

- python
- docker
```

…that's canonical. Use it.

### 2. Cached answers

`.claude/.dotclaude-interview.json` (gitignored, written by init) includes the stack list.

### 3. Inference from `source:` tags

Collect every `source:` value across the target's upstream files. Any `stacks/<name>` that appears is a stack the project is using.

If the three signals disagree, **trust the explicit list** and warn about the discrepancy — it often means init was re-run and the cache or the tags are stale.

## Classifying each file — decision tree

```
For each file under .claude/ (and .mcp.json):

  Is path one of: settings.json, CLAUDE.md, .mcp.json?
    → merged
    (stop)

  Read file, try to extract `source:`.
    Found, value starts with "core/templates":
      → template-seeded
      (stop)

    Found (other value):
      → upstream  (record path + source + hash of content)

    Not found:
      → project-owned
```

For each upstream file, also determine:

- **Source layer exists in DOTCLAUDE_HOME?** If not → `delete` candidate.
- **Source's stack is still active?** If not → `stack-removed` candidate.
- **Content matches current upstream?** (See `drift-handling.md` for the nuance.)

## What about `.dotclaude-interview.json`?

- **Created by init**, read by sync.
- **No `source:` tag** — but it's not project-owned either; it's state.
- Sync treats it as: read it, never write it (unless specifically reconciling the cached stack list with the CLAUDE.md stacks section — and even then, only with user confirmation).
- Should be in `.gitignore` by default; if it's committed, the project accepted the trade-off.

## What about `.gitignore`?

Outside `.claude/` — **do not touch in sync**. Init adds entries; sync doesn't add new ones. If upstream changes what should be ignored, that's a note in the release output, not a silent file edit.
