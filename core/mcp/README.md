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
| `context7` | Optional `CONTEXT7_API_KEY` for higher rate limits | Interview confirms project uses a framework likely to need current library docs (Next, Prisma, Django, etc.) or user explicitly opts in |
| `chrome-devtools` | none | Interview confirms frontend/web-app work is the current focus. Heavy context footprint (~17k tokens); opt-in only when needed |
| `brain-mcp` | none | User wants cross-agent persistent memory (Claude Code ↔ Cursor ↔ Codex ↔ ...). **Recommended install path is GLOBAL via `pipx install brain-mcp && brain-mcp setup`** — auto-configures every agent on the machine. Use the project-scoped `.mcp.json` entry only when you want a brain isolated to one repo |
| `graphify` | none | User wants a queryable knowledge graph of the repo (code + docs + papers + diagrams). Primary install is the CLI + skill manifest that ships with `pip install graphifyy`; the project-scoped `.mcp.json` entry is for protocol-level integration via `graphify serve` |
| `code-review-graph` | none | User wants an **incrementally-updated** code graph tuned for review and daily coding (blast-radius analysis, <2s auto-update on save/commit, 28 MCP tools, multi-repo daemon). Recommended install path is GLOBAL via `pip install code-review-graph && code-review-graph install` — auto-configures 11 supported agents. Use the project-scoped `.mcp.json` entry only to scope to one repo or to filter tools. Pairs with `graphify`: graphify for *exploration* (multi-modal), CRG for *review* (incremental, blast-radius) |

## Usage skills

Every optional MCP has a matching skill in `core/mcp/skills/<name>-mcp/SKILL.md`
explaining when to use it, when not to, and common pitfalls. The init skill
copies the matching usage skills into the target project only when the MCP
itself is opted in.

Sequential thinking is always-on, but has its own usage skill too —
overusing it is a common failure mode.

## Adding a new core MCP

1. Verify it's free and universally useful. If it's language-specific, it belongs in `stacks/<lang>/mcp/` instead.
2. If no credentials required → `mcp.partial.json`. If credentials required → `optional/<name>.mcp.json`.
3. Add `skills/<name>-mcp/SKILL.md` explaining when to prefer it vs alternatives (e.g., `gh` CLI), common pitfalls, auth notes.
4. If optional, update `references/scanning.md` in the init skill with the opt-in trigger.
