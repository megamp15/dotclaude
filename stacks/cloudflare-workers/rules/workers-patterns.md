---
source: stacks/cloudflare-workers
---

# Workers patterns

- Keep request parsing, auth, handler logic, and binding access separated.
- Validate environment bindings at startup or first use with clear errors.
- Avoid Node-only APIs unless the compatibility flag and runtime support are
  explicit.
- Test cache behavior, headers, and error paths; edge bugs are often contract
  bugs.
- Never deploy or mutate remote secrets/KV/D1 without explicit user approval.

