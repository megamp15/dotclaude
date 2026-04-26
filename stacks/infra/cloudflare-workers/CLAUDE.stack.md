---
source: stacks/cloudflare-workers
---

# Cloudflare Workers stack

- Keep edge runtime limits in mind: CPU time, subrequest count, body size,
  streaming behavior, and cold-start-sensitive dependencies.
- Treat bindings as infrastructure contracts; review changes to KV, D1, R2,
  Durable Objects, Queues, and secrets carefully.
- Prefer local/miniflare tests before remote operations.

