#!/usr/bin/env bash
# source: core — Format files after edit using the project's configured formatter.
# Detects formatter per-language via local config. Silent no-op if no formatter configured.
# Never fails the hook (formatting is best-effort; don't block the edit pipeline).
#
# Invocation: PostToolUse on Edit|Write|MultiEdit. Input payload on stdin as JSON.

set -u

INPUT="$(cat)"

# Extract the path of the file that was just edited. jq is standard in Claude Code envs.
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)"

[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0

# Resolve repo root so tool lookups hit the project, not home configs.
if command -v git >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null)"
fi
REPO_ROOT="${REPO_ROOT:-$(pwd)}"

format_with() {
  local cmd="$1"; shift
  command -v "$cmd" >/dev/null 2>&1 || return 1
  ( cd "$REPO_ROOT" && "$cmd" "$@" "$FILE_PATH" ) >/dev/null 2>&1 || true
  return 0
}

case "$FILE_PATH" in
  *.py)
    # Prefer ruff if project uses it; else black.
    if [ -f "$REPO_ROOT/pyproject.toml" ] && grep -q "ruff" "$REPO_ROOT/pyproject.toml" 2>/dev/null; then
      format_with ruff format && exit 0
    fi
    format_with black -q && exit 0
    ;;
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.json|*.md|*.mdx|*.css|*.scss|*.html|*.yml|*.yaml)
    # Prefer project-local binary; fall back to global.
    if [ -x "$REPO_ROOT/node_modules/.bin/prettier" ]; then
      ( cd "$REPO_ROOT" && ./node_modules/.bin/prettier --write "$FILE_PATH" ) >/dev/null 2>&1 || true
      exit 0
    fi
    format_with prettier --write && exit 0
    ;;
  *.go)
    format_with gofmt -w && exit 0
    ;;
  *.rs)
    format_with rustfmt && exit 0
    ;;
  *.sh|*.bash)
    format_with shfmt -w && exit 0
    ;;
  *.tf|*.tfvars)
    format_with terraform fmt && exit 0
    ;;
  *.sql)
    format_with sqlfluff format --dialect ansi && exit 0
    ;;
esac

exit 0
