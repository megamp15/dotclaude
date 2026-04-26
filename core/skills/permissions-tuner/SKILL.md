---
name: permissions-tuner
description: Reduce approval-prompt friction safely. Configure Claude Code's auto-mode (and dotclaude's broader permissions package) so the agent runs read-only / safe-by-intent commands without asking, blocks the destruction/exfiltration/escalation set without thinking, and only escalates to a human prompt when something genuinely matters. Covers the four-layer model (allow rules → deny rules → static safety hook → user-specific overrides), the auto-mode walkthrough, and the audit workflow.
source: core
triggers: /permissions, permissions, auto-mode, auto mode, claude code auto mode, reduce prompts, stop asking, allowlist, denylist, settings.json, allow rules, deny rules, permission tuning, fewer approvals, can the agent stop asking, why is it asking
---

# permissions-tuner

The default Claude Code (and most agents) ask before running almost
anything. Useful at first; exhausting at scale. dotclaude's permissions
package and Claude Code's [auto-mode](https://www.anthropic.com/engineering/claude-code-auto-mode)
work together to cut the prompt count by 80–95% on routine work
**without** widening the blast radius of the dangerous 5%.

This skill is the one-stop guide for tuning that balance.

## The four-layer model

dotclaude treats permissions as defense-in-depth, not a single allowlist:

| Layer | Lives in | Catches | Failure mode if it misfires |
|---|---|---|---|
| **1. Allow rules** | `.claude/settings.json#permissions.allow` | Read-only / safe-by-intent commands → no prompt | Too narrow → many prompts; too broad → see layer 3 |
| **2. Deny rules** | `.claude/settings.json#permissions.deny` | Always-bad patterns → instant block | Too broad → blocks legit work; too narrow → see layer 3 |
| **3. Static safety hook** | `core/hooks/block-dangerous-commands.sh` | Wrapped or escaped destructive commands the static rules can't pattern-match | False positive → user can override per-command |
| **4. User-specific overrides** | `.claude/settings.local.json` (gitignored) | Project-specific allows ("yes I really do want `bun publish` here") | None — local-only, doesn't ship in repo |

Layers 1 and 2 are **declarative** (JSON, deep-merged from
`core` + `stacks/<lang>` + project). Layer 3 is **runtime** (bash hook
on PreToolUse). Layer 4 is **per-developer**, never committed.

## Two questions to ask before tuning

1. **"Is the agent asking too often?"** → Loosen layer 1 (add specific
   allows) or enable Claude Code's auto-mode (see below).
2. **"Did the agent do something I didn't expect?"** → Tighten layer 2 or
   3. Run `/dotclaude-permissions-audit` first; it usually points at the
   over-broad allow rule that let the surprise through.

Don't tune in the abstract. Tune in response to friction or surprise.

## Quick wins (do these first)

Before reaching for auto-mode, dotclaude's defaults already cover ~85%
of common safe commands. If you haven't yet:

1. **Run `/dotclaude-init`** in the project. It deep-merges
   `core/settings.partial.json` + the stack overlays into
   `.claude/settings.json`. That alone removes most prompts for
   `git status`, `ls`, `pytest`, `pnpm install`, `terraform plan`, etc.
2. **Run `/dotclaude-permissions-audit`** to see what's actually
   in `.claude/settings.json` vs what dotclaude recommends. Reports
   over-broad rules, missing deny patterns from the auto-mode threat
   model, and unused allow rules you can prune.

If you still have too many prompts after these two, move on to
Claude Code auto-mode.

## Claude Code auto-mode

Auto-mode (Anthropic, 2025) is Claude Code's built-in permission
*classifier* — separate from but complementary to dotclaude's static
allow/deny rules. It uses a fast model to bucket each tool invocation
into one of three risk tiers and only escalates the high-risk ones.

dotclaude does **not** replace this classifier — it can't, the
classifier is internal. dotclaude *composes* with it by:

- Pre-allowing the obvious safe set in `permissions.allow` so the
  classifier never sees them (classifier latency saved on every call).
- Pre-denying the obvious unsafe set in `permissions.deny` and via
  `block-dangerous-commands.sh` so the classifier *can't* misclassify
  a destructive command as safe.

**Setup** — see `references/auto-mode-setup.md` for the full
walkthrough including the exact CLI flag, when each setting matters,
and how the classifier interacts with dotclaude's static rules.

## The threat model dotclaude defends against

`references/threat-model.md` documents the eight categories
`block-dangerous-commands.sh` enforces, with one example per:

