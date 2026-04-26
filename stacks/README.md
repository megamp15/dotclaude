# Stacks

Stacks are grouped by category for source-tree hygiene. Target-project source
tags intentionally remain flat as `source: stacks/<name>` so initialized repos
continue to sync across this reorg.

```text
stacks/lang/       python, node-ts, go, rust, dotnet
stacks/frontend/   react, nextjs, angular, svelte, htmx-alpine, reflex
stacks/backend/    fastapi
stacks/infra/      aws, docker, github-actions, kubernetes, terraform, cloudflare-workers
stacks/ml/         pytorch, vllm-ollama
stacks/desktop/    tauri
```

Each stack keeps the same internal shape:

```text
CLAUDE.stack.md
settings.partial.json
rules/
skills/
agents/
hooks/
mcp/
```

Only `CLAUDE.stack.md` and `settings.partial.json` are expected everywhere.
Other folders are optional and should exist only when the stack needs them.

