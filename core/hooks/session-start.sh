#!/usr/bin/env bash
# source: core/hooks/session-start.sh
#
# SessionStart hook. Injects a brief project context snapshot into the
# session: current branch, last commit, dirty state, open PR (if gh available),
# stashes. Output goes to stdout and is added to the session context.

set -euo pipefail

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

branch=$(git branch --show-current 2>/dev/null || echo "(detached)")
last_commit=$(git log -1 --pretty=format:'%h %s (%cr by %an)' 2>/dev/null || echo "(no commits)")
dirty=""
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  dirty=" [dirty]"
fi

stash_count=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
upstream=$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo "")
ahead_behind=""
if [ -n "$upstream" ]; then
  ahead=$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
  behind=$(git rev-list --count "HEAD..@{u}" 2>/dev/null || echo 0)
  if [ "$ahead" -gt 0 ] || [ "$behind" -gt 0 ]; then
    ahead_behind=" (↑${ahead} ↓${behind} vs ${upstream})"
  fi
fi

pr_info=""
if command -v gh >/dev/null 2>&1; then
  pr_info=$(gh pr view --json number,title,isDraft,state 2>/dev/null \
    | jq -r 'if . then "  PR #\(.number) [\(.state)\(if .isDraft then " / draft" else "" end)]: \(.title)" else "" end' \
    2>/dev/null || echo "")
fi

cat <<EOF
[session-start]
  branch: ${branch}${dirty}${ahead_behind}
  last:   ${last_commit}
  stashes: ${stash_count}
${pr_info}
EOF

exit 0
