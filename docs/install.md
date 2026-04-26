# Install

One-time, per machine.

## Linux / macOS

```bash
git clone https://github.com/<you>/dotclaude ~/code/dotclaude
export DOTCLAUDE_HOME=~/code/dotclaude

mkdir -p ~/.claude/skills ~/.claude/commands

for skill in "$DOTCLAUDE_HOME"/skills/*/; do
  ln -sfn "$skill" "$HOME/.claude/skills/$(basename "$skill")"
done

for cmd in "$DOTCLAUDE_HOME"/commands/*.md; do
  ln -sfn "$cmd" "$HOME/.claude/commands/$(basename "$cmd")"
done
```

Add `DOTCLAUDE_HOME` to your shell init file.

## Windows PowerShell

```powershell
git clone https://github.com/<you>/dotclaude "$env:USERPROFILE\code\dotclaude"
setx DOTCLAUDE_HOME "$env:USERPROFILE\code\dotclaude"
$env:DOTCLAUDE_HOME = "$env:USERPROFILE\code\dotclaude"

New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude\skills"   | Out-Null
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude\commands" | Out-Null

Get-ChildItem -Path "$env:DOTCLAUDE_HOME\skills" -Directory | ForEach-Object {
    $link = Join-Path "$env:USERPROFILE\.claude\skills" $_.Name
    if (Test-Path $link) { Remove-Item $link -Force -Recurse }
    New-Item -ItemType Junction -Path $link -Target $_.FullName | Out-Null
}

Get-ChildItem -Path "$env:DOTCLAUDE_HOME\commands" -Filter *.md | ForEach-Object {
    $link = Join-Path "$env:USERPROFILE\.claude\commands" $_.Name
    if (Test-Path $link) { Remove-Item $link -Force }
    cmd /c mklink /H "`"$link`"" "`"$($_.FullName)`"" | Out-Null
}
```

Restart any running Claude Code session after installing. Skills and commands
are discovered at session start.

## What Gets Installed

Framework skills:

- `dotclaude-init`
- `dotclaude-sync`
- `dotclaude-init-cursor`
- `dotclaude-init-copilot`
- `dotclaude-init-opencode`
- `dotclaude-init-agents-md`
- `dotclaude-doctor`

Framework slash commands mirror those skills and add operational commands such
as `/dotclaude-resume`, `/dotclaude-learn`, `/dotclaude-parallel`, and
`/dotclaude-permissions-audit`.

