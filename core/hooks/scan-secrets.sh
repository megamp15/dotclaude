#!/usr/bin/env bash
# source: core/hooks/scan-secrets.sh
#
# PostToolUse hook for Write|Edit|MultiEdit. Scans the just-edited file
# for common secret patterns. Emits warnings to stderr (non-blocking
# by default). Set CLAUDE_SCAN_SECRETS_BLOCK=1 to block on hits.

set -euo pipefail

payload=$(cat)
file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || echo "")

if [ -z "$file" ] || [ ! -f "$file" ]; then
  exit 0
fi

# Skip obvious binary and lock files
case "$file" in
  *.lock|*.lockb|*-lock.json|*.min.js|*.min.css|*.map|*.bin|*.so|*.dylib|*.dll|*.png|*.jpg|*.jpeg|*.gif|*.webp|*.pdf)
    exit 0 ;;
esac

hits=0
report() {
  echo "⚠ scan-secrets.sh: possible secret in $file — $1" >&2
  hits=$((hits + 1))
}

# AWS
grep -Eq 'AKIA[0-9A-Z]{16}' "$file" && report "AWS Access Key ID"
grep -Eq 'aws_secret_access_key\s*=\s*[A-Za-z0-9/+=]{40}' "$file" && report "AWS Secret Access Key"

# GitHub
grep -Eq 'gh[pousr]_[A-Za-z0-9_]{36,}' "$file" && report "GitHub token (classic or fine-grained)"
grep -Eq 'github_pat_[A-Za-z0-9_]{80,}' "$file" && report "GitHub fine-grained PAT"

# Slack
grep -Eq 'xox[abpors]-[A-Za-z0-9-]{10,}' "$file" && report "Slack token"

# Google API
grep -Eq 'AIza[0-9A-Za-z_-]{35}' "$file" && report "Google API key"

# OpenAI / Anthropic
grep -Eq 'sk-[A-Za-z0-9]{20,}' "$file" && report "OpenAI-style API key (sk-...)"
grep -Eq 'sk-ant-[A-Za-z0-9_-]{20,}' "$file" && report "Anthropic API key"

# Stripe
grep -Eq 'sk_live_[A-Za-z0-9]{20,}' "$file" && report "Stripe live secret key"
grep -Eq 'rk_live_[A-Za-z0-9]{20,}' "$file" && report "Stripe live restricted key"

# Private keys
grep -Eq '-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----' "$file" && report "PEM private key"

# Generic high-entropy env var assignment (heuristic, noisy — last)
grep -Eq '(SECRET|PASSWORD|TOKEN|API_KEY)\s*=\s*["'\'']?[A-Za-z0-9+/=_-]{24,}' "$file" \
  && report "generic secret-shaped env assignment"

if [ "$hits" -gt 0 ]; then
  if [ "${CLAUDE_SCAN_SECRETS_BLOCK:-0}" = "1" ]; then
    echo "BLOCKED: $hits potential secret(s) detected in $file" >&2
    exit 2
  fi
fi

exit 0
