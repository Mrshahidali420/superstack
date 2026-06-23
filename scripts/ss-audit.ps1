#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Verify mandatory phases ran. Usage: ss-audit.ps1 [change] | ss-audit.ps1 -Attest
param([string]$Change = "", [switch]$Attest)
$ErrorActionPreference = 'Stop'
$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
$ledger = Join-Path $dir 'ledger.jsonl'; $config = Join-Path $dir 'config'
$mandatory = @('review','secure')
if (Test-Path $config) {
  $m = Select-String -Path $config -Pattern '^mandatory_phases=(.*)$' | Select-Object -Last 1
  if ($m) { $mandatory = $m.Matches.Groups[1].Value -split ',' }
}
if (-not $Change) { $Change = "$(git branch --show-current 2>$null)".Trim() }
if (-not $Change) { $Change = 'default' }
if (-not (Test-Path $ledger)) { Write-Host "ss-audit: no ledger at $ledger"; exit 1 }
$entries = Get-Content $ledger | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.change -eq $Change }
function Get-State([string]$p) {
  $e = $entries | Where-Object { $_.phase -eq $p }
  if ($e | Where-Object { $_.event -eq 'gate' -and $_.status -eq 'pass' }) { return 'pass' }
  $s = $e | Where-Object { $_.event -eq 'skip' } | Select-Object -Last 1
  if ($s) { return "skip:$($s.note)" }
  return ''
}
if ($Attest) {
  $line = 'SuperStack process:'
  foreach ($p in 'frame','plan','build','review','qa','secure','ship','learn') {
    $s = Get-State $p
    if ($s -eq 'pass') { $line += " $p OK" } elseif ($s -like 'skip:*') { $line += " $p SKIP" }
  }
  Write-Output $line; exit 0
}
Write-Host "Process audit for '$Change' (mandatory: $($mandatory -join ',')):"
$missing = @()
foreach ($p in $mandatory) {
  $s = Get-State $p
  if ($s -eq 'pass') { Write-Host "  $($p): pass" }
  elseif ($s -like 'skip:*') { Write-Host "  $($p): skip" }
  else { Write-Host "  $($p): MISSING"; $missing += $p }
}
if ($missing.Count) { Write-Host "VERDICT: INCOMPLETE - missing: $($missing -join ' ')"; exit 1 }
Write-Host "VERDICT: COMPLETE"; exit 0
