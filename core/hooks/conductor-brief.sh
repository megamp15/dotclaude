#!/usr/bin/env bash
# source: core/hooks/conductor-brief.sh
#
# SessionStart hook. Prints the project-conductor re-entry brief: the
# durable .claude/project-state.md (if any) plus availability hints for
# brain-mcp and graphify so the agent knows to query them BEFORE asking
# the user what to do.
#
# This is what makes "0 context loss across agents" the default rather
# than something the user has to remember to ask for.
#
# Cheap. Runs in well under a second. Output is added to session context.

set -u

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
STATE_FILE="$REPO_ROOT/.claude/project-state.md"
LEARNINGS_FILE="$REPO_ROOT/.claude/learnings.md"
GRAPH_REPORT="$REPO_ROOT/graphify-out/GRAPH_REPORT.md"
CRG_DB_DIR="$REPO_ROOT/.code-review-graph"

echo "=== conductor brief ==="

# 1. Project state (the agent-agnostic handoff file).
if [ -f "$STATE_FILE" ]; then
  echo ""
  echo "--- .claude/project-state.md ---"
  cat "$STATE_FILE"
  echo "--- end project-state.md ---"
else
  echo ""
  echo "no .claude/project-state.md yet — first session, or it was never written."
  echo "the project-conductor skill will create one at the end of substantive work."
fi

# 2. Learnings log — top 3 most recent entries (newest are on top of the file).
#    Append-only project memory. Zero-dep alternative / supplement to brain-mcp.
#    See .claude/skills/learnings-log/SKILL.md for the writing discipline.
if [ -f "$LEARNINGS_FILE" ]; then
  recent_learnings=$(awk '
    /^## / {
      count++
      if (count > 3) exit
    }
    count >= 1 && count <= 3 { print }
  ' "$LEARNINGS_FILE")

  if [ -n "$recent_learnings" ]; then
    echo ""
    echo "--- .claude/learnings.md (3 most recent) ---"
    echo "$recent_learnings"
    echo "--- end learnings.md ---"
    echo "(open the full file for older entries; append a new one when you discover something non-obvious.)"
  fi
fi

# 3. brain-mcp availability — global install, indexed cross-agent history.
if command -v brain-mcp >/dev/null 2>&1; then
  brain_version=$(brain-mcp --version 2>/dev/null | head -n1 || echo "available")
  echo ""
  echo "[brain-mcp ${brain_version}] cross-agent memory is wired."
  echo "  before asking the user what to do, call:"
  echo "    brain.context_recovery(domain=<project name>)"
  echo "    brain.open_threads()"
  echo "  see .claude/skills/brain-mcp/SKILL.md for the full tool list."
else
  echo ""
  echo "[brain-mcp not installed] cross-agent memory is unavailable."
  echo "  install with:  pipx install brain-mcp && brain-mcp setup"
  echo "  see .claude/skills/brain-mcp/SKILL.md for why this is recommended."
fi

# 4. graphify graph freshness — structural codebase context (exploration).
if [ -f "$GRAPH_REPORT" ]; then
  if command -v stat >/dev/null 2>&1; then
    if stat -c %Y "$GRAPH_REPORT" >/dev/null 2>&1; then
      report_mtime=$(stat -c %Y "$GRAPH_REPORT" 2>/dev/null)
    else
      report_mtime=$(stat -f %m "$GRAPH_REPORT" 2>/dev/null)
    fi
    now=$(date +%s)
    age_days=$(( (now - report_mtime) / 86400 ))
    echo ""
    echo "[graphify graph ${age_days}d old] structural map is available at graphify-out/GRAPH_REPORT.md."
    echo "  read its god nodes + surprises before any structural change."
    if [ "$age_days" -gt 14 ]; then
      echo "  graph is stale — consider rebuilding with:  graphify ./"
    fi
  fi
elif command -v graphify >/dev/null 2>&1; then
  echo ""
  echo "[graphify available, no graph yet] for structural questions:  graphify ./"
fi

# 5. code-review-graph (CRG) — incremental review-time graph.
#    Looks for the SQLite DB rather than a report file (CRG persists state in
#    .code-review-graph/). Different concern than graphify: CRG is the
#    always-fresh review graph, graphify is the multi-modal exploration graph.
if [ -d "$CRG_DB_DIR" ]; then
  echo ""
  echo "[code-review-graph wired] incremental code graph at .code-review-graph/."
  echo "  before reviewing a diff, prefer:"
  echo "    detect_changes_tool / get_review_context_tool / get_impact_radius_tool"
  echo "  see .claude/skills/code-review-graph/SKILL.md for the 28-tool cheat sheet."
elif command -v code-review-graph >/dev/null 2>&1; then
  echo ""
  echo "[code-review-graph available, no graph yet] for first build:  code-review-graph build"
fi

# 6. Phase hint from cheap git heuristics. Conductor will refine this.
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  commit_count=$(git -C "$REPO_ROOT" rev-list --all --count 2>/dev/null || echo 0)
  tag_count=$(git -C "$REPO_ROOT" tag 2>/dev/null | wc -l | tr -d ' ')
  last_commit_ts=$(git -C "$REPO_ROOT" log -1 --format=%ct 2>/dev/null || echo 0)
  if [ "$last_commit_ts" -gt 0 ]; then
    days_since=$(( ($(date +%s) - last_commit_ts) / 86400 ))
  else
    days_since=999
  fi

  phase_hint="unknown"
  if [ "$commit_count" -le 3 ]; then
    phase_hint="greenfield (<=3 commits)"
  elif [ "$days_since" -gt 90 ]; then
    phase_hint="maintenance (last commit ${days_since}d ago)"
  elif [ "$tag_count" -gt 0 ]; then
    phase_hint="established (${tag_count} tag(s), ${commit_count} commits)"
  else
    phase_hint="building (${commit_count} commits, no release tags)"
  fi
  echo ""
  echo "[phase hint] ${phase_hint}"
  echo "  defer to .claude/project-state.md if it disagrees; otherwise project-conductor will confirm."
fi

echo ""
echo "=== end conductor brief ==="
