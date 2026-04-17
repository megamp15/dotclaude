#!/usr/bin/env bash
# source: core/hooks/warn-large-files.sh
#
# PostToolUse hook for Write|Edit|MultiEdit. Warns when the edited file
# is unusually large (probable build artifact, binary, or generated file
# that shouldn't be hand-edited). Non-blocking by default.

set -euo pipefail

payload=$(cat)
file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || echo "")

if [ -z "$file" ] || [ ! -f "$file" ]; then
  exit 0
fi

THRESHOLD_BYTES="${CLAUDE_LARGE_FILE_BYTES:-500000}"   # 500 KB default
LINE_THRESHOLD="${CLAUDE_LARGE_FILE_LINES:-2000}"

# Build artifact / generated patterns → always warn
case "$(basename "$file")" in
  *.min.js|*.min.css|*.bundle.js|*.bundle.css|*.map|*-lock.json|*.lock|*.lockb|pnpm-lock.yaml|yarn.lock|poetry.lock|uv.lock|Cargo.lock|go.sum)
    echo "⚠ warn-large-files.sh: $file looks like a generated/lock file — avoid hand-editing." >&2
    exit 0 ;;
esac

case "$file" in
  */dist/*|*/build/*|*/.next/*|*/node_modules/*|*/target/*|*/__pycache__/*|*/.venv/*|*/venv/*)
    echo "⚠ warn-large-files.sh: $file is under a build/vendor directory — edits likely lost on rebuild." >&2
    exit 0 ;;
esac

# Size check
size=$(wc -c < "$file" 2>/dev/null || echo 0)
if [ "$size" -gt "$THRESHOLD_BYTES" ]; then
  echo "⚠ warn-large-files.sh: $file is ${size} bytes (> ${THRESHOLD_BYTES}) — consider splitting." >&2
fi

# Line check — skip for binary-like files
if file -b "$file" 2>/dev/null | grep -qiE 'text|json|xml|yaml|script'; then
  lines=$(wc -l < "$file" 2>/dev/null || echo 0)
  if [ "$lines" -gt "$LINE_THRESHOLD" ]; then
    echo "⚠ warn-large-files.sh: $file has ${lines} lines (> ${LINE_THRESHOLD}) — consider refactoring." >&2
  fi
fi

exit 0
