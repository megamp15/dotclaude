# Python stack MCPs

MCP servers commonly relevant to Python projects. Opt-in via the init
interview — the scanner proposes them when it sees matching evidence
(env vars, imports, file patterns).

All servers here are free. Paid services (Snyk, Datadog, etc.) are
the user's responsibility — add credentials and server configs manually.

## Layout

```
stacks/python/mcp/
├── optional/                ← opt-in via interview
│   ├── postgres.mcp.json    ← proposed if POSTGRES_URL/DATABASE_URL env or psycopg/asyncpg imported
│   └── sqlite.mcp.json      ← proposed if sqlite3 imported or *.db/*.sqlite file present
└── skills/
    └── postgres-mcp/SKILL.md
```

No `mcp.partial.json` here — nothing in this stack is always-on. All
Python-adjacent MCPs are conditional on project evidence.

## Adding a new Python MCP

1. Confirm it's free and genuinely more useful for Python projects than for other stacks. If cross-stack, move it to `core/mcp/`.
2. Put the server config in `optional/<name>.mcp.json`.
3. Add the scan signal and opt-in trigger to the init skill's `references/scanning.md`.
4. Add a usage skill at `skills/<name>-mcp/SKILL.md`.
