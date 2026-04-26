---
source: stacks/svelte
---

# Svelte patterns

- Keep `load` functions focused on data fetching and authorization checks.
- Use form actions for progressive-enhancement-friendly mutations.
- Prefer accessible HTML and role/name based tests.
- Avoid over-global stores; colocate state with the component tree when possible.
- Treat `+page.server.*` and `+layout.server.*` as trust-boundary files.

