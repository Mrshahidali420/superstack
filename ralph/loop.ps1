#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# SuperStack - Ralph autonomous loop (Windows / PowerShell).
# Spawns a fresh agent per iteration until every prd.json story passes, or max iterations.
# Memory lives in git + prd.json + progress.md.
#
# Usage:  ./loop.ps1 [-MaxIterations 10]
# Config (env): PRD_FILE, PROGRESS_FILE, PROMPT_FILE, AGENT_CMD
param([int]$MaxIterations = 10)
$ErrorActionPreference = 'Stop'

$PrdFile      = if ($env:PRD_FILE)      { $env:PRD_FILE }      else { 'prd.json' }
$ProgressFile = if ($env:PROGRESS_FILE) { $env:PROGRESS_FILE } else { 'progress.md' }
$PromptFile   = if ($env:PROMPT_FILE)   { $env:PROMPT_FILE }   else { Join-Path $PSScriptRoot 'prompt.md' }
$AgentCmd     = if ($env:AGENT_CMD)     { $env:AGENT_CMD }     else { 'claude -p --dangerously-skip-permissions' }

if (-not (Get-Command jq -ErrorAction SilentlyContinue)) { Write-Error 'jq is required (winget install jqlang.jq)'; exit 1 }
if (-not (Test-Path $PrdFile))    { Write-Error "$PrdFile not found - run /ss-ralph to generate one"; exit 1 }
if (-not (Test-Path $PromptFile)) { Write-Error "prompt template $PromptFile not found"; exit 1 }

function Get-Remaining { [int](jq '[.stories[] | select(.passes == false)] | length' $PrdFile) }

$tokens = $AgentCmd.Split(' ')
$exe = $tokens[0]
$agentArgs = if ($tokens.Count -gt 1) { $tokens[1..($tokens.Count - 1)] } else { @() }
$nl = [Environment]::NewLine

$iter = 0
while ($iter -lt $MaxIterations) {
  $left = Get-Remaining
  if ($left -eq 0) { Write-Host "All stories pass. Completed in $iter iteration(s)."; exit 0 }
  $iter++
  Write-Host "---- iteration $iter/$MaxIterations - $left story(ies) remaining ----"

  $prompt  = (Get-Content $PromptFile -Raw)
  $prompt += $nl + $nl + "## Current $PrdFile" + $nl + '```json' + $nl + (Get-Content $PrdFile -Raw) + $nl + '```' + $nl
  if (Test-Path $ProgressFile) { $prompt += $nl + "## $ProgressFile" + $nl + (Get-Content $ProgressFile -Raw) }

  $prompt | & $exe @agentArgs
  if ($LASTEXITCODE -ne 0) { Write-Error "agent run failed on iteration $iter"; exit 1 }
}

Write-Host "Reached max iterations ($MaxIterations). $(Get-Remaining) story(ies) still open."
exit 1
