---
title: Ported-skills provenance convention
source: core
---

# Ported-skills provenance

Some `dotclaude` skills are adapted from external upstream sources (most often
[Jeffallan/claude-skills](https://github.com/Jeffallan/claude-skills)). We do
not vendor them as-is — they are rewritten to match `dotclaude` style and
scope — but we track where they came from so a future `dotclaude-upstream-check`
skill (or a human) can diff against the upstream and decide whether to re-port.

## Frontmatter convention

Any skill adapted from an external source carries these fields in addition to
the normal `name`, `description`, `source`, `triggers`:

```yaml
---
name: the-fool
description: …
source: core
triggers: …
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/the-fool
ported-at: 2026-04-17
ported-sha: main                # or a specific commit SHA when known
adapted: true                   # content was rewritten, not copied verbatim
---
```

Field semantics:

| Field | Meaning |
|---|---|
| `ported-from` | URL of the upstream skill directory |
| `ported-at` | Date of the port (YYYY-MM-DD, no time, no timezone) |
| `ported-sha` | Upstream commit SHA at port time (`main` acceptable if no pin) |
| `adapted: true` | Signals "content is not a verbatim copy". Sync tooling must not blindly overwrite |
| `adapted: false` | Verbatim copy — `dotclaude-upstream-check` can pull updates with low risk |

## Behaviour

- `dotclaude-sync` continues to ignore these fields. It only cares about
  `source:` to decide ownership.
- A future `dotclaude-upstream-check` will:
  1. Read every file whose frontmatter has `ported-from:`.
  2. Fetch the upstream file at `HEAD`.
  3. Report diffs; prompt the maintainer to re-port if significant.
  4. Never auto-overwrite adapted files.
- When you re-port a skill, bump `ported-at` and `ported-sha`.

## What counts as "adapted"?

Mark `adapted: true` if any of the following apply:

- File structure was changed (sections reordered, merged, or split).
- Content was trimmed to fit `dotclaude`'s leaner style.
- Examples were rewritten to match our stacks or tone.
- Opinions were added or removed.

In practice, nearly everything we port is adapted. The rare exceptions are
pure reference tables (e.g. an HTTP status code cheat sheet) that make no
sense to rewrite.

## Applies to references too

Reference files under a ported skill's `references/` folder should also carry
`ported-from:` frontmatter pointing at the specific upstream reference file.
This keeps provenance granular — if only one reference changes upstream, we
don't have to re-evaluate the entire skill.

## Not a license replacement

Provenance is not a license. Upstream Jeffallan skills are MIT-licensed;
check the upstream `LICENSE` before porting. Keep attribution prominent in
any ported `SKILL.md` that borrows significant structure.
