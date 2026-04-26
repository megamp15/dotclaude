#!/usr/bin/env bash
# source: scripts/dotclaude-resume.sh
#
# Print the dotclaude re-entry brief on demand. Useful for:
#   - Agents that don't fire SessionStart hooks (some Codex / Cursor configs).
#   - Manual `/dotclaude-resume` slash command.
#   - Humans pasting the brief into any agent's chat to bootstrap.
#
# Identical to the SessionStart conductor brief but invokable anywhere,
# anytime. Keep this file's behavior in sync with
# core/hooks/conductor-brief.sh.

set -u

# Find the dotclaude install. Two paths:
#   1. DOTCLAUDE_HOME points at the repo (preferred — same source).
#   2. .claude/hooks/conductor-brief.sh exists in the current project.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK=""

if [ -n "${DOTCLAUDE_HOME:-}" ] && [ -f "$DOTCLAUDE_HOME/core/hooks/conductor-brief.sh" ]; then
  HOOK="$DOTCLAUDE_HOME/core/hooks/conductor-brief.sh"
elif [ -f ".claude/hooks/conductor-brief.sh" ]; then
  HOOK=".claude/hooks/conductor-brief.sh"
elif [ -f "$SCRIPT_DIR/../core/hooks/conductor-brief.sh" ]; then
  HOOK="$SCRIPT_DIR/../core/hooks/conductor-brief.sh"
fi

if [ -z "$HOOK" ]; then
  echo "dotclaude-resume: cannot locate conductor-brief.sh" >&2
  echo "  set DOTCLAUDE_HOME, or run from inside a dotclaude-initialized repo, or place this" >&2
  echo "  script next to dotclaude's scripts/ folder." >&2
  exit 1
fi

exec bash "$HOOK"
