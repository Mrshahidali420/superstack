#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Detect drift between a plan's declared files and the branch's actual changes (read-only).
# Usage: ss-drift.ps1 <plan-file> [base]    Exit: 0 clean, 1 drift, 2 usage/precondition.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false  # git non-zero exits must not throw

$pos = @()
foreach ($a in $args) {
  if ($a -like '-*') { [Console]::Error.WriteLine("ss-drift: unknown flag '$a' (usage: ss-drift <plan-file> [base])"); exit 2 }
  $pos += $a
}
if ($pos.Count -lt 1) { [Console]::Error.WriteLine("ss-drift: missing plan file (usage: ss-drift <plan-file> [base])"); exit 2 }
if ($pos.Count -gt 2) { [Console]::Error.WriteLine("ss-drift: too many arguments (usage: ss-drift <plan-file> [base])"); exit 2 }
$plan = $pos[0]
$base = if ($pos.Count -ge 2) { $pos[1] } else { 'main' }
if (-not (Test-Path -LiteralPath $plan -PathType Leaf)) { [Console]::Error.WriteLine("ss-drift: plan file not found: $plan"); exit 2 }
$null = (git rev-parse --is-inside-work-tree 2>$null); if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine("ss-drift: not a git repository"); exit 2 }
$null = (git rev-parse --verify --quiet $base 2>$null); if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine("ss-drift: base ref not found: $base"); exit 2 }

# declared set: first backtick token from Create/Modify/Test bullets inside **Files:** blocks
$declared = [System.Collections.Generic.HashSet[string]]::new()
$inFiles = $false
foreach ($line in (Get-Content -LiteralPath $plan)) {
  $line = $line.TrimEnd("`r")
  if ($line -match '^\*\*Files:\*\*') { $inFiles = $true; continue }
  if ($inFiles -and $line -match '^\s*$') { $inFiles = $false; continue }
  if ($inFiles -and ($line -match '^(\*\*|### |- \[ \])')) { $inFiles = $false }
  if ($inFiles -and ($line -match '^- (Create|Modify|Test):')) {
    if ($line -match '`([^`]+)`') {
      $p = $Matches[1] -replace ':[0-9]+(-[0-9]+)?$', ''
      [void]$declared.Add($p)
    }
  }
}

# changed set: committed (base...HEAD) + uncommitted staged (HEAD) + untracked files
# mirrors bash: { git diff --name-only "$base"...HEAD; git diff --name-only HEAD; git ls-files --others --exclude-standard; }
$changed = [System.Collections.Generic.HashSet[string]]::new()
$raw = @()
$raw += (git diff --name-only "$base...HEAD" 2>$null)
$raw += (git diff --name-only HEAD 2>$null)
$raw += (git ls-files --others --exclude-standard 2>$null)
foreach ($f in $raw) {
  if ([string]::IsNullOrWhiteSpace($f)) { continue }
  $f = $f.Trim()
  if ($f -like 'docs/specs/*') { continue }
  [void]$changed.Add($f)
}

# set differences, byte-order (Ordinal) sorted to match bash LC_ALL=C
$unplanned = [string[]]@($changed | Where-Object { -not $declared.Contains($_) })
$untouched = [string[]]@($declared | Where-Object { -not $changed.Contains($_) })
[Array]::Sort($unplanned, [System.StringComparer]::Ordinal)
[Array]::Sort($untouched, [System.StringComparer]::Ordinal)
$dcount = $declared.Count; $ccount = $changed.Count; $ucount = $unplanned.Count; $tcount = $untouched.Count

$lines = @('ss-drift: plan vs build', ('-' * 54))
$lines += ('{0,-9} {1}' -f 'plan:', (Split-Path -Leaf $plan))
$lines += ('{0,-9} {1}' -f 'base:', $base)
$lines += ('declared: {0}   changed: {1}   unplanned: {2}   untouched: {3}' -f $dcount, $ccount, $ucount, $tcount)
$lines += ('-' * 54)
if ($ucount -gt 0) {
  $lines += 'unplanned changes (not in the plan):'
  foreach ($p in $unplanned) { $lines += "  + $p" }
}
if ($tcount -gt 0) {
  $lines += 'planned but untouched (not yet built / over-declared):'
  foreach ($p in $untouched) { $lines += "  - $p" }
}
$verdict = if ($ucount -gt 0) { 'DRIFT' } else { 'CLEAN' }
$lines += "verdict: $verdict"
Write-Output ($lines -join "`n")
if ($ucount -gt 0) { exit 1 }
exit 0
