#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Replay one loop run from the ledger as a chronological timeline. Usage: ss-replay.ps1 [change] [-Save]
param([string]$Change = "", [switch]$Save)
$ErrorActionPreference = 'Stop'
$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
# On Windows/MSYS2/Cygwin, bash may pass a Unix-style path (/c/Users/...). Convert it.
if ($dir -match '^/[a-zA-Z]/') { try { $dir = (& cygpath -w $dir 2>$null).Trim() } catch {} }
$ledger = Join-Path $dir 'ledger.jsonl'
$explicit = [bool]$Change
$SEP = '------------------------------------------------------'
function Fmt([int]$s) { "+$([math]::Floor($s / 60))m" }

$rows = @()
if (Test-Path $ledger) {
  $all = @(Get-Content $ledger | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
  if (-not $explicit -and $all.Count) { $Change = "$($all[-1].change)" }
  $rows = @($all | Where-Object { "$($_.change)" -eq $Change })
}

if (-not $Change -or $rows.Count -eq 0) {
  if ($explicit) { Write-Output "ss-replay: no run found for $Change" } else { Write-Output "ss-replay: no run to replay" }
  exit 0
}

$t0 = [datetime]$rows[0].ts
$failed = @{}
$retries = 0; $skips = 0
$lines = @("loop replay: $Change", $SEP)
foreach ($r in $rows) {
  $el = [int][math]::Floor((([datetime]$r.ts) - $t0).TotalSeconds)
  $mk = if ($r.status -eq 'na' -or $null -eq $r.status) { '' } else { "$($r.status)".ToUpper() }
  $rt = $false
  if ($r.event -eq 'gate' -and $r.status -eq 'pass' -and $failed.ContainsKey("$($r.phase)")) { $rt = $true; $retries++ }
  if ($r.event -eq 'gate' -and $r.status -eq 'fail') { $failed["$($r.phase)"] = $true }
  if ($r.event -eq 'skip') { $skips++ }
  $note = "$($r.note)"; if ($rt) { $note = "(retry) $note" }
  # Bash IFS=$'\t' collapses consecutive tabs, so when mk="" the retry-bit shifts into the
  # marker column and the note shifts into the next slot — match that behaviour exactly.
  $mkCol = if ($mk -eq '') { if ($rt) { '1' } else { '0' } } else { $mk }
  $noteCol = if ($mk -eq '') { '' } else { $note }
  $lines += ('{0,6}  {1,-7} {2,-5} {3,-4} {4}' -f (Fmt $el), "$($r.phase)", "$($r.event)", $mkCol, $noteCol).TrimEnd()
}
$phases = @($rows | Select-Object -ExpandProperty phase -Unique).Count
$openfails = 0
foreach ($g in ($rows | Group-Object phase)) {
  $gates = @($g.Group | Where-Object { $_.event -eq 'gate' })
  if ($gates.Count -and $gates[-1].status -eq 'fail') { $openfails++ }
}
$span = [int][math]::Floor((([datetime]$rows[-1].ts) - $t0).TotalSeconds)
$total = (Fmt $span).TrimStart('+')
$lines += $SEP
$lines += "phases: $phases   gate-retries: $retries   skips: $skips   open-fails: $openfails   total: ~$total"
$block = ($lines -join "`n")
Write-Output $block
if ($Save) {
  $rdir = Join-Path $dir 'replays'
  New-Item -ItemType Directory -Force -Path $rdir | Out-Null
  $bt = [char]96
  $fenced = ($bt.ToString() * 3) + "`n" + $block + "`n" + ($bt.ToString() * 3)
  Set-Content -Path (Join-Path $rdir (($Change -replace '/', '-') + '.md')) -Value $fenced -Encoding utf8
}
