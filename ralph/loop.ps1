#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# SuperStack - Ralph autonomous loop (Windows / PowerShell).
# Spawns a fresh agent per iteration until every prd.json story passes, or max iterations.
# Each iteration's output is logged under runs/; a completed run is archived under archive/.
# Memory lives in git + prd.json + progress.md.
#
# Usage:  ./loop.ps1 [-DryRun] [-MaxIterations 10]
# Config (env): PRD_FILE, PROGRESS_FILE, PROMPT_FILE, AGENT_CMD, RUN_DIR, ARCHIVE_DIR
param([switch]$DryRun, [int]$MaxIterations = 10)
$ErrorActionPreference = 'Stop'

$PrdFile      = if ($env:PRD_FILE) { $env:PRD_FILE } else { 'prd.json' }
$ProgressFile = if ($env:PROGRESS_FILE) { $env:PROGRESS_FILE } else { 'progress.md' }
$PromptFile   = if ($env:PROMPT_FILE) { $env:PROMPT_FILE } else { Join-Path $PSScriptRoot 'prompt.md' }
$AgentCmd     = if ($env:AGENT_CMD) { $env:AGENT_CMD } else { 'claude -p --dangerously-skip-permissions' }
$RunDir       = if ($env:RUN_DIR) { $env:RUN_DIR } else { 'runs' }
$ArchiveDir   = if ($env:ARCHIVE_DIR) { $env:ARCHIVE_DIR } else { 'archive' }

if (-not (Get-Command jq -ErrorAction SilentlyContinue)) { Write-Error 'jq is required (winget install jqlang.jq)'; exit 1 }
if (-not (Test-Path $PrdFile))    { Write-Error "$PrdFile not found - run /ss-ralph to generate one"; exit 1 }
if (-not (Test-Path $PromptFile)) { Write-Error "prompt template $PromptFile not found"; exit 1 }

function Get-Remaining { [int](jq '[.stories[] | select(.passes == false)] | length' $PrdFile) }
function Get-NextStory { jq -r '[.stories[] | select(.passes==false)] | sort_by(.priority) | .[0] // empty | "#\(.id) \(.title)"' $PrdFile }
function Save-Archive {
  $branch = ("$(jq -r '.branchName // "feature"' $PrdFile)").Trim() -replace '[^A-Za-z0-9._-]', '-'
  $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
  $dest = Join-Path $ArchiveDir "$branch-$ts"
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item $PrdFile $dest -Force
  if (Test-Path $ProgressFile) { Copy-Item $ProgressFile $dest -Force }
  Write-Host "Archived completed run to $dest"
}

if ($DryRun) {
  Write-Host ("Dry run - {0} story(ies) open." -f (Get-Remaining))
  $ns = Get-NextStory
  if ($ns) { Write-Host "next up: $ns" } else { Write-Host "nothing to do (all pass)" }
  exit 0
}

$tokens = $AgentCmd.Split(' '); $exe = $tokens[0]
$agentArgs = if ($tokens.Count -gt 1) { $tokens[1..($tokens.Count - 1)] } else { @() }
$nl = [Environment]::NewLine

$iter = 0
while ($iter -lt $MaxIterations) {
  $left = Get-Remaining
  if ($left -eq 0) {
    Write-Host "All stories pass. Completed in $iter iteration(s)."
    if ($iter -gt 0) { Save-Archive }
    exit 0
  }
  $iter++
  Write-Host "---- iteration $iter/$MaxIterations - $left remaining - next: $(Get-NextStory) ----"
  New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
  $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
  $prompt  = (Get-Content $PromptFile -Raw)
  $prompt += $nl + $nl + "## Current $PrdFile" + $nl + '```json' + $nl + (Get-Content $PrdFile -Raw) + $nl + '```' + $nl
  if (Test-Path $ProgressFile) { $prompt += $nl + "## $ProgressFile" + $nl + (Get-Content $ProgressFile -Raw) }
  $prompt | & $exe @agentArgs 2>&1 | Tee-Object -FilePath (Join-Path $RunDir "iter-$iter-$ts.log")
  if ($LASTEXITCODE -ne 0) { Write-Error "agent run failed on iteration $iter (see $RunDir)"; exit 1 }
}

Write-Host "Reached max iterations ($MaxIterations). $(Get-Remaining) story(ies) still open."
exit 1
