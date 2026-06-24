#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Read-only health check of a project's SuperStack runtime.
# Exit 0 = healthy/warnings, 1 = problems, 2 = usage error.
# Usage: ss-doctor.ps1
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false  # git non-zero exits must not throw
if ($args.Count -gt 0) { [Console]::Error.WriteLine("ss-doctor: unexpected argument '$($args[0])' (usage: ss-doctor)"); exit 2 }

$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
if ($dir -match '^/[a-zA-Z]/') { try { $dir = (& cygpath -w $dir 2>$null).Trim() } catch {} }
$config = Join-Path $dir 'config'
$ledger = Join-Path $dir 'ledger.jsonl'

$script:ok = 0; $script:warn = 0; $script:fail = 0
$script:lines = @('ss-doctor: SuperStack project health (.superstack/)', ('-' * 54))
function Emit($status, $label, $detail) {
  switch ($status) { 'OK' { $script:ok++ } 'WARN' { $script:warn++ } 'FAIL' { $script:fail++ } }
  $script:lines += ('  {0,-6} {1,-10} {2}' -f "[$status]", $label, $detail)
}

# 1. jq
if (Get-Command jq -ErrorAction SilentlyContinue) {
  $ver = (jq --version 2>$null); if (-not $ver) { $ver = 'jq' }
  Emit OK jq "$ver on PATH"
} else {
  Emit FAIL jq 'not found -> install jq (needed by audit/report/replay/evolve)'
}

# 2. git
$inRepo = $false; $root = ''
if (Get-Command git -ErrorAction SilentlyContinue) {
  $null = (git rev-parse --is-inside-work-tree 2>$null)
  if ($LASTEXITCODE -eq 0) {
    $br = (git branch --show-current 2>$null); if (-not $br) { $br = 'detached' }
    Emit OK git "git repo (branch: $br)"
    $inRepo = $true; $root = (git rev-parse --show-toplevel 2>$null)
  } else {
    Emit WARN git 'not a git repo -> ledger change will be "default"; gitignore check skipped'
  }
} else {
  Emit WARN git 'git not on PATH -> branch detection degrades (change=default)'
}

# 3. config
if (Test-Path $config) {
  $mp = ((Get-Content $config | Where-Object { $_ -match '^mandatory_phases=' } | Select-Object -Last 1) -replace '^mandatory_phases=', '')
  $et = ((Get-Content $config | Where-Object { $_ -match '^evolve_threshold=' } | Select-Object -Last 1) -replace '^evolve_threshold=', '')
  $mp = if ($mp) { $mp.Trim() } else { '' }
  $et = if ($et) { $et.Trim() } else { '' }
  $problem = ''
  $valid = @('frame','plan','build','review','qa','secure','ship','learn')
  if ($mp) { foreach ($p in ($mp -split ',')) { if ($p -and ($valid -notcontains $p)) { $problem = "unknown phase ""$p"" in mandatory_phases"; break } } }
  if (-not $problem -and $et) { if ($et -notmatch '^[0-9]+$' -or [int]$et -lt 1) { $problem = "evolve_threshold ""$et"" not a positive integer" } }
  if ($problem) { Emit WARN config "$problem -> edit .superstack/config" }
  else {
    $mpShow = if ($mp) { $mp } else { 'review,secure' }
    $etShow = if ($et) { $et } else { '3' }
    Emit OK config "mandatory_phases=$mpShow  evolve_threshold=$etShow"
  }
} else {
  Emit WARN config '.superstack/config missing -> run /ss-init'
}

# 4. gitignore
if ($inRepo) {
  $gif = Join-Path $root '.gitignore'
  $ignored = $false
  if (Test-Path $gif) {
    $ignored = @(Get-Content $gif | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -eq '.superstack/' -or $_ -eq '.superstack' }).Count -gt 0
  }
  if ($ignored) { Emit OK gitignore '.superstack/ is gitignored' }
  else { Emit WARN gitignore '.superstack/ not gitignored -> run /ss-init' }
} else {
  Emit OK gitignore 'n/a (not a git repo)'
}

# 5. ledger
if (Test-Path $ledger) {
  $nonEmpty = @(Get-Content $ledger | Where-Object { $_.Trim() -ne '' })
  $total = $nonEmpty.Count
  $bad = @($nonEmpty | Where-Object { $_.Trim() -notmatch '^\{.*\}$' }).Count
  if ($total -eq 0) { Emit WARN ledger 'ledger is empty -> run /ss-init or start the loop' }
  elseif ($bad -gt 0) { Emit FAIL ledger "$bad of $total lines malformed -> inspect .superstack/ledger.jsonl" }
  else { Emit OK ledger "$total entries, all well-formed" }
} else {
  Emit WARN ledger 'no ledger yet -> run /ss-init or start the loop'
}

# footer
$script:lines += ('-' * 54)
$verdict = if ($script:fail -gt 0) { 'PROBLEMS' } elseif ($script:warn -gt 0) { 'WARNINGS' } else { 'HEALTHY' }
$script:lines += ('ok: {0}   warnings: {1}   problems: {2}   verdict: {3}' -f $script:ok, $script:warn, $script:fail, $verdict)
Write-Output ($script:lines -join "`n")
if ($script:fail -gt 0) { exit 1 }
exit 0
