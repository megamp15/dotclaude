#!/usr/bin/env bash
# source: scripts/dotclaude-doctor.sh

set -u

failures=()
warnings=()
healthy=()

add_failure() { failures+=("$1"); }
add_warning() { warnings+=("$1"); }
add_healthy() { healthy+=("$1"); }

if [ -n "${DOTCLAUDE_HOME:-}" ]; then
  ROOT="$DOTCLAUDE_HOME"
else
  ROOT="$(pwd)"
fi

if [ ! -d "$ROOT/core" ] || [ ! -d "$ROOT/skills" ] || [ ! -d "$ROOT/stacks" ]; then
  add_failure "Cannot locate dotclaude root. Set DOTCLAUDE_HOME or run from the dotclaude checkout."
else
  add_healthy "Located dotclaude root: $ROOT"
fi

check_json() {
  file="$1"
  if command -v python >/dev/null 2>&1; then
    python -m json.tool "$file" >/dev/null 2>&1 || add_failure "Invalid JSON: $file"
  elif command -v jq >/dev/null 2>&1; then
    jq empty "$file" >/dev/null 2>&1 || add_failure "Invalid JSON: $file"
  else
    add_warning "Cannot parse JSON without python or jq: $file"
  fi
}

if [ -d "$ROOT" ]; then
  while IFS= read -r -d '' file; do
    check_json "$file"
  done < <(find "$ROOT" \( -name 'settings.partial.json' -o -name '*.mcp.json' \) -type f -print0 2>/dev/null)

  flat_count="$(find "$ROOT/stacks" -path '*/skills/*.md' -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$flat_count" != "0" ]; then
    add_failure "Found $flat_count flat stack skill file(s); use skills/<name>/SKILL.md."
  else
    add_healthy "No flat stack skill files found."
  fi

  missing_frontmatter=0
  missing_source=0
  while IFS= read -r -d '' skill; do
    if ! head -n 1 "$skill" | grep -qx -- '---'; then
      missing_frontmatter=$((missing_frontmatter + 1))
      continue
    fi
    grep -q '^name:' "$skill" || missing_frontmatter=$((missing_frontmatter + 1))
    grep -q '^description:' "$skill" || missing_frontmatter=$((missing_frontmatter + 1))
    case "$skill" in
      "$ROOT/core/skills/"*|"$ROOT/core/mcp/skills/"*|"$ROOT/stacks/"*)
        grep -q '^source:' "$skill" || missing_source=$((missing_source + 1))
        ;;
    esac
  done < <(find "$ROOT" -name SKILL.md -type f -print0 2>/dev/null)

  [ "$missing_frontmatter" -eq 0 ] && add_healthy "All SKILL.md files have name/description frontmatter." || add_failure "$missing_frontmatter skill file(s) missing required frontmatter."
  [ "$missing_source" -eq 0 ] && add_healthy "Source-managed skills have source tags." || add_failure "$missing_source source-managed skill file(s) missing source tags."

  for hook in block-dangerous-commands.sh protect-files.sh scan-secrets.sh warn-large-files.sh format-on-save.sh auto-test.sh session-start.sh context-recovery.sh conductor-brief.sh notify.sh agent-team-idle.sh agent-team-task-completed.sh; do
    [ -f "$ROOT/core/hooks/$hook" ] || add_failure "Missing core hook: $hook"
  done
fi

if [ -f "$HOME/.claude/skills/dotclaude-init/SKILL.md" ]; then
  add_healthy "Framework skills are visible under ~/.claude/skills."
else
  add_warning "dotclaude-init not found under ~/.claude/skills; links may not be installed for Claude Code."
fi

echo "dotclaude doctor"
if [ "${#failures[@]}" -gt 0 ]; then
  echo "Status: fail"
elif [ "${#warnings[@]}" -gt 0 ]; then
  echo "Status: warn"
else
  echo "Status: pass"
fi

echo
echo "Failures:"
if [ "${#failures[@]}" -eq 0 ]; then
  echo "- none"
else
  printf -- '- %s\n' "${failures[@]}"
fi

echo
echo "Warnings:"
if [ "${#warnings[@]}" -eq 0 ]; then
  echo "- none"
else
  printf -- '- %s\n' "${warnings[@]}"
fi

echo
echo "Healthy:"
if [ "${#healthy[@]}" -eq 0 ]; then
  echo "- none"
else
  printf -- '- %s\n' "${healthy[@]}"
fi

[ "${#failures[@]}" -eq 0 ]

