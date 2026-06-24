#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Detect ledger patterns; optionally auto-apply low-risk fixes. Usage: ss-evolve.ps1 [-Json] [-NewOnly] [-Apply] [-DryRun]
param([switch]$Json, [switch]$NewOnly, [switch]$Apply, [switch]$DryRun, [switch]$Explore, [string]$Since)
$ErrorActionPreference = 'Stop'
if ($Apply -and $Explore) { Write-Error 'ss-evolve: --apply and --explore are mutually exclusive'; exit 1 }
$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
if ($dir -match '^/[a-zA-Z]/') { try { $dir = (& cygpath -w $dir 2>$null).Trim() } catch {} }
$ledger = Join-Path $dir 'ledger.jsonl'; $config = Join-Path $dir 'config'; $state = Join-Path $dir 'evolve-state'

$threshold = 3
if (Test-Path $config) {
  $m = Select-String -Path $config -Pattern '^evolve_threshold=(.*)$' | Select-Object -Last 1
  if ($m) { $threshold = [int]$m.Matches.Groups[1].Value }
}

$cutoff = ''
if ($Since) {
  if ($Since -match '^([0-9]+)d$') { $cutoff = [DateTime]::UtcNow.AddDays(-[int]$Matches[1]).ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture) }
  elseif ($Since -match '^([0-9]+)h$') { $cutoff = [DateTime]::UtcNow.AddHours(-[int]$Matches[1]).ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture) }
  elseif ($Since -match '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') { $cutoff = "$($Since)T00:00:00Z" }
  else { Write-Error "ss-evolve: bad -Since '$Since' (want Nd, Nh, or YYYY-MM-DD)"; exit 1 }
}

$findings = @()
if (Test-Path $ledger) {
  $all = @(Get-Content $ledger | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
  if ($cutoff) { $all = @($all | Where-Object { $ts = if ($_.ts -is [datetime]) { $_.ts.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture) } else { [string]$_.ts }; [string]::CompareOrdinal($ts, $cutoff) -ge 0 }) }
  $skips = @($all | Where-Object { $_.event -eq 'skip' } | Group-Object phase | Sort-Object Name | ForEach-Object {
    $notes = @($_.Group | ForEach-Object { $_.note } | Where-Object { $_ })
    $reason = if ($notes.Count) { ($notes | Group-Object | Sort-Object Count, Name -Descending | Select-Object -First 1).Name } else { '' }
    [pscustomobject]@{ id = "skipped:$($_.Name)"; type = 'skipped'; phase = $_.Name; count = $_.Count; reason = $reason } })
  $fails = @($all | Where-Object { $_.event -eq 'gate' -and $_.status -eq 'fail' } | Group-Object phase | Sort-Object Name | ForEach-Object {
    [pscustomobject]@{ id = "failing:$($_.Name)"; type = 'failing'; phase = $_.Name; count = $_.Count; reason = '' } })
  $findings = @($skips) + @($fails) | Where-Object { $_.count -ge $threshold }
}

function Seen([string]$id) { (Test-Path $state) -and (Select-String -Path $state -Pattern ([regex]::Escape($id)) -SimpleMatch -Quiet) }

$active = @($findings | Where-Object { -not (($NewOnly -or $Apply) -and (Seen $_.id)) })

if ($Apply) {
  $applied = 0
  foreach ($f in $active) {
    $line = if ($f.type -eq 'skipped') {
      "- **``$($f.phase)`` is routinely skipped** ($($f.count)x" + $(if ($f.reason) { "; usual reason: ""$($f.reason)""" } else { '' }) + "). If that is expected here, keep recording the skip reason or drop ``$($f.phase)`` from ``.superstack/config`` ``mandatory_phases``; otherwise it is a process gap to close."
    } else {
      "- **``$($f.phase)`` gate often fails first pass** ($($f.count)x). Recurring friction - see the ledger notes; consider tightening the upstream phase or adding a checklist."
    }
    if ($DryRun) { Write-Output "[dry-run] $($f.id) -> append to CONTEXT.md + commit 'chore(evolve): document $($f.id)'"; continue }
    if (-not (Test-Path CONTEXT.md)) { Set-Content CONTEXT.md "# Context" -Encoding utf8 }
    if (-not (Select-String -Path CONTEXT.md -Pattern '^## Evolved insights$' -Quiet)) { Add-Content CONTEXT.md "`n## Evolved insights" }
    Add-Content CONTEXT.md $line
    New-Item -ItemType Directory -Force -Path $dir | Out-Null; Add-Content $state $f.id
    $sib = Join-Path $PSScriptRoot 'ledger'; if (Test-Path $sib) { try { bash $sib evolve note na "applied $($f.id)" *>$null } catch {} }
    git add CONTEXT.md *>$null; git commit -q -m "chore(evolve): document $($f.id)" *>$null
    Write-Output "applied $($f.id) (revert with: git revert HEAD)"; $applied++
  }
  if (-not $DryRun -and $applied -eq 0) { Write-Output "ss-evolve: nothing new to apply" }
}
elseif ($Json) {
  Write-Output (@($active | ForEach-Object { [pscustomobject]@{ id = $_.id; type = $_.type; phase = $_.phase; count = $_.count; reason = $_.reason } }) | ConvertTo-Json -Compress -AsArray)
}
else {
  if ($active.Count -eq 0) { Write-Output "ss-evolve: no patterns at or above threshold $threshold" }
  foreach ($f in $active) {
    $sfx = if ($f.reason) { " - reason: ""$($f.reason)""" } else { '' }
    Write-Output "- [$($f.type)] $($f.phase) (x$($f.count))$sfx"
  }
}
