#!/usr/bin/env bash
# source: core/hooks/block-dangerous-commands.sh
#
# PreToolUse hook for Bash. Blocks destructive or high-risk commands
# before they run. Non-zero exit = block. Exit 0 = allow.
#
# This is the runtime safety net for things the static permissions.deny
# list can't catch — wrapped commands, command substitution, env-injected
# auto-approve, multi-line shell pipelines, etc. It's defense-in-depth, not
# the primary defense. The deny list in core/settings.partial.json is.
#
# Threat model categories (from Claude Code auto-mode design):
#   1. Destroy data           — git reset --hard, rm -rf root, SQL DROP
#   2. Destroy infra          — terraform destroy, docker system prune, etc.
#   3. Exfiltrate secrets     — read ~/.ssh, ~/.aws, ~/.npmrc + pipe to net
#   4. Cross trust boundary   — curl|sh, run cloned untrusted code
#   5. Bypass review          — --no-verify, force push to protected, publish
#   6. Persist access         — write authorized_keys, crontab, systemd unit
#   7. Disable logging        — unset HISTFILE, set +o history, history -c
#   8. Modify own permissions — write to .claude/settings.json
#
# Reads the Claude Code hook payload from stdin (JSON).
# See: https://docs.claude.com/en/docs/claude-code/hooks

set -euo pipefail

payload=$(cat)
cmd=""

# Prefer jq when available; fall back to python; fall back to a sed extraction.
# All three handle escaped quotes; the sed fallback is the weakest and is only
# a last resort so the hook still functions on minimal containers.
if command -v jq >/dev/null 2>&1; then
  cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
elif command -v python3 >/dev/null 2>&1; then
  cmd=$(printf '%s' "$payload" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("command","") or "")' 2>/dev/null || echo "")
elif command -v python >/dev/null 2>&1; then
  cmd=$(printf '%s' "$payload" | python -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("command","") or "")' 2>/dev/null || echo "")
