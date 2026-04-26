#!/usr/bin/env bash
# source: core/hooks/agent-team-idle.sh
#
# TeammateIdle hook for Agent Teams. It is intentionally advisory: idle can be
# healthy if a teammate is waiting for a lock or clarification.

set -u

payload="$(cat || echo '{}')"
name="$(printf '%s' "$payload" | jq -r '.teammate.name // .name // .agent.name // "teammate"' 2>/dev/null || echo teammate)"
task="$(printf '%s' "$payload" | jq -r '.task.title // .task.description // .task // ""' 2>/dev/null || echo '')"

echo "[agent-team-idle] ${name} is idle."
[ -n "$task" ] && echo "[agent-team-idle] Task: ${task}"
echo "[agent-team-idle] Lead action: narrow the task, provide missing context, reassign, or mark blocked."

exit 0

