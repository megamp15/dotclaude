---
source: stacks/tauri
---

# Tauri security

- Do not widen capabilities to make a feature pass quickly.
- Avoid shell execution; if unavoidable, use fixed commands and validated args.
- Keep updater/signing keys out of the repo and out of agent-readable files.
- Treat drag/drop paths, URLs, and IPC payloads as untrusted input.
- Prefer explicit command allowlists and small command handlers.

