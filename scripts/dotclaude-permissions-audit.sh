#!/usr/bin/env bash
# source: scripts/dotclaude-permissions-audit.sh
#
# Read-only audit of the project's .claude/settings.json against the
# dotclaude defaults and the eight-category threat model. Prints a
# structured findings report. Does NOT modify any files.
#
# Reads:
#   .claude/settings.json                          (project config)
#   $DOTCLAUDE_HOME/core/settings.partial.json     (universal defaults)
#   $DOTCLAUDE_HOME/stacks/<category>/<name>/settings.partial.json (overlays, when detected)
#
# Exit codes:
#   0  — no critical findings
#   1  — at least one CRITICAL finding (over-broad allow, missing deny)
#   2  — file errors (settings.json missing or malformed)
#
# Flags:
#   --diff      show full deep-diff against current dotclaude defaults
#   --strict    treat broad interpreter allows as findings (default: warn)
#   --unused    attempt to detect allow rules with no recorded use (heuristic)
#   --json      emit machine-readable JSON instead of the formatted report

set -euo pipefail

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SETTINGS_FILE="$REPO_ROOT/.claude/settings.json"
DOTCLAUDE_HOME="${DOTCLAUDE_HOME:-}"

DIFF_MODE=0
STRICT=0
UNUSED=0
JSON_MODE=0
for arg in "$@"; do
  case "$arg" in
    --diff)   DIFF_MODE=1 ;;
    --strict) STRICT=1 ;;
    --unused) UNUSED=1 ;;
    --json)   JSON_MODE=1 ;;
    --help|-h)
      grep '^#' "$0" | head -30 | sed 's/^# \{0,1\}//'
      exit 0
      ;;
  esac
done

# Pick a JSON parser (jq > python3 > python). Without one we can't audit
# meaningfully — bail cleanly with a clear message.
if command -v python3 >/dev/null 2>&1; then PY=python3
elif command -v python >/dev/null 2>&1; then PY=python
else
  echo "ERROR: dotclaude-permissions-audit needs python3 or python." >&2
  exit 2
fi

if [ ! -f "$SETTINGS_FILE" ]; then
  echo "=== dotclaude permissions audit ==="
  echo ""
  echo "[CRITICAL]   .claude/settings.json not found at $SETTINGS_FILE"
  echo "             run /dotclaude-init to generate the universal + stack defaults."
  echo ""
  echo "=== summary: 1 critical, 0 warning, 0 info ==="
  exit 1
fi

# Validate JSON before doing anything else.
if ! "$PY" -c "import json,sys; json.load(open(sys.argv[1]))" "$SETTINGS_FILE" 2>/dev/null; then
  echo "ERROR: $SETTINGS_FILE is not valid JSON. Fix and re-run." >&2
  exit 2
fi

# The core of the audit lives in inline python so we can use real JSON
# parsing and set algebra without bringing in another dependency.
"$PY" - "$SETTINGS_FILE" "$DOTCLAUDE_HOME" "$DIFF_MODE" "$STRICT" "$UNUSED" "$JSON_MODE" <<'PYEOF'
import json
import os
import re
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
dotclaude_home = sys.argv[2]
diff_mode = sys.argv[3] == "1"
strict = sys.argv[4] == "1"
unused = sys.argv[5] == "1"
json_mode = sys.argv[6] == "1"

with settings_path.open() as f:
    settings = json.load(f)

allow = set(settings.get("permissions", {}).get("allow", []))
deny = set(settings.get("permissions", {}).get("deny", []))
hooks = settings.get("hooks", {})

