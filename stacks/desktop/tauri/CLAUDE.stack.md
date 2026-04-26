---
source: stacks/tauri
---

# Tauri stack

- Treat the Rust command layer as a privileged boundary.
- Keep filesystem, shell, network, and OS integrations least-privilege.
- Validate all inputs crossing from webview to Rust commands.
- Review `tauri.conf.*` capability and allowlist changes carefully.

