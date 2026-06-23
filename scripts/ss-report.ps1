#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Shareable Markdown summary of how a change was built. Usage: ss-report.ps1 [change] [-Save]
param([string]$Change = "", [switch]$Save)
$ErrorActionPreference = 'Stop'
$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
# On Windows/MSYS2/Cygwin, bash may pass a Unix-style path (/c/Users/...). Convert it.
if ($dir -match '^/[a-zA-Z]/') {
  try { $dir = (& cygpath -w $dir 2>$null).Trim() } catch {}
}
$env:SUPERSTACK_DIR = $dir
$ledger = Join-Path $dir 'ledger.jsonl'
if (-not $Change) { $Change = "$(git branch --show-current 2>$null)".Trim() }
if (-not $Change) { $Change = 'default' }

$run = 0; $skipped = 0; $skips = ''; $notes = ''; $first = $null; $last = $null
if (Test-Path $ledger) {
  $e = @(Get-Content $ledger | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.change -eq $Change })
  $run = @($e | Where-Object { $_.event -eq 'gate' } | Select-Object -ExpandProperty phase -Unique).Count
  $skipE = @($e | Where-Object { $_.event -eq 'skip' })
  $skipped = @($skipE | Select-Object -ExpandProperty phase -Unique).Count
  $skips = (($skipE | ForEach-Object { "$($_.phase) ($($_.note))" }) -join ', ')
  $notes = ((@($e | Where-Object { $_.event -eq 'note' }) | ForEach-Object { "$($_.phase): $($_.note)" }) -join ', ')
  $ts = @($e | Select-Object -ExpandProperty ts | Sort-Object)
  if ($ts.Count) { $first = $ts[0]; $last = $ts[-1] }
}

$elapsed = ''
if ($first -and $last -and $first -ne $last) {
  try {
    $styles = [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal
    $span = [datetime]::Parse($last, [Globalization.CultureInfo]::InvariantCulture, $styles) -
            [datetime]::Parse($first, [Globalization.CultureInfo]::InvariantCulture, $styles)
    if ($span.TotalSeconds -ge 0) {
      $h = [int][math]::Floor($span.TotalHours); $m = $span.Minutes
      $elapsed = if ($h -gt 0) { "${h}h ${m}m" } else { "${m}m" }
    }
  } catch {}
}

$att = ''
$audit = Join-Path $PSScriptRoot 'ss-audit.ps1'
if (Test-Path $audit) {
  try {
    $raw = (& $audit -Attest) 2>$null
    if ($raw -is [array]) { $raw = $raw -join "`n" }
    if ("$raw".StartsWith('SuperStack process:')) { $att = "$raw".Trim() }
  } catch {}
}

$gitLine = ''
if ((git rev-parse --is-inside-work-tree 2>$null) -eq 'true') {
  $mb = (git merge-base HEAD main 2>$null); if (-not $mb) { $mb = (git merge-base HEAD master 2>$null) }
  if ($mb) {
    $commits = (git rev-list --count "$mb..HEAD" 2>$null)
    $short = (git diff --shortstat "$mb..HEAD" 2>$null)
    $files = if ($short -match '(\d+) files? changed') { $Matches[1] } else { '0' }
    $ins   = if ($short -match '(\d+) insertion')      { $Matches[1] } else { '0' }
    $del   = if ($short -match '(\d+) deletion')       { $Matches[1] } else { '0' }
    $names = @(git diff --name-only "$mb..HEAD" 2>$null)
    $tests = @($names | Where-Object { $_ -match '(^|/)(tests?|spec|__tests__)/|\.(test|spec)\.' }).Count
    $gitLine = "- Change: $commits commits, $files files, +$ins / -$del, $tests test files touched"
  }
}

$bt = [char]96
$lines = @("### SuperStack run: $Change")
$lines += $(if ($elapsed) { "Built through the loop in $elapsed." } else { "Built through the loop." })
$lines += ''
if ($att) { $lines += "$bt$att$bt"; $lines += '' }
$lines += "- Phases: $run run, $skipped skipped"
if ($gitLine) { $lines += $gitLine }
if ($skips)   { $lines += "- Skipped: $skips" }
if ($notes)   { $lines += "- Notes: $notes" }
$block = ($lines -join "`n")
Write-Output $block
if ($Save) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  Set-Content -Path (Join-Path $dir ("run-report-" + ($Change -replace '/', '-') + ".md")) -Value $block -Encoding utf8
}
