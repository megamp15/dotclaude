# Core MCP servers

Universal, free MCP servers merged into every project's `.mcp.json`.

## Inclusion rules

Every server added here must be:

- **Free** to run and use. No paid tier required for base functionality.
- **Widely applicable** — useful regardless of language or domain.
- **Stable** — an official Anthropic reference server, an official vendor server, or a well-maintained community one.

Paid MCPs (Linear, Stripe, Datadog, Atlassian paid tiers, etc.) do NOT go here.
They're the user's responsibility — the init interview can surface them as
*candidates* with a note, but the user installs + configures credentials.

## Layout

```
core/mcp/
├── mcp.partial.json        ← always-on servers (no credentials, or optional ones)
├── optional/
│   └── *.mcp.json          ← opt-in via interview (e.g., github needs a PAT)
└── skills/
    └── <name>-mcp/SKILL.md ← usage skill for each server, copied into target's skills/ only if opted in
```

## Always-on (in `mcp.partial.json`)

| Server | Purpose |
|---|---|
| `filesystem` | Scoped filesystem access for the project root |
| `fetch` | HTTP fetch for docs, APIs, RSS |
| `git` | Local git operations via MCP (complements shell `git`) |
| `memory` | Persistent key-value memory across sessions |
| `sequential-thinking` | Structured reasoning tool |
| `time` | Timezone-aware date/time helpers |

## Optional (in `optional/`)

| Server | Credential | Opt-in trigger |
|---|---|---|
| `github` | `GITHUB_PERSONAL_ACCESS_TOKEN` env var | Interview confirms project is on GitHub |

## Adding a new core MCP

1. Verify it's free and universally useful. If it's language-specific, it belongs in `stacks/<lang>/mcp/` instead.
2. If no credentials required → `mcp.partial.json`. If credentials required → `optional/<name>.mcp.json`.
3. Add `skills/<name>-mcp/SKILL.md` explaining when to prefer it vs alternatives (e.g., `gh` CLI), common pitfalls, auth notes.
4. If optional, update `references/scanning.md` in the init skill with the opt-in trigger.
