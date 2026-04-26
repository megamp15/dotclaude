#!/usr/bin/env bash
# source: core/hooks/agent-team-task-completed.sh
#
# TaskCompleted hook for Agent Teams. If CLAUDE_TEAM_VERIFY_CMD is set, run it
# as a completion gate. By default failures are advisory; set
# CLAUDE_AGENT_TEAM_STRICT=1 to make failures block the hook.

set -u

payload="$(cat || echo '{}')"
name="$(printf '%s' "$payload" | jq -r '.teammate.name // .name // .agent.name // "teammate"' 2>/dev/null || echo teammate)"
task="$(printf '%s' "$payload" | jq -r '.task.title // .task.description // .task // ""' 2>/dev/null || echo '')"

echo "[agent-team-task-completed] ${name} completed a task."
[ -n "$task" ] && echo "[agent-team-task-completed] Task: ${task}"

if [ -z "${CLAUDE_TEAM_VERIFY_CMD:-}" ]; then
  echo "[agent-team-task-completed] No CLAUDE_TEAM_VERIFY_CMD set; require the teammate to report tests/checks run."
  exit 0
fi

echo "[agent-team-task-completed] Running verification: ${CLAUDE_TEAM_VERIFY_CMD}"
sh -c "$CLAUDE_TEAM_VERIFY_CMD"
status=$?

if [ "$status" -eq 0 ]; then
  echo "[agent-team-task-completed] Verification passed."
  exit 0
fi

echo "[agent-team-task-completed] Verification failed with exit ${status}."
if [ "${CLAUDE_AGENT_TEAM_STRICT:-0}" = "1" ]; then
  exit "$status"
fi

echo "[agent-team-task-completed] Advisory mode; not blocking. Set CLAUDE_AGENT_TEAM_STRICT=1 to block."
exit 0

