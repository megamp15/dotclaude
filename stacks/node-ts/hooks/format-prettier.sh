#!/usr/bin/env bash
# source: stacks/node-ts — run prettier on the just-edited JS/TS/JSON/Markdown file if a
# local prettier is available. Silent no-op otherwise. Never fails the hook.
#
# This duplicates core's format-on-save behavior for prettier specifically, but runs
# tighter: only prettier, no formatter detection, pinned to the project-local binary.
# Projects with a stack-specific formatter preference can use this; otherwise core's
# format-on-save handles it.

set -u

INPUT="$(cat)"
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)"

[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0

case "$FILE_PATH" in
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.mts|*.cts|*.json|*.md|*.mdx|*.css|*.scss|*.html|*.yml|*.yaml|*.vue) ;;
  *) exit 0 ;;
esac

if command -v git >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null)"
fi
REPO_ROOT="${REPO_ROOT:-$(pwd)}"

if [ -x "$REPO_ROOT/node_modules/.bin/prettier" ]; then
  ( cd "$REPO_ROOT" && ./node_modules/.bin/prettier --write --log-level=silent "$FILE_PATH" ) >/dev/null 2>&1 || true
elif command -v prettier >/dev/null 2>&1; then
  ( cd "$REPO_ROOT" && prettier --write --log-level=silent "$FILE_PATH" ) >/dev/null 2>&1 || true
fi

exit 0