else
  cmd=$(printf '%s' "$payload" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

if [ -z "$cmd" ]; then
  exit 0
fi

# Protected branches configurable via env var; default: main, master, production, release
PROTECTED_BRANCHES="${CLAUDE_PROTECTED_BRANCHES:-main|master|production|release}"

block() {
  echo "BLOCKED by block-dangerous-commands.sh: $1" >&2
  echo "  category: $2" >&2
  echo "  command: $cmd" >&2
  echo "  to override (you-own-the-blast-radius): comment the rule in core/hooks/block-dangerous-commands.sh" >&2
  exit 2
}

# ─── 1. Destroy data ──────────────────────────────────────────────────────────

# Force push to protected branches
if echo "$cmd" | grep -qE "git push.*(--force|-f)\b" \
   && echo "$cmd" | grep -qE "($PROTECTED_BRANCHES)\b"; then
  block "force push to protected branch" "destroy"
fi

# Force push in general (warn — not block; --force-with-lease is sometimes needed)
if echo "$cmd" | grep -qE "git push.*(--force|--force-with-lease|-f)\b"; then
  echo "WARN: force push detected — confirm the target branch is safe." >&2
fi

# Hard reset
if echo "$cmd" | grep -qE "git reset --hard\b"; then
  block "git reset --hard (destructive; use git stash or a backup branch)" "destroy"
fi

# Clean -fdx
if echo "$cmd" | grep -qE "git clean.*-[a-z]*f[a-z]*d[a-z]*x\b"; then
  block "git clean -fdx (destructive; includes ignored files)" "destroy"
fi

# rm -rf at dangerous roots — covers: /, ~, $HOME, ${HOME}, ., ./, .git, .claude
if echo "$cmd" | grep -qE "rm\s+-[a-z]*r[a-z]*f\s+(/|~|\\\$HOME|\\\$\{HOME\}|\.|\./)(\s|$)"; then
  block "rm -rf on filesystem root, home, or current directory" "destroy"
fi
if echo "$cmd" | grep -qE "rm\s+-[a-z]*r[a-z]*f\s+(\.git|\.claude|\.git/|\.claude/)(\s|$)"; then
  block "rm -rf on .git or .claude (destroys repo metadata or agent config)" "destroy"
fi

# Unbounded DELETE / DROP
if echo "$cmd" | grep -qiE "DROP\s+(TABLE|DATABASE|SCHEMA)\b"; then
  block "SQL DROP" "destroy"
fi
if echo "$cmd" | grep -qiE "DELETE\s+FROM\s+\w+\s*;"; then
  block "DELETE without WHERE" "destroy"
fi
if echo "$cmd" | grep -qiE "TRUNCATE\s+TABLE\b"; then
  block "SQL TRUNCATE" "destroy"
fi

# Destructive branch deletion on protected
if echo "$cmd" | grep -qE "git branch\s+-D\s+($PROTECTED_BRANCHES)\b"; then
  block "force-deleting protected branch" "destroy"
fi
if echo "$cmd" | grep -qE "git push\s+(--delete|origin\s+--delete|origin\s+:)\s*($PROTECTED_BRANCHES)\b"; then
  block "deleting protected branch on remote" "destroy"
fi

# ─── 2. Destroy infra ─────────────────────────────────────────────────────────

# terraform destroy / apply -auto-approve (also caught by stacks/terraform deny + block-destroy-apply hook)
if echo "$cmd" | grep -qE "terraform\s+destroy\b"; then
  block "terraform destroy" "destroy-infra"
fi
if echo "$cmd" | grep -qE "(terraform|opentofu|tofu)\s+apply\b.*(--auto-approve|-auto-approve)\b"; then
  block "terraform apply -auto-approve (skips review of plan)" "destroy-infra"
fi

# Docker system-wide prune
if echo "$cmd" | grep -qE "docker\s+system\s+prune\s.*(-a|--all)\b"; then
  block "docker system prune -a (deletes all unused images + caches)" "destroy-infra"
fi

# Compose down with volumes
if echo "$cmd" | grep -qE "docker\s+compose\s+down\s.*(-v|--volumes)\b"; then
  block "docker compose down -v (deletes named volumes — usually database data)" "destroy-infra"
fi

# kubectl delete on namespaces or all
if echo "$cmd" | grep -qE "kubectl\s+delete\s+(namespace|ns|all)\b"; then
  block "kubectl delete namespace/all (mass deletion)" "destroy-infra"
fi
if echo "$cmd" | grep -qE "kubectl\s+delete\s+.*--all\b"; then
  block "kubectl delete --all (mass deletion)" "destroy-infra"
fi

# AWS / cloud mass-delete patterns
if echo "$cmd" | grep -qE "aws\s+s3\s+rm\s+s3://\S+\s.*--recursive\b"; then
  block "aws s3 rm --recursive (irreversible bucket data deletion)" "destroy-infra"
fi
if echo "$cmd" | grep -qE "aws\s+s3\s+rb\s+s3://\S+\s.*--force\b"; then
  block "aws s3 rb --force (deletes bucket and contents)" "destroy-infra"
fi

# chmod 777
if echo "$cmd" | grep -qE "chmod\s+(-R\s+)?777\b"; then
  block "chmod 777 (world-writable)" "weaken-security"
fi

# ─── 3. Exfiltrate secrets ───────────────────────────────────────────────────

# Reading sensitive files AND piping somewhere networked.
# Heuristic: if the cmd touches one of these paths AND has a pipe to curl/wget/nc/scp/ssh
SENSITIVE='~/\.ssh/(id_|authorized_keys|known_hosts)|~/\.aws/credentials|~/\.kube/config|~/\.netrc|~/\.npmrc|~/\.pypirc|~/\.docker/config\.json'
if echo "$cmd" | grep -qE "($SENSITIVE)" \
   && echo "$cmd" | grep -qE "\|\s*(curl|wget|nc|netcat|scp|ssh)\b"; then
  block "reading credentials and piping to network tool (curl/scp/nc/ssh)" "exfiltrate"
fi

# Direct upload of credential dirs
if echo "$cmd" | grep -qE "(curl|wget)\s.*(-T|--upload-file|--data-binary @|-d @)\s*~/(\.ssh|\.aws|\.kube|\.npmrc|\.pypirc)"; then
  block "uploading credential directory contents to network endpoint" "exfiltrate"
fi
if echo "$cmd" | grep -qE "scp\s+~/(\.ssh|\.aws|\.kube)/"; then
  block "scp from credential directory" "exfiltrate"
fi

# Posting whole env to a network endpoint (env > /tmp/x; curl ... @/tmp/x is harder to detect — skip and accept)
if echo "$cmd" | grep -qE "(env|printenv|set)\s*\|\s*(curl|wget|nc|netcat)\b"; then
  block "piping env to network tool (likely env exfiltration)" "exfiltrate"
fi

# ─── 4. Cross trust boundary ─────────────────────────────────────────────────

# curl|sh, wget|sh, irm|iex, etc.
if echo "$cmd" | grep -qE "(curl|wget)[^|]*\|\s*(sh|bash|zsh|fish|ksh)\b"; then
  block "piping remote content to shell (curl|sh / wget|bash)" "trust-boundary"
fi

# powershell remote execution patterns
if echo "$cmd" | grep -qE "(iex|Invoke-Expression).*\(\s*(iwr|Invoke-WebRequest|curl)\b"; then
  block "PowerShell IEX of remote content (analogous to curl|sh)" "trust-boundary"
fi

# eval of dynamic content (eval $(curl...))
if echo "$cmd" | grep -qE "eval\s+[\"']?\\\$\(\s*(curl|wget)\b"; then
  block "eval of curl/wget output" "trust-boundary"
fi

# ─── 5. Bypass review ────────────────────────────────────────────────────────

# --no-verify on commit/push (bypasses pre-commit / pre-push hooks)
if echo "$cmd" | grep -qE "git\s+(commit|push|merge)\s.*--no-verify\b"; then
  block "git --no-verify (bypasses commit/push hooks)" "bypass-review"
fi

# Package publish
if echo "$cmd" | grep -qE "(npm|pnpm|yarn|bun)\s+publish\b"; then
  block "package publish to registry (irreversible release)" "bypass-review"
fi
if echo "$cmd" | grep -qE "(twine|uv|poetry|hatch)\s+(upload|publish)\b"; then
  block "Python package publish to PyPI (irreversible release)" "bypass-review"
fi
if echo "$cmd" | grep -qE "cargo\s+publish\b"; then
  block "cargo publish (irreversible release to crates.io)" "bypass-review"
fi
if echo "$cmd" | grep -qE "gem\s+push\b"; then
  block "gem push (irreversible release to RubyGems)" "bypass-review"
fi

# ─── 6. Persist access ───────────────────────────────────────────────────────

# Writing to authorized_keys
if echo "$cmd" | grep -qE "(>>?|tee\b.*)\s*~/\.ssh/authorized_keys"; then
  block "writing to ~/.ssh/authorized_keys (persist remote access)" "persist"
fi

# crontab edit / install
if echo "$cmd" | grep -qE "crontab\s+(-e|-r|/|<)"; then
  block "crontab edit/replace (persistent scheduled execution)" "persist"
fi

# systemd / launchd persistence
if echo "$cmd" | grep -qE "systemctl\s+(enable|disable|mask|unmask)\b"; then
  block "systemctl enable/disable (persistence change)" "persist"
fi
if echo "$cmd" | grep -qE "launchctl\s+(load|unload|bootstrap|bootout)\b"; then
  block "launchctl load/unload (macOS persistence change)" "persist"
fi

# Writing to shell rc files (high-confidence: redirection target)
if echo "$cmd" | grep -qE "(>>?|tee\b.*)\s*~/(\.bashrc|\.zshrc|\.profile|\.bash_profile|\.zprofile)\b"; then
  block "writing to shell rc (~/.bashrc, ~/.zshrc, etc — persists across sessions)" "persist"
fi

# ─── 7. Disable logging ──────────────────────────────────────────────────────

if echo "$cmd" | grep -qE "(unset\s+HISTFILE|export\s+HISTFILE=/dev/null|set\s+\+o\s+history|history\s+-c)"; then
  block "disabling shell history (anti-forensic; never legitimate from agent)" "disable-logging"
fi
if echo "$cmd" | grep -qE "(rm|truncate)\s.*~/\.(bash_history|zsh_history|history)\b"; then
  block "truncating shell history file" "disable-logging"
fi

# ─── 8. Modify own permissions ───────────────────────────────────────────────

# Writing to .claude/settings.json (covered by Write/Edit deny rules, but
# catch shell-level writes too: > redirection, sed -i, jq pipe)
if echo "$cmd" | grep -qE "(>|>>|tee\b.*)\s*\.?claude/settings(\.local)?\.json\b"; then
  block "writing to .claude/settings.json from shell (agent should not modify its own permissions)" "modify-own-permissions"
fi
if echo "$cmd" | grep -qE "sed\s+-i\b.*\.?claude/settings(\.local)?\.json\b"; then
  block "in-place edit of .claude/settings.json from shell" "modify-own-permissions"
fi

exit 0
