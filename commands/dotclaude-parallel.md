---
description: Run a parallel-agent workflow using dotclaude's Agent Teams wrapper and fallbacks.
---

Run the `dotclaude-parallel` skill at `~/.claude/skills/dotclaude-parallel/SKILL.md`.

Use Agent Teams if `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is available. If not,
use the fallback pattern that matches the current host agent.

Default to one of these recipes:

- `parallel-pr-review`
- `competing-debug`
- `cross-layer-feature`
- `adversarial-design-review`
- `verification-before-completion`

$ARGUMENTS

