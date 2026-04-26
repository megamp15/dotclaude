---
name: workers-engineer
description: Cloudflare Workers skill for edge runtime constraints, Wrangler, bindings, KV/D1/R2/Durable Objects/Queues, caching, request handling, tests, and deployment safety.
source: stacks/cloudflare-workers
triggers: Cloudflare Workers, wrangler, edge runtime, KV, D1, R2, Durable Object, Workers Queue, Pages Functions, Miniflare, cache API
---

# workers-engineer

Use for Cloudflare Workers implementation, review, and debugging.

## Defaults

- Design around explicit bindings and edge runtime limits.
- Keep remote mutations gated by user approval.
- Prefer local `wrangler dev` / Miniflare and unit tests before deploy.
- Review cache keys, headers, auth, and error responses as public contracts.

