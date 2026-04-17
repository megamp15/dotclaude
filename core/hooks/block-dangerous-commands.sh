#!/usr/bin/env bash
# source: core/hooks/block-dangerous-commands.sh
#
# PreToolUse hook for Bash. Blocks destructive or high-risk commands
# before they run. Non-zero exit = block. Exit 0 = allow.
#
# Reads the Claude Code hook payload from stdin (JSON).
# See: https://docs.claude.com/en/docs/claude-code/hooks

set -euo pipefail

payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

if [ -z "$cmd" ]; then
  exit 0
fi

# Protected branches configurable via env var; default: main, master, production, release
PROTECTED_BRANCHES="${CLAUDE_PROTECTED_BRANCHES:-main|master|production|release}"

block() {
  echo "BLOCKED by block-dangerous-commands.sh: $1" >&2
  echo "  command: $cmd" >&2
  exit 2
}

# Force push to protected branches
if echo "$cmd" | grep -qE "git push.*(--force|-f)\b" \
   && echo "$cmd" | grep -qE "($PROTECTED_BRANCHES)\b"; then
  block "force push to protected branch"
fi

# Force push in general
if echo "$cmd" | grep -qE "git push.*(--force|--force-with-lease|-f)\b"; then
  echo "WARN: force push detected — confirm the target branch is safe." >&2
fi

# Hard reset
if echo "$cmd" | grep -qE "git reset --hard\b"; then
  block "git reset --hard (destructive; use git stash or a backup branch)"
fi

# Clean -fdx
if echo "$cmd" | grep -qE "git clean.*-[a-z]*f[a-z]*d[a-z]*x\b"; then
  block "git clean -fdx (destructive; includes ignored files)"
fi

# rm -rf at dangerous roots
if echo "$cmd" | grep -qE "rm\s+-[a-z]*r[a-z]*f\s+(/|~|\\\$HOME|\\\$\{HOME\})(\s|$)"; then
  block "rm -rf on filesystem root or home"
fi

# Unbounded DELETE / DROP
if echo "$cmd" | grep -qiE "DROP\s+(TABLE|DATABASE|SCHEMA)\b"; then
  block "SQL DROP"
fi
if echo "$cmd" | grep -qiE "DELETE\s+FROM\s+\w+\s*;"; then
  block "DELETE without WHERE"
fi
if echo "$cmd" | grep -qiE "TRUNCATE\s+TABLE\b"; then
  block "SQL TRUNCATE"
fi

# chmod 777
if echo "$cmd" | grep -qE "chmod\s+(-R\s+)?777\b"; then
  block "chmod 777 (world-writable)"
fi

# curl|sh, wget|sh
if echo "$cmd" | grep -qE "(curl|wget)[^|]*\|\s*(sh|bash|zsh)\b"; then
  block "piping remote content to shell (curl|sh / wget|bash)"
fi

# Destructive branch deletion
if echo "$cmd" | grep -qE "git branch\s+-D\s+($PROTECTED_BRANCHES)\b"; then
  block "force-deleting protected branch"
fi

exit 0
