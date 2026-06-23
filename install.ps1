#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# SuperStack installer (Windows / PowerShell). Installs the /ss-* skills (and agents, for
# Claude Code) into one or more coding-agent homes.
#
#   ./install.ps1                # Claude Code (default)
#   ./install.ps1 -Agent codex   # claude|codex|cursor|opencode|factory|kiro
#   ./install.ps1 -All           # every detected agent
#
# Override the install root with $env:SUPERSTACK_INSTALL_HOME (used for testing).
param([string]$Agent = "claude", [switch]$All)
$ErrorActionPreference = 'Stop'

$Src  = $PSScriptRoot
$Base = if ($env:SUPERSTACK_INSTALL_HOME) { $env:SUPERSTACK_INSTALL_HOME } else { $HOME }

$SkillsRel = @{
  claude   = '.claude/skills';   codex   = '.codex/skills';   cursor = '.cursor/skills'
  opencode = '.config/opencode/skills'; factory = '.factory/skills'; kiro = '.kiro/skills'
}
$HostHome = @{
  claude = '.claude'; codex = '.codex'; cursor = '.cursor'
  opencode = '.config/opencode'; factory = '.factory'; kiro = '.kiro'
}

function Install-AgentHost([string]$h) {
  if (-not $SkillsRel.ContainsKey($h)) { Write-Host "  unknown host: $h (skipped)"; return }
  $dir = Join-Path $Base $SkillsRel[$h]
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $n = 0
  Get-ChildItem -Directory (Join-Path $Src 'skills') | ForEach-Object {
    if (Test-Path (Join-Path $_.FullName 'SKILL.md')) {
      $dest = Join-Path $dir ("ss-" + $_.Name)
      if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
      Copy-Item -Recurse $_.FullName $dest
      $n++
    }
  }
  Write-Host ("  {0}: {1} skills -> {2}" -f $h, $n, $dir)
  if ($h -eq 'claude') {
    $agents = Join-Path $Base '.claude/agents'
    New-Item -ItemType Directory -Force -Path $agents | Out-Null
    Get-ChildItem (Join-Path $Src 'agents') -Filter *.md | ForEach-Object { Copy-Item $_.FullName $agents -Force }
    Write-Host "  claude: agents -> $agents"
  }
}

Write-Host "SuperStack installer (source: $Src, base: $Base)"
if ($All) {
  foreach ($h in $SkillsRel.Keys) {
    $marker = Join-Path $Base $HostHome[$h]
    if ($h -eq 'claude' -or (Test-Path $marker)) { Install-AgentHost $h }
  }
} else {
  Install-AgentHost $Agent
}

Write-Host ""
Write-Host "Done. Merge CLAUDE.md into your config (global $Base\.claude\CLAUDE.md or project)."