1. **Destroy data** — `git reset --hard`, `rm -rf /`, SQL `DROP`
2. **Destroy infra** — `terraform destroy`, `docker system prune -a`, `kubectl delete --all`
3. **Exfiltrate secrets** — `cat ~/.aws/credentials | curl …`
4. **Cross trust boundary** — `curl … | sh`, `eval $(curl …)`
5. **Bypass review** — `git --no-verify`, `npm publish`, `twine upload`
6. **Persist access** — `crontab -e`, write to `~/.ssh/authorized_keys`
7. **Disable logging** — `unset HISTFILE`, `history -c`
8. **Modify own permissions** — write to `.claude/settings.json`

If you find a category we're missing, add it to the hook and the
threat-model reference together.

## Tuning loop

```
[friction or surprise]
   │
   ├── friction (too many prompts)
   │     │
   │     ├── /dotclaude-permissions-audit          ← see what's already configured
   │     ├── add specific allow rule to .claude/settings.local.json
   │     │   (gitignored — your machine, your call)
   │     └── if pattern is universal: PR it to core/ or stacks/<lang>/
   │
   └── surprise (agent did something unwanted)
         │
         ├── /dotclaude-permissions-audit          ← which rule allowed this?
         ├── tighten the over-broad allow OR
         ├── add a targeted deny rule OR
         └── add a hook rule for patterns the static rules can't catch
```

The audit command is the centerpiece — it's read-only and tells you
what would change if you applied the dotclaude defaults today.

## Stack-specific tuning notes

Each stack overlay (`stacks/<lang>/settings.partial.json`) ships its
own balance. The headline trade-offs:

| Stack | Allow philosophy | Notable denies |
|---|---|---|
| **python** | uv-first, pip/pipx allowed for inspect, broad `python:*` for run | `pip install --break-system-packages`, `twine upload`, `uv publish` |
| **node-ts** | Broad `npm:*`/`pnpm:*` (subcommands mostly safe) | `*publish*`, `*--force*`, `npm config set`, `*login*` |
| **docker** | All `compose` ops + read-only inspect | `system prune -a`, `compose down -v`, `--privileged`, `docker push`, `--net=host`, mounting `/` or `docker.sock` |
| **terraform** | `fmt`/`validate`/`init`/`plan`/`show` + state list | `apply`, `destroy`, `state rm/mv/push`, `taint`, `force-unlock`, `import` |
| **github-actions** | All `gh` read + PR/issue mutation (daily-use surface) | `repo delete`, `secret set/delete`, `release create/delete`, `gh api -X POST/DELETE/PUT/PATCH` |

If your team's trust model is stricter (e.g., you don't want broad
`Bash(npm:*)`), narrow it in your project-level
`.claude/settings.json` — the deep-merge keeps the deny set intact
when you tighten an allow.

## When to add to local-only settings vs the repo

| Add to | When |
|---|---|
| `.claude/settings.json` (committed) | The rule is correct **for everyone on this project**. E.g., "always allow `make test`." |
| `.claude/settings.local.json` (gitignored) | The rule is **your habit**. E.g., you use `vim` heavily and want `Bash(vim:*)` allowed. |
| `core/` (PR to dotclaude) | The rule applies to **every project everywhere**. E.g., "`tree` is read-only safe." |
| `stacks/<lang>/` (PR to dotclaude) | The rule applies to **every project using that stack**. E.g., "`hadolint` is safe." |

Don't put project-specific business rules into `core/`. Don't put
universal rules into a single project's `.claude/`. The split scales.

## Common mistakes

- **`Bash(*)` in allow.** Defeats the entire model. Never do this.
  If you need to, you don't want dotclaude — you want raw shell access.
- **Allow without checking deny coverage.** Adding `Bash(git:*)` allows
  `git push --force` unless deny catches it. Always pair broad allows
  with specific denies.
- **Editing `.claude/settings.json` from the agent.** Blocked by both
  the deny rules and the hook. If the agent thinks it needs to, it's a
  signal the user wants an allow added — it should propose the change,
  not make it.
- **Treating allow as approval.** Allow means "no prompt"; it doesn't
  mean "good idea." The agent still owes the user judgment about
  whether the command is the right one. Most read-only commands are
  trivially worth running; mutating ones still deserve thought even if
  pre-allowed.
- **Forgetting the hook is the safety net.** If you're considering a
  broad allow because "the hook will catch the dangerous version" — the
  hook *is* the design. That's correct usage, not a workaround.

## Reference

- `references/auto-mode-setup.md` — Claude Code auto-mode setup
  walkthrough, with the dotclaude integration notes.
- `references/threat-model.md` — full eight-category threat model with
  examples and the corresponding hook/deny rule.
- `references/audit-workflow.md` — how to read `/dotclaude-permissions-audit`
  output and act on it.

## See also

- `core/settings.partial.json` — universal allow/deny set.
- `core/hooks/block-dangerous-commands.sh` — the runtime safety net.
- `stacks/<lang>/settings.partial.json` — stack overlays.
- `commands/dotclaude-permissions-audit.md` — the `/dotclaude-permissions-audit`
  slash command.