# ─── Threat-model deny coverage ────────────────────────────────────────────
# These are the must-have deny patterns. The audit checks whether any of
# the synonyms for each category is present (some users phrase rules
# slightly differently — we want one of the family to exist).
THREAT_MODEL = {
    "destroy: force push": [r"git push.*--force", r"git push.*-f"],
    "destroy: hard reset": [r"git reset --hard"],
    "destroy: rm -rf root/home": [r"rm -rf /", r"rm -rf ~", r"rm -rf \\$HOME"],
    "destroy: SQL DROP/DELETE/TRUNCATE": [r"DROP TABLE", r"TRUNCATE", r"DELETE FROM"],
    "destroy: filter-branch/filter-repo": [r"filter-branch", r"filter-repo"],
    "weaken-security: chmod 777": [r"chmod.*777"],
    "trust-boundary: curl|sh / wget|sh": [r"curl.*\| sh", r"curl.*\| bash", r"wget.*\| sh", r"wget.*\| bash"],
    "exfiltrate: cat ssh/aws creds": [r"cat ~/\.ssh", r"cat ~/\.aws", r"cat ~/\.kube"],
    "bypass-review: --no-verify": [r"--no-verify"],
    "bypass-review: package publish": [r"npm publish", r"twine upload", r"uv publish", r"poetry publish", r"hatch publish", r"cargo publish"],
    "persist: authorized_keys": [r"authorized_keys"],
    "persist: crontab edit": [r"crontab -e", r"crontab -r"],
    "persist: systemctl/launchctl": [r"systemctl enable", r"launchctl load"],
    "modify-own-permissions: write .claude/settings.json": [r"\.claude/settings(\.local)?\.json"],
}

def deny_covers(patterns):
    """Return True if any deny rule contains any of the given regex patterns."""
    for d in deny:
        for p in patterns:
            if re.search(p, d, re.IGNORECASE):
                return True
    return False

missing_categories = []
for category, patterns in THREAT_MODEL.items():
    if not deny_covers(patterns):
        missing_categories.append(category)

# ─── Over-broad allow detection ─────────────────────────────────────────────
# The most dangerous broad allows.
NUCLEAR_BROAD = [
    re.compile(r"^Bash\(\*\)$"),
    re.compile(r"^Bash\(\*:\*\)$"),
    re.compile(r"^Write\(\*\)$"),
    re.compile(r"^Edit\(\*\)$"),
]
# Borderline: bare interpreters with :* — flagged in --strict mode only.
INTERPRETER_BROAD = [
    re.compile(r"^Bash\(bash:\*\)$"),
    re.compile(r"^Bash\(sh:\*\)$"),
    re.compile(r"^Bash\(zsh:\*\)$"),
    re.compile(r"^Bash\(eval:\*\)$"),
    re.compile(r"^Bash\(rm:\*\)$"),
    re.compile(r"^Bash\(curl:\*\)$"),
    re.compile(r"^Bash\(wget:\*\)$"),
    re.compile(r"^Bash\(ssh:\*\)$"),
    re.compile(r"^Bash\(sudo:\*\)$"),
]

nuclear_findings = [a for a in allow for r in NUCLEAR_BROAD if r.match(a)]
interpreter_findings = [a for a in allow for r in INTERPRETER_BROAD if r.match(a)]

# ─── Hook registration vs file presence ────────────────────────────────────
pre_hooks = hooks.get("PreToolUse", [])
hook_paths = []
for entry in pre_hooks:
    for h in entry.get("hooks", []):
        if h.get("type") == "command":
            hook_paths.append(h.get("command", ""))

repo_root = settings_path.parent.parent
hook_warnings = []
for hp in hook_paths:
    abs_path = (repo_root / hp).resolve() if not os.path.isabs(hp) else Path(hp)
    if not abs_path.exists():
        hook_warnings.append(f"hook registered but file missing: {hp}")
    elif not os.access(abs_path, os.X_OK):
        hook_warnings.append(f"hook registered but not executable: {hp}  (fix: chmod +x {hp})")

# ─── Drift from dotclaude defaults (only if DOTCLAUDE_HOME set) ────────────
drift = {"allow_added": [], "allow_removed": [], "deny_added": [], "deny_removed": []}
core_allow = set()
core_deny = set()
if dotclaude_home:
    core_path = Path(dotclaude_home) / "core" / "settings.partial.json"
    if core_path.exists():
        try:
            with core_path.open() as f:
                core = json.load(f)
            core_allow = set(core.get("permissions", {}).get("allow", []))
            core_deny = set(core.get("permissions", {}).get("deny", []))
            drift["allow_added"] = sorted(allow - core_allow)
            drift["allow_removed"] = sorted(core_allow - allow)
            drift["deny_added"] = sorted(deny - core_deny)
            drift["deny_removed"] = sorted(core_deny - deny)
        except Exception as e:
            pass

