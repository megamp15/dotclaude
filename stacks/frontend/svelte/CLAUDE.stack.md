---
source: stacks/svelte
---

# Svelte stack

- Prefer SvelteKit conventions for routing, loading, actions, and invalidation.
- Keep server-only code in server modules and never expose secrets to client
  bundles.
- Use stores/runes sparingly; local component state is often enough.
- Verify with type checking, unit tests, and Playwright when behavior crosses
  browser boundaries.

