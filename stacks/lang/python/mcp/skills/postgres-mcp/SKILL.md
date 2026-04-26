---
name: postgres-mcp
description: Query and inspect a Postgres database through the MCP server. Use for schema exploration, read-only queries, and quick data checks from inside a Claude Code session.
triggers: postgres mcp, psql, database query, schema, sql explain, analyze query
source: stacks/python/mcp
---

# Postgres MCP

Anthropic reference MCP server for Postgres. Free. Connects via a standard
connection string supplied in `POSTGRES_CONNECTION_STRING` env var.

## When to use

- Inspecting schema / table definitions mid-conversation
- Running read-only SELECT queries to sanity-check data
- EXPLAIN / EXPLAIN ANALYZE on a draft query before committing it to code
- Counting rows, checking constraints, verifying a migration landed

## When NOT to use

- **Writes.** This server is not a production tool. Run migrations through your
  app's migration tool (`alembic`, `django-admin migrate`, etc.), not the MCP.
- **Bulk exports.** MCP responses go through the model — massive result sets
  eat context and cost money. Use `psql -c "COPY ..."` for exports.

## Auth & connection

Set in your shell init or `.env.local` (gitignored):

```bash
export POSTGRES_CONNECTION_STRING="postgresql://user:pass@localhost:5432/dbname"
```

For production DBs, connect through a read-only replica with a read-only user.
Never point the MCP at a primary with a write-capable role.

## Common pitfalls

- **Timeouts on big queries** — the MCP doesn't stream. Add `LIMIT` to exploratory queries.
- **Schema in multiple search_paths** — qualify table names (`public.users`) if you get "relation not found".
- **Credentials in logs** — the connection string is passed as an argv entry. On shared hosts, prefer `PGSERVICE` config files.
