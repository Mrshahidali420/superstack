#!/usr/bin/env pwsh
# SuperStack installer (Windows / PowerShell).
# Copies the /ss-* skills and agents into ~/.claude and points you at CLAUDE.md.
$ErrorActionPreference = 'Stop'

$Src = $PSScriptRoot
$ClaudeHome = if ($env:CLAUDE_HOME) { $env:CLAUDE_HOME } else { Join-Path $HOME '.claude' }

Write-Host "SuperStack installer"
Write-Host "  source: $Src"
Write-Host "  target: $ClaudeHome"
New-Item -ItemType Directory -Force -Path (Join-Path $ClaudeHome 'skills') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $ClaudeHome 'agents') | Out-Null

Get-ChildItem -Directory (Join-Path $Src 'skills') | ForEach-Object {
  if (Test-Path (Join-Path $_.FullName 'SKILL.md')) {
    $name = "ss-$($_.Name)"
    $dest = Join-Path $ClaudeHome "skills\$name"
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    Copy-Item -Recurse $_.FullName $dest
    Write-Host "  + skill  $name"
  }
}

Get-ChildItem (Join-Path $Src 'agents') -Filter *.md | ForEach-Object {
  Copy-Item $_.FullName (Join-Path $ClaudeHome 'agents') -Force
  Write-Host "  + agent  $($_.BaseName)"
}

Write-Host ""
Write-Host "Done. The /ss-* skills and agents are installed."
Write-Host "Ralph loop: $Src\ralph\loop.ps1"
Write-Host ""
Write-Host "Adopt the operating system by merging CLAUDE.md into your config:"
Write-Host "  global  -> $ClaudeHome\CLAUDE.md"
Write-Host "  project -> .\CLAUDE.md   (in any repo you work in)"
