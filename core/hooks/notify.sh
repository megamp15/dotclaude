#!/usr/bin/env bash
# source: core/hooks/notify.sh
#
# Stop hook. Fires a native OS notification when Claude finishes its turn.
# Respects CLAUDE_NOTIFY=0 to disable. Cross-platform: macOS, Linux, WSL.

set -euo pipefail

if [ "${CLAUDE_NOTIFY:-1}" = "0" ]; then
  exit 0
fi

payload=$(cat || echo "{}")
session_id=$(printf '%s' "$payload" | jq -r '.session_id // ""' 2>/dev/null || echo "")
title="Claude Code"
message="Session finished — needs input"
[ -n "$session_id" ] && message="$message (session ${session_id:0:8})"

# macOS
if command -v terminal-notifier >/dev/null 2>&1; then
  terminal-notifier -title "$title" -message "$message" -sound default >/dev/null 2>&1 || true
  exit 0
fi
if [ "$(uname)" = "Darwin" ]; then
  osascript -e "display notification \"$message\" with title \"$title\"" >/dev/null 2>&1 || true
  exit 0
fi

# Linux
if command -v notify-send >/dev/null 2>&1; then
  notify-send "$title" "$message" >/dev/null 2>&1 || true
  exit 0
fi

# WSL → Windows toast via powershell
if command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -Command "
    [reflection.assembly]::loadwithpartialname('System.Windows.Forms') > \$null;
    [reflection.assembly]::loadwithpartialname('System.Drawing') > \$null;
    \$n = New-Object System.Windows.Forms.NotifyIcon;
    \$n.Icon = [System.Drawing.SystemIcons]::Information;
    \$n.Visible = \$true;
    \$n.ShowBalloonTip(3000, '$title', '$message', [System.Windows.Forms.ToolTipIcon]::Info);
    Start-Sleep -Seconds 1;
    \$n.Dispose();
  " >/dev/null 2>&1 || true
  exit 0
fi

# Fallback: terminal bell
printf '\a' >&2 || true
exit 0
