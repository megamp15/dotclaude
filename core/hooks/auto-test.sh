#!/usr/bin/env bash
# source: core — After editing a source file, run the related test(s) if they exist.
# Best-effort, non-blocking: prints PASS/FAIL summary into the hook's stdout which
# Claude sees as context. Never exits non-zero (tests failing is signal, not error).
#
# Invocation: PostToolUse on Edit|Write|MultiEdit. Opt-in: set CLAUDE_AUTO_TEST=1.
# Disabled by default because running tests on every edit is noisy for large edits.

set -u

[ "${CLAUDE_AUTO_TEST:-0}" = "1" ] || exit 0

INPUT="$(cat)"
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)"

[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0

case "$FILE_PATH" in
  *_test.go|*_test.py|*.test.ts|*.test.tsx|*.test.js|*.spec.ts|*.spec.tsx|*.spec.js) ;;  # it IS a test file; fall through
  *.test.*|*.spec.*) ;;
  *)
    # Source file — try to find a sibling test.
    dir="$(dirname "$FILE_PATH")"
    base="$(basename "$FILE_PATH")"
    stem="${base%.*}"
    ext="${base##*.}"
    candidates=(
      "$dir/${stem}_test.$ext"
      "$dir/test_${stem}.$ext"
      "$dir/${stem}.test.$ext"
      "$dir/${stem}.spec.$ext"
      "$dir/__tests__/${stem}.test.$ext"
      "$dir/../tests/test_${stem}.$ext"
    )
    found=""
    for c in "${candidates[@]}"; do
      [ -f "$c" ] && { found="$c"; break; }
    done
    [ -z "$found" ] && exit 0
    FILE_PATH="$found"
    ;;
esac

if command -v git >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null)"
fi
REPO_ROOT="${REPO_ROOT:-$(pwd)}"

run() {
  ( cd "$REPO_ROOT" && "$@" ) 2>&1 | tail -n 20
}

case "$FILE_PATH" in
  *.py)
    if command -v pytest >/dev/null 2>&1; then
      echo "[auto-test] pytest $FILE_PATH"
      run pytest -x --tb=short "$FILE_PATH"
    fi
    ;;
  *.ts|*.tsx|*.js|*.jsx)
    if [ -x "$REPO_ROOT/node_modules/.bin/vitest" ]; then
      echo "[auto-test] vitest $FILE_PATH"
      run ./node_modules/.bin/vitest run --reporter=basic "$FILE_PATH"
    elif [ -x "$REPO_ROOT/node_modules/.bin/jest" ]; then
      echo "[auto-test] jest $FILE_PATH"
      run ./node_modules/.bin/jest --silent "$FILE_PATH"
    fi
    ;;
  *.go)
    echo "[auto-test] go test $(dirname "$FILE_PATH")"
    run go test "$(dirname "$FILE_PATH")"
    ;;
esac

exit 0
