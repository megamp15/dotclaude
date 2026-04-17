#!/usr/bin/env bash
# source: core — Re-inject high-priority project context after conversation compaction.
# Claude Code compacts long conversations; rules/skills previously loaded may be evicted.
# This hook prints a compact digest Claude sees as system context, pointing back to the
# canonical sources so it knows where to look rather than paraphrase from memory.
#
# Invocation: SessionStart or on-demand. Cheap; runs in under a second.

set -u

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CLAUDE_DIR="$REPO_ROOT/.claude"

[ -d "$CLAUDE_DIR" ] || exit 0

echo "=== project context digest ==="
echo "root: $REPO_ROOT"

if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  echo ""
  echo "CLAUDE.md (first 40 lines):"
  head -n 40 "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null | sed 's/^/  /'
fi

if [ -d "$CLAUDE_DIR/rules" ]; then
  echo ""
  echo "rules available (re-read as needed):"
  find "$CLAUDE_DIR/rules" -maxdepth 2 -name '*.md' -type f 2>/dev/null \
    | sed "s|$CLAUDE_DIR/||" | sort | sed 's/^/  /'
fi

if [ -d "$CLAUDE_DIR/skills" ]; then
  echo ""
  echo "skills available (invoke by name):"
  find "$CLAUDE_DIR/skills" -maxdepth 3 \( -name 'SKILL.md' -o -name '*.md' \) -type f 2>/dev/null \
    | grep -v '/references/' \
    | sed "s|$CLAUDE_DIR/skills/||;s|/SKILL.md||;s|\.md$||" \
    | sort -u | sed 's/^/  /'
fi

if [ -d "$CLAUDE_DIR/agents" ]; then
  echo ""
  echo "agents available (invoke via Task):"
  find "$CLAUDE_DIR/agents" -maxdepth 2 -name '*.md' -type f 2>/dev/null \
    | sed "s|$CLAUDE_DIR/agents/||;s|\.md$||" | sort | sed 's/^/  /'
fi

echo ""
echo "=== end digest ==="
