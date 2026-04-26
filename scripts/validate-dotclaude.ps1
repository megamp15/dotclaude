param(
  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
  param([string]$Message)
  $script:failures.Add($Message) | Out-Null
}

function Get-Frontmatter {
  param([string]$Path)
  $lines = Get-Content -LiteralPath $Path
  if ($lines.Count -lt 3 -or $lines[0] -ne "---") {
    return $null
  }

  $end = -1
  for ($i = 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -eq "---") {
      $end = $i
      break
    }
  }
  if ($end -lt 0) {
    return $null
  }

  $map = @{}
  for ($i = 1; $i -lt $end; $i++) {
    if ($lines[$i] -match "^([^:#]+):\s*(.*)$") {
      $map[$Matches[1].Trim()] = $Matches[2].Trim()
    }
  }
  return $map
}

Write-Host "dotclaude validation root: $Root"

# JSON validation.
$jsonFiles = Get-ChildItem -LiteralPath $Root -Recurse -File |
  Where-Object {
    $_.Name -eq "settings.partial.json" -or
    $_.Name -like "*.mcp.json" -or
    $_.FullName -like "*.github*workflows*.json"
  }

foreach ($file in $jsonFiles) {
  try {
    Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json | Out-Null
  } catch {
    Add-Failure "Invalid JSON: $($file.FullName): $($_.Exception.Message)"
  }
}

# Core settings smoke checks.
$coreSettingsPath = Join-Path $Root "core/settings.partial.json"
if (Test-Path -LiteralPath $coreSettingsPath) {
  $coreSettings = Get-Content -LiteralPath $coreSettingsPath -Raw | ConvertFrom-Json
  if (-not $coreSettings.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS) {
    Add-Failure "core/settings.partial.json missing CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS env wiring"
  }

  if ($coreSettings.hooks) {
    foreach ($event in $coreSettings.hooks.PSObject.Properties) {
      foreach ($entry in @($event.Value)) {
        foreach ($hook in @($entry.hooks)) {
          $command = [string]$hook.command
          if ($command -like ".claude/hooks/*") {
            $hookName = Split-Path $command -Leaf
            $sourceHook = Join-Path $Root "core/hooks/$hookName"
            if (-not (Test-Path -LiteralPath $sourceHook)) {
              Add-Failure "Registered hook missing source file: $command"
            }
          }
        }
      }
    }
  }
}

# Skill frontmatter validation.
$skillFiles = Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "SKILL.md"
foreach ($file in $skillFiles) {
  $fm = Get-Frontmatter $file.FullName
  if ($null -eq $fm) {
    Add-Failure "Missing frontmatter: $($file.FullName)"
    continue
  }
  foreach ($field in @("name", "description")) {
    if (-not $fm.ContainsKey($field) -or [string]::IsNullOrWhiteSpace($fm[$field])) {
      Add-Failure "Missing '$field' in frontmatter: $($file.FullName)"
    }
  }

  $relative = Resolve-Path -LiteralPath $file.FullName -Relative
  if ($relative -match "^\.(\\|/)core(\\|/)skills(\\|/)" -or
      $relative -match "^\.(\\|/)core(\\|/)mcp(\\|/)skills(\\|/)" -or
      $relative -match "^\.(\\|/)stacks(\\|/)") {
    if (-not $fm.ContainsKey("source") -or [string]::IsNullOrWhiteSpace($fm["source"])) {
      Add-Failure "Missing 'source' in source-managed skill: $($file.FullName)"
    }
  }
}

# Stack skill shape validation: stacks/<stack>/skills/<name>.md is not
# discoverable by Claude Code. Use stacks/<stack>/skills/<name>/SKILL.md.
$flatStackSkills = Get-ChildItem -LiteralPath (Join-Path $Root "stacks") -Recurse -File -Filter "*.md" |
  Where-Object { $_.FullName -match "[\\/]skills[\\/][^\\/]+\.md$" }

foreach ($file in $flatStackSkills) {
  Add-Failure "Flat stack skill should be folder form: $($file.FullName)"
}

# Stack layout validation: physical stack folders live one level below a
# category, but source tags remain source: stacks/<name>.
$allowedStackCategories = @("backend", "desktop", "frontend", "infra", "lang", "ml")
$stacksRoot = Join-Path $Root "stacks"
if (Test-Path -LiteralPath $stacksRoot) {
  $topLevelStackDirs = Get-ChildItem -LiteralPath $stacksRoot -Directory
  foreach ($dir in $topLevelStackDirs) {
    if ($allowedStackCategories -notcontains $dir.Name) {
      Add-Failure "Top-level stack directory should be under a category: $($dir.FullName)"
    }
  }

  foreach ($category in $allowedStackCategories) {
    $categoryPath = Join-Path $stacksRoot $category
    if (-not (Test-Path -LiteralPath $categoryPath)) {
      Add-Failure "Missing stack category directory: $category"
      continue
    }
    foreach ($stack in Get-ChildItem -LiteralPath $categoryPath -Directory) {
      $claude = Join-Path $stack.FullName "CLAUDE.stack.md"
      $settings = Join-Path $stack.FullName "settings.partial.json"
      if (-not (Test-Path -LiteralPath $claude)) {
        Add-Failure "Stack missing CLAUDE.stack.md: $($stack.FullName)"
      }
      if (-not (Test-Path -LiteralPath $settings)) {
        Add-Failure "Stack missing settings.partial.json: $($stack.FullName)"
      }
    }
  }
}

# Command smoke checks for framework commands. A command may map to a same-name
# framework skill, a core skill that gets copied into .claude/skills, or a
# script.
$commands = Get-ChildItem -LiteralPath (Join-Path $Root "commands") -File -Filter "*.md" -ErrorAction SilentlyContinue
foreach ($command in $commands) {
  $name = [System.IO.Path]::GetFileNameWithoutExtension($command.Name)
  $sameNameTargets = @(
    (Join-Path $Root "skills/$name/SKILL.md"),
    (Join-Path $Root "core/skills/$name/SKILL.md"),
    (Join-Path $Root "scripts/$name.sh"),
    (Join-Path $Root "scripts/$name.ps1")
  )
  $hasTarget = $false
  foreach ($target in $sameNameTargets) {
    if (Test-Path -LiteralPath $target) {
      $hasTarget = $true
    }
  }

  $body = Get-Content -LiteralPath $command.FullName -Raw
  $matches = [regex]::Matches($body, "\.claude/skills/([^/\\]+)/SKILL\.md")
  foreach ($match in $matches) {
    $skillName = $match.Groups[1].Value
    $referencedTargets = @(
      (Join-Path $Root "skills/$skillName/SKILL.md"),
      (Join-Path $Root "core/skills/$skillName/SKILL.md")
    )
    foreach ($target in $referencedTargets) {
      if (Test-Path -LiteralPath $target) {
        $hasTarget = $true
      }
    }
  }

  if ($name -like "dotclaude-*" -and -not $hasTarget) {
    Add-Failure "Command has no matching skill or script target: $($command.FullName)"
  }
}

if ($failures.Count -gt 0) {
  Write-Host ""
  Write-Host "Validation failed:" -ForegroundColor Red
  foreach ($failure in $failures) {
    Write-Host " - $failure" -ForegroundColor Red
  }
  exit 1
}

Write-Host "Validation passed: $($skillFiles.Count) skills and $($jsonFiles.Count) JSON files checked."
