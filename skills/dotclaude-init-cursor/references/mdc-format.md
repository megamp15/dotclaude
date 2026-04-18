# Cursor `.mdc` format reference

What a Cursor rule file looks like and how Cursor decides when to load
it. Based on Cursor's 2026 docs.

## File structure

```mdc
---
description: Short sentence used for intent-matching. Required for "intelligent" mode.
globs: ["src/**/*.ts", "src/**/*.tsx"]
alwaysApply: false
---

# Rule body (plain markdown)

Write like you'd write a CLAUDE rule. Bullet points, short sections,
concrete guidance. The frontmatter controls when the rule loads; the
body is what Cursor reads into context.
```

Frontmatter is YAML between `---` markers. Body is markdown. Cursor
ignores unknown frontmatter keys silently — harmless but don't rely on
them.

## The four activation modes

Decided by which frontmatter fields are set:

| Mode | `alwaysApply` | `description` | `globs` | When loaded |
|---|---|---|---|---|
| **Always Apply** | `true` | optional | ignored | Every prompt, every session |
| **Apply Intelligently** | `false` (or absent) | required | absent | Cursor's model decides based on current task + description |
| **Apply to Specific Files** | `false` (or absent) | optional | required | When any file matching a glob is in the context |
| **Manual** | `false` (or absent) | absent | absent | Only when the user types `@rule-name` |

**Corollaries:**

- A file with `alwaysApply: true` overrides everything else. Even with globs or description, it applies always.
- A file with no `alwaysApply`, no `description`, no `globs` is manual-only. This is how we represent agent personas.
- A file with `description` *and* `globs` uses globs for file-triggered loading; description is still visible to the model for relevance.

## Glob rules

- Standard `minimatch` syntax.
- String or list of strings. Prefer lists — more readable and avoids quoting issues.
- Patterns match paths *relative to the repo root*.
- `**` matches any number of directories.
- Don't forget the leading `**/` unless you mean only root-level.

```yaml
globs:
  - "**/*.py"
  - "**/pyproject.toml"
  - "**/requirements*.txt"
```

## Description writing

Cursor uses `description` as a semantic match signal. Write it like you
would a short, purposeful tool description:

- **Good**: `"PR review workflow — run multi-agent review, produce structured findings, severity-labeled"`
- **Good**: `"TypeScript-specific style rules; apply when writing or reviewing .ts/.tsx"`
- **Bad**: `"Rules for PR reviews"` (vague; doesn't help the model match)
- **Bad**: `"Best practices"` (matches everything and nothing)

Think: "what phrase in my prompt would cause me to want this rule loaded?" That phrase belongs in the description.

## Body length

Cursor's docs recommend keeping individual `.mdc` files **under ~500 lines** for token-budget reasons. dotclaude's `core/rules/` are usually well under that; stack rules sometimes approach it. When rendering, keep watch:

- If a rendered body is longer than ~500 lines, consider splitting the source rule upstream, or omitting the less-critical tail section.
- Don't silently truncate; warn the user.

## Common footguns

### Frontmatter with no closing `---`

Breaks parsing silently. Cursor won't complain; the rule just won't activate. Always end the frontmatter with the closing `---`.

```mdc
---
description: ...
alwaysApply: false
---                     ← don't forget this
```

### Quoting single globs

Both of these work:

```yaml
globs: "src/**/*.ts"
globs: ["src/**/*.ts"]
```

The list form is what we'll render — it scales to multiple patterns without changing shape.

### `alwaysApply` must be boolean

`alwaysApply: "true"` (string) is silently wrong. Always render as bare `true` or `false`.

### `.cursorrules` vs `.cursor/rules/`

- `.cursorrules` (at repo root) — legacy, single-file, less featureful.
- `.cursor/rules/*.mdc` — current, modular, frontmatter-driven.

When both exist, `.cursor/rules/` wins. This skill renders to `.cursor/rules/` only. If the target has a `.cursorrules`, we leave it untouched and note its presence in the report.

## MCP — `.cursor/mcp.json`

Separate file, schema close to but not identical to Claude Code's `.mcp.json`.

Cursor's schema:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "."]
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_PERSONAL_ACCESS_TOKEN}"
      }
    }
  }
}
```

Differences vs Claude Code's `.mcp.json`:

- Same top-level shape (`mcpServers` map).
- Cursor supports `http` type servers via `url` field (like Claude Code).
- Cursor *does not* read a `_comment` field for our `source:` tags. Render-time: strip `_comment` before writing to `.cursor/mcp.json`.
- MCP permission scoping is coarser in Cursor; project-level `.cursor/mcp.json` is the finest grain.

## `AGENTS.md` compatibility

Cursor (and VS Code, OpenCode, and a growing list of agents) reads
`AGENTS.md` at repo root as a neutral project-context file. We render
one so the project's context works across agents.

`AGENTS.md` is plain markdown — no frontmatter, no special fields. Just
a structured file with the project's conventions. See `translation.md`
for what dotclaude content goes here.

## What Cursor currently does not support

At time of writing (April 2026):

- **No hook system.** Tool-invocation interception, pre-command, post-edit — none of it. Closest analog: VS Code tasks + manual invocation.
- **No subagent system** analogous to Claude Code's Task tool. Composer can fan out, but not with dotclaude-style agent personas as first-class entities.
- **No per-pattern permission system.** Cursor gates tool use by tool type (edit, shell, terminal) at the IDE level, not by command pattern.
- **Limited `.mdc` frontmatter.** Only `description`, `globs`, `alwaysApply` are honored. Our `source:` tag belongs elsewhere if we want to preserve ownership metadata.
