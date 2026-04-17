---
name: uv-deps
description: Add, remove, or update Python dependencies using uv
---

# uv-deps

- Add a runtime dep: `uv add <package>`
- Add a dev dep: `uv add --dev <package>`
- Remove: `uv remove <package>`
- Update lockfile: `uv lock`
- Sync environment: `uv sync`

Never edit `pyproject.toml` dependencies by hand — uv writes them. Never
commit without a fresh `uv.lock`.

If a dep pins to an old version for compatibility, document the reason
inline as a comment on the line in `pyproject.toml`.
