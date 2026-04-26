# dotclaude permissions threat model

This is the explicit list of what the deny rules and the
`block-dangerous-commands.sh` hook defend against. If you find a
category we're missing, add it both to the hook and to this list.

The categories are derived from Claude Code's auto-mode design notes
plus observed agent failure modes. They're prioritized roughly by
"how bad if it happens" × "how easy for an agent to do it accidentally."

## 1. Destroy data

Anything that loses uncommitted work, removes files, or deletes rows.

| Pattern | Where defended |
|---|---|
| `git reset --hard` | core deny + hook |
| `git clean -fdx` | core deny + hook |
| `rm -rf /`, `rm -rf ~`, `rm -rf .`, `rm -rf .git`, `rm -rf .claude` | core deny + hook |
| SQL `DROP TABLE/DATABASE/SCHEMA` | hook (in any Bash command body) |
| SQL `DELETE FROM table;` (no WHERE) | hook |
| SQL `TRUNCATE TABLE` | hook |
| `git branch -D` on protected branch | core deny + hook |
| `git push --delete` on protected branch | core deny + hook |
| `git filter-branch`, `git filter-repo` (rewrites history) | core deny |

**Why these are special.** Recovery from data loss is asymmetric — the
agent took a second to type the command; you have hours of recovery
work. Rules in this category are **never** loosened by stack overlays.

## 2. Destroy infrastructure

Like data destruction but for cloud / container / cluster resources.

| Pattern | Where defended |
|---|---|
| `terraform destroy` | stack deny (terraform) + hook |
| `terraform apply -auto-approve` | stack deny + hook + dedicated `block-destroy-apply.sh` |
| `terraform state rm/mv/push/replace-provider` | stack deny |
| `terraform taint`, `untaint`, `import` | stack deny |
| `terraform force-unlock` | stack deny |
| `docker system prune -a`, `docker volume prune` | stack deny + hook |
| `docker compose down -v` | stack deny + hook |
| `kubectl delete namespace`, `kubectl delete --all` | hook |
| `aws s3 rm --recursive`, `aws s3 rb --force` | hook |
| `docker push`, `docker login`, `docker logout` | stack deny |

**Why these are special.** Cloud destruction is multi-tenant blast
radius. `aws s3 rm --recursive` doesn't just delete *your* objects —
it can take downstream consumers with it. Cluster-level
`kubectl delete` does the same on Kubernetes.

## 3. Exfiltrate secrets

Reading credentials and shipping them somewhere external.

| Pattern | Where defended |
|---|---|
| `cat ~/.ssh/id_*`, `cat ~/.aws/credentials`, etc. | core deny |
| `cat <secret-file> | curl …` (read + pipe to network) | hook |
| `curl --upload-file ~/.ssh`, `curl -d @~/.aws` | hook |
| `scp ~/.ssh/`, `scp ~/.aws/`, `scp ~/.kube/` | hook |
| `env | curl …`, `printenv | nc …` | hook |
| `gh gist create` (with file content) | core deny |

**What we *can't* defend against.** A determined exfiltration could:
- `cp ~/.aws/credentials /tmp/x; curl … -d @/tmp/x` (decoupled)
- `python -c 'import os; ...'` reading env and posting it (in any language)
- A multi-step plan that hides intent across tool calls

These require either prompt-engineering defenses (system prompt rules)
or external monitoring. The static rules + hook catch the obvious
single-command versions; deeper defense needs more than file rules.

## 4. Cross trust boundary

Executing untrusted remote content as code.

| Pattern | Where defended |
|---|---|
| `curl … | sh`, `wget … | bash`, etc. | core deny + hook |
| `eval $(curl …)`, `eval "$(wget …)"` | hook |
| PowerShell `IEX (iwr …)`, `Invoke-Expression (Invoke-WebRequest …)` | hook |
| `bash <(curl …)`, `bash <(wget …)` | (TODO: add to hook) |

**Why these are special.** They're the textbook supply-chain attack:
the agent thinks it's running an installer, but the installer's source
is whatever an attacker served at that URL today. Every trustworthy
project ships installer scripts you can `cat` first; the few that
don't aren't worth the risk.

## 5. Bypass review

Pushing changes without the safety net of code review or test gates.

| Pattern | Where defended |
|---|---|
| `git --no-verify` (skip pre-commit/pre-push hooks) | core deny + hook |
| `git push --force` to protected branches | core deny + hook |
| `npm/pnpm/yarn/bun publish` | stack deny + hook |
| `twine upload`, `python -m twine upload` | stack deny + hook |
| `uv publish`, `poetry publish`, `hatch publish` | stack deny + hook |
| `cargo publish`, `gem push` | hook |
| `gh release create` (irreversible release) | stack deny |

**Why these are special.** They take an action the team can't easily
unwind: published packages can be unpublished but consumers may
already have pulled them; force-pushed history is gone for everyone
who hasn't fetched yet; --no-verify-bypassed hooks would have caught
the bug the hooks exist for.

## 6. Persist access

Establishing footholds that survive the current session.

| Pattern | Where defended |
|---|---|
| `>> ~/.ssh/authorized_keys`, `> ~/.ssh/authorized_keys` | core deny + hook |
| `crontab -e`, `crontab -r`, `crontab <` | core deny + hook |
| `systemctl enable/disable/mask` | core deny + hook |
| `launchctl load/unload/bootstrap/bootout` (macOS) | core deny + hook |
| Writes to `~/.bashrc`, `~/.zshrc`, etc. (via `>` or `tee`) | hook |

**Why these are special.** Almost no legitimate development task
requires modifying authorized_keys, crontab, or systemd. If the agent
thinks it does, the user should explicitly do it themselves.

## 7. Disable logging

Anti-forensic patterns that erase the trail.

| Pattern | Where defended |
|---|---|
| `unset HISTFILE`, `export HISTFILE=/dev/null` | core deny + hook |
| `set +o history` | core deny + hook |
| `history -c` | core deny + hook |
| `rm ~/.bash_history`, `truncate ~/.zsh_history` | hook |

**Why these are special.** No agentic task should ever erase shell
history. If the agent does this, something is wrong (prompt injection,
misaligned instructions, etc.).

## 8. Modify own permissions

The agent shouldn't be able to widen its own allow list.

| Pattern | Where defended |
|---|---|
| `Write` / `Edit` to `.claude/settings.json` | core deny |
| `Write` / `Edit` to `.claude/settings.local.json` | core deny |
| `Write` / `Edit` to `~/.claude/settings.json` | core deny |
| Shell-level `> .claude/settings.json`, `tee`, `sed -i` | hook |

**Why these are special.** If the agent could modify its own
permissions, all other defenses become meaningless. The agent must
*propose* permission changes to the user; the user makes the change.

## What this model does NOT cover

Honest limitations:

- **Multi-step exfiltration** that decouples the read and the send.
- **Application-level damage** that uses an allowed tool harmfully
  (e.g., a Python script the agent writes that drops the database).
- **Network egress at the application layer** (apps making HTTPS calls
  outside the hook scope).
- **Container-internal damage** (commands run inside a `docker exec`
  bypass the host hook entirely).
- **Prompt injection** via files the agent reads. The agent might be
  told to run dangerous commands by content in a `README` or comment;
  the hooks catch the dangerous *commands* but not the *intent*.

For those, you need additional layers: container sandboxing, network
egress controls, or prompt-injection mitigations at the system-prompt
layer. dotclaude doesn't replace those.