# ─── Build findings ─────────────────────────────────────────────────────────
findings = {"critical": [], "warning": [], "info": [], "ok": []}

if nuclear_findings:
    findings["critical"].append({
        "kind": "over-broad-allow-nuclear",
        "rules": nuclear_findings,
        "fix": "remove these -- they defeat the entire permission model",
    })

if strict and interpreter_findings:
    findings["critical"].append({
        "kind": "over-broad-allow-interpreter",
        "rules": interpreter_findings,
        "fix": "narrow to specific subcommands (e.g. Bash(rm:*) → Bash(rm /tmp/*) or remove)",
    })
elif interpreter_findings:
    findings["warning"].append({
        "kind": "broad-interpreter-allow",
        "rules": interpreter_findings,
        "fix": "consider narrowing to specific subcommands; run with --strict to treat as critical",
    })

if missing_categories:
    findings["critical"].append({
        "kind": "missing-deny-rules-from-threat-model",
        "categories": missing_categories,
        "fix": "re-run /dotclaude-init to merge core defaults, OR copy the missing rule from core/settings.partial.json",
    })

for w in hook_warnings:
    findings["warning"].append({"kind": "hook-misconfigured", "detail": w})

if dotclaude_home and core_allow:
    if drift["allow_removed"]:
        findings["info"].append({
            "kind": "allows-missing-vs-core-default",
            "count": len(drift["allow_removed"]),
            "examples": drift["allow_removed"][:5],
            "fix": "consider /dotclaude-sync to pull universal allow updates",
        })
    if drift["deny_removed"]:
        findings["info"].append({
            "kind": "denies-missing-vs-core-default",
            "count": len(drift["deny_removed"]),
            "examples": drift["deny_removed"][:5],
            "fix": "consider /dotclaude-sync -- these are universal safety rules",
        })

if not findings["critical"] and not findings["warning"]:
    findings["ok"].append("threat-model coverage is complete")
    findings["ok"].append(f"{len(allow)} allow rules, {len(deny)} deny rules in effect")

# ─── Render ─────────────────────────────────────────────────────────────────
if json_mode:
    print(json.dumps({
        "settings_file": str(settings_path),
        "summary": {
            "critical": len(findings["critical"]),
            "warning": len(findings["warning"]),
            "info":    len(findings["info"]),
            "ok":      len(findings["ok"]),
        },
        "findings": findings,
        "drift": drift if dotclaude_home else None,
    }, indent=2))
else:
    print("=== dotclaude permissions audit ===")
    print()
    print(f"settings: {settings_path}")
    print(f"allow rules: {len(allow)}    deny rules: {len(deny)}    hooks registered: {len(hook_paths)}")
    print()
    if findings["critical"]:
        for f in findings["critical"]:
            print(f"[CRITICAL]   {f['kind']}")
            for k, v in f.items():
                if k == "kind": continue
                if isinstance(v, list):
                    for item in v: print(f"             - {item}")
                else:
                    print(f"             {k}: {v}")
            print()
    if findings["warning"]:
        for f in findings["warning"]:
            print(f"[WARNING]    {f['kind']}")
            for k, v in f.items():
                if k == "kind": continue
                if isinstance(v, list):
                    for item in v: print(f"             - {item}")
                else:
                    print(f"             {k}: {v}")
            print()
    if findings["info"]:
        for f in findings["info"]:
            print(f"[INFO]       {f['kind']}")
            for k, v in f.items():
                if k == "kind": continue
                if isinstance(v, list):
                    for item in v: print(f"             - {item}")
                else:
                    print(f"             {k}: {v}")
            print()
    if findings["ok"]:
        for msg in findings["ok"]:
            print(f"[OK]         {msg}")
        print()

    if diff_mode and dotclaude_home and core_allow:
        print("=== drift detail ===")
        for kind in ("allow_added", "allow_removed", "deny_added", "deny_removed"):
            items = drift[kind]
            print(f"\n{kind} ({len(items)}):")
            for it in items:
                print(f"  {it}")
        print()

    n_c = len(findings["critical"])
    n_w = len(findings["warning"])
    n_i = len(findings["info"])
    print(f"=== summary: {n_c} critical, {n_w} warning, {n_i} info ===")

sys.exit(1 if findings["critical"] else 0)
PYEOF
