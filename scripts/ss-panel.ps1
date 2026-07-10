#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Unified read-only dashboard over the Loop Ledger: report + replay + trace in one view.
# A thin composer - the change is resolved once, then the sibling legs run verbatim.
# Usage: ss-panel.ps1 [change] [-Save]   Exit: 0 ok, 1 usage/no ledger, 2 missing jq.
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$ErrorActionPreference = 'Stop'
$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
if ($dir -match '^/[a-zA-Z]/') { try { $dir = (& cygpath -w $dir 2>$null).Trim() } catch {} }
$ledger = Join-Path $dir 'ledger.jsonl'
if (-not (Get-Command jq -ErrorAction SilentlyContinue)) { [Console]::Error.WriteLine('ss-panel: jq is required'); exit 2 }

$save = $false; $change = ''
foreach ($a in @($Rest)) {
  if ($null -eq $a -or $a -eq '') { continue }
  if ($a -ceq '--save' -or $a -ceq '-Save') { $save = $true }
  elseif ($a.StartsWith('-')) { [Console]::Error.WriteLine("ss-panel: unknown flag '$a' (usage: ss-panel [change] [--save])"); exit 1 }
  else { $change = $a }
}
if (-not ((Test-Path -LiteralPath $ledger -PathType Leaf) -and (Get-Item -LiteralPath $ledger).Length -gt 0)) {
  [Console]::Error.WriteLine("ss-panel: no ledger at $ledger (run /ss-init)"); exit 1
}
if (-not $change) { $change = ((Get-Content -LiteralPath $ledger -Raw | jq -rn '[inputs][-1].change // empty') | Out-String).Trim() }
if (-not $change) { [Console]::Error.WriteLine('ss-panel: could not resolve a change from the ledger'); exit 1 }

function Leg($name) {
  $ps1 = Join-Path $PSScriptRoot "$name.ps1"
  $o = & pwsh -NoProfile -File $ps1 $change 2>$null
  if ($LASTEXITCODE -eq 0) { return (@($o) -join "`n") }
  return ('  ({0} unavailable - exit {1})' -f $name, $LASTEXITCODE)
}

$SEP = '-' * 54
$out = New-Object System.Collections.Generic.List[string]
$out.Add("ss-panel: $change - report + replay + trace"); $out.Add($SEP)
$out.Add((Leg 'ss-report')); $out.Add($SEP)
$out.Add((Leg 'ss-replay')); $out.Add($SEP)
$out.Add((Leg 'ss-trace'))
$output = ($out -join "`n")
Write-Output $output

if ($save) {
  $rdir = Join-Path $dir 'replays'
  New-Item -ItemType Directory -Force -Path $rdir | Out-Null
  $file = Join-Path $rdir ('panel-' + ($change -replace '/', '-') + '.md')
  [IO.File]::WriteAllText($file, ("``````" + "`n" + $output + "`n" + "``````" + "`n"))
  [Console]::Error.WriteLine(('saved -> .superstack/replays/panel-' + ($change -replace '/', '-') + '.md'))
}
exit 0
