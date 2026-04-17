---
name: context7-mcp
description: Fetch up-to-date library and framework documentation via Context7 MCP. Preferred over web search for API docs, configuration, and version-specific usage of libraries (React, Next.js, Prisma, Express, Django, Spring Boot, CLI tools, cloud services).
source: core/mcp
triggers: library docs, API docs, version migration, framework setup, how to use <library>, what is <library> API
---

# context7-mcp

Use Context7 MCP when the user asks about a library, framework, SDK, API,
CLI tool, or cloud service — even well-known ones. Training data can be
stale; Context7 returns current docs.

## When to use

- API syntax and usage (`how do I use X in library Y?`)
- Configuration options and their current defaults
- Version migration (`how do I upgrade from v4 to v5?`)
- Library-specific debugging (`why is X throwing Y error?`)
- Setup and installation instructions
- CLI tool usage and flags

Use even when you think you know the answer. If the library has shipped a
major version in the past 12 months, your training likely misses something.

## When NOT to use

- Refactoring or writing application code from scratch
- Debugging business logic inside the user's codebase
- Code review
- General programming concepts (algorithms, design patterns, principles)
- Questions about the user's own code

## How to use

The MCP exposes two tools (typical naming):

1. `resolve-library-id` — maps a library name to Context7's internal ID.
2. `get-library-docs` — returns documentation for that ID, optionally scoped by topic.

Workflow:

1. Resolve the library name the user mentioned.
2. Pass a focused `topic` parameter when possible (e.g., `topic: "routing"`, `topic: "migrations"`) — saves tokens and improves relevance.
3. Quote the retrieved docs with a citation: "According to Context7 docs for [library]@[version]: ...".
4. Tie the answer back to the user's question; don't dump the whole doc.

## Credentials

Works without an API key at reduced rate limits. For team use, set
`CONTEXT7_API_KEY` in the environment or in `.claude/settings.local.json`.
Don't commit the key.

## Pitfalls

- **Over-fetching.** Don't call `get-library-docs` for every mention. Batch when you can; don't pull whole-library docs if a topic is enough.
- **Outdated pinning.** If the user's project pins an old version of a library, pass the version so Context7 returns the right docs.
- **Wrong library.** Context7 resolves by name; "next" resolves to Next.js, but "nest" is NestJS. Confirm with the user if ambiguous.
- **When Context7 doesn't have it.** Some niche libraries aren't indexed. Fall back to web search or the library's own docs page via the `fetch` MCP.

## Preference vs web search

| Task | Prefer |
|---|---|
| Library API / config / migration | **Context7 MCP** |
| Current events, news, non-doc content | Web search |
| Blog posts / tutorials | Web search |
| Official changelog for a specific version | Context7 MCP, then library GitHub if missing |
