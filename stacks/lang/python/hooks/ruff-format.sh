#!/usr/bin/env bash
# PostToolUse hook: format a Python file after Edit/Write.
# Reads the hook payload from stdin (see Claude Code hook docs).
payload=$(cat)
file=$(echo "$payload" | python -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))")
case "$file" in
  *.py) uv run ruff format "$file" >/dev/null 2>&1 || true ;;
esac
