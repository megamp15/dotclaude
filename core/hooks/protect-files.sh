#!/usr/bin/env bash
# source: core/hooks/protect-files.sh
#
# PreToolUse hook for Write|Edit|MultiEdit. Blocks or warns on edits
# to sensitive files. Exit 2 = block; exit 0 = allow.

set -euo pipefail

payload=$(cat)
file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || echo "")

if [ -z "$file" ]; then
  exit 0
fi

# Hard-block list — never editable through Claude tools
HARD_BLOCK=(
  "*.pem"
  "*.key"
  "*.p12"
  "*.pfx"
  "*_rsa"
  "*_ed25519"
  "*_ecdsa"
  "*.gpg"
  ".npmrc"
  ".pypirc"
  ".netrc"
  ".aws/credentials"
  ".ssh/id_*"
  ".ssh/known_hosts"
  ".claude/hooks/*"
)

# Confirm-first list — editable but always warns
WARN=(
  ".env"
  ".env.*"
  "secrets.*"
  "credentials.*"
  ".claude/settings.json"
  ".mcp.json"
  "docker-compose.prod.*"
  "Dockerfile.prod"
  "terraform.tfvars"
  "*.tfstate"
)

match_any() {
  local path=$1
  shift
  for pattern in "$@"; do
    # shellcheck disable=SC2053
    case "$path" in $pattern) return 0 ;; esac
    # also match basename
    case "$(basename "$path")" in $pattern) return 0 ;; esac
  done
  return 1
}

if match_any "$file" "${HARD_BLOCK[@]}"; then
  echo "BLOCKED by protect-files.sh: $file matches hard-block list" >&2
  echo "  If this is intentional, edit the file outside Claude Code." >&2
  exit 2
fi

if match_any "$file" "${WARN[@]}"; then
  echo "WARN: editing sensitive file $file — confirm this is intended." >&2
fi

exit 0
