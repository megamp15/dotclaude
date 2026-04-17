#!/usr/bin/env bash
# source: stacks/terraform — defense-in-depth over the permissions deny list.
# Blocks destructive Terraform invocations even if they slipped past the deny list
# (odd quoting, PATH aliasing, an inline shell wrapper).
#
# Exit 2 to signal a blocked PreToolUse to Claude Code with an explanation.
#
# Invocation: PreToolUse on Bash.

set -u

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"

[ -z "$CMD" ] && exit 0

deny() {
  printf '{"decision":"block","reason":"%s"}' "$1"
  exit 2
}

# Normalize: collapse whitespace for matching
NORM="$(printf '%s' "$CMD" | tr -s '[:space:]' ' ')"

case "$NORM" in
  *"terraform destroy"*)
    deny "terraform destroy is blocked by stacks/terraform policy. If this is intentional and reviewed, run it manually outside the agent."
    ;;
  *"terraform apply"*" -auto-approve"*|*"terraform apply -auto-approve"*)
    deny "terraform apply -auto-approve is blocked. Plan, review the diff, then apply interactively."
    ;;
  *"terraform state rm"*|*"terraform state mv"*)
    deny "terraform state mutations are blocked. Hand-editing state is how outages happen."
    ;;
  *"terraform taint"*)
    deny "terraform taint is blocked. Prefer -replace on the next apply with explicit human review."
    ;;
  *"terraform force-unlock"*)
    deny "terraform force-unlock is blocked. Investigate why a lock is held before unlocking."
    ;;
  *"terraform workspace delete"*)
    deny "terraform workspace delete is blocked. State in that workspace may be irreplaceable."
    ;;
esac

exit 0
