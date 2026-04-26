# Windows and OneDrive Locks

This checkout is under `OneDrive\Desktop`, and directory operations can fail
with `Access is denied` when OneDrive, Explorer, or Windows ACLs hold the tree.

In this session, directory moves under `stacks/` failed because the sandbox user
only had `ReadAndExecute` on existing directories. That is why P1.2 could not
complete even though file edits were possible.

## Fast Fixes to Try

1. Pause OneDrive sync:
   - Click the OneDrive cloud tray icon.
   - Choose the gear icon.
   - Choose **Pause syncing** for 2 hours.

2. Quit OneDrive completely:
   - OneDrive tray icon -> gear -> **Quit OneDrive**.
   - Retry the move.
   - Start OneDrive again afterward from the Start menu.

3. Close Explorer windows open inside this repo.

4. Check Windows Security:
   - Open **Windows Security**.
   - Go to **Virus & threat protection** -> **Ransomware protection**.
   - If **Controlled folder access** is on, allow your terminal/editor or move
     the repo out of protected folders.

5. Move the repo out of OneDrive for structural refactors:

```powershell
New-Item -ItemType Directory -Force -Path C:\code | Out-Null
robocopy "$env:USERPROFILE\OneDrive\Desktop\MP\CODE\dotclaude" C:\code\dotclaude /MIR /XD .git
```

Prefer a fresh clone at `C:\code\dotclaude` if you do not need OneDrive backup
for the working tree.

## ACL Fix

If the issue is ACL ownership, run PowerShell as your normal Windows user:

```powershell
icacls "$env:USERPROFILE\OneDrive\Desktop\MP\CODE\dotclaude" /grant "$($env:USERNAME):(OI)(CI)F" /T
```

Then restart the terminal/agent session and retry the stack reorg.

## P1.2 Intended Move

Once unlocked, move stacks into category folders while keeping `source:` tags
stable:

```text
stacks/lang/       python, node-ts, go, rust, dotnet
stacks/frontend/   react, nextjs, angular, svelte, htmx-alpine, reflex
stacks/backend/    fastapi
stacks/infra/      aws, docker, github-actions, kubernetes, terraform, cloudflare-workers
stacks/ml/         pytorch, vllm-ollama
stacks/desktop/    tauri
```

Keep target-project source tags as `source: stacks/<name>` so existing sync
state remains compatible.
