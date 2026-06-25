#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Cross-run loop analytics from the ledger (read-only).
# Usage: ss-stats.ps1 [-Since <Nd|Nh|YYYY-MM-DD>] [-Limit N]   Exit: 0 ok, 1 usage.
param([string]$Since='', [string]$Limit='10')
$ErrorActionPreference = 'Stop'

if ($Limit -notmatch '^[0-9]+$' -or [int]$Limit -lt 1) { [Console]::Error.WriteLine("ss-stats: --limit must be a positive integer"); exit 1 }
$lim = [int]$Limit

$cutoff = ''
if ($Since) {
  if ($Since -match '^([0-9]+)d$') { $cutoff = [DateTime]::UtcNow.AddDays(-[int]$Matches[1]).ToString('yyyy-MM-ddTHH:mm:ssZ') }
  elseif ($Since -match '^([0-9]+)h$') { $cutoff = [DateTime]::UtcNow.AddHours(-[int]$Matches[1]).ToString('yyyy-MM-ddTHH:mm:ssZ') }
  elseif ($Since -match '^[0-9]{4}-[0-1][0-9]-[0-3][0-9]$') { $cutoff = "$Since" + 'T00:00:00Z' }
  else { [Console]::Error.WriteLine("ss-stats: bad --since '$Since' (use Nd, Nh, or YYYY-MM-DD)"); exit 1 }
}

$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
if ($dir -match '^/[a-zA-Z]/') { try { $dir = (& cygpath -w $dir 2>$null).Trim() } catch {} }
$ledger = Join-Path $dir 'ledger.jsonl'
$SEP = '-' * 54
function EmitEmpty($m) { Write-Output (@('ss-stats: loop trends', $SEP, "ss-stats: $m") -join "`n") }

if (-not (Test-Path $ledger) -or (Get-Item $ledger).Length -eq 0) { EmitEmpty 'no runs yet'; exit 0 }

# parse + normalize ts (ConvertFrom-Json coerces ISO strings to [datetime])
$entries = @()
foreach ($line in (Get-Content $ledger)) {
  if ($line.Trim() -eq '') { continue }
  $o = $line | ConvertFrom-Json
  $ts = if ($o.ts -is [datetime]) { $o.ts.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { [string]$o.ts }
  $entries += [PSCustomObject]@{ ts=$ts; change=[string]$o.change; phase=[string]$o.phase; event=[string]$o.event; status=[string]$o.status }
}
if ($cutoff) { $entries = @($entries | Where-Object { [string]::CompareOrdinal($_.ts, $cutoff) -ge 0 }) }

# build run records
$runs = @()
foreach ($g in ($entries | Group-Object change)) {
  $es = $g.Group
  $tss = [string[]]@($es | ForEach-Object { $_.ts }); [Array]::Sort($tss, [System.StringComparer]::Ordinal)
  $runs += [PSCustomObject]@{
    change = [string]$g.Name
    first  = $tss[0]
    last   = $tss[-1]
    phases = @($es.phase | Select-Object -Unique).Count
    fails  = @($es | Where-Object { $_.event -eq 'gate' -and $_.status -eq 'fail' }).Count
    gates  = @($es | Where-Object { $_.event -eq 'gate' }).Count
    skips  = @($es | Where-Object { $_.event -eq 'skip' }).Count
  }
}
if ($runs.Count -eq 0) {
  if ($cutoff) { EmitEmpty 'no runs in window' } else { EmitEmpty 'no runs yet' }
  exit 0
}
# order by first ts (ordinal), tiebreak change
$runs = @($runs | Sort-Object @{Expression='first'}, @{Expression='change'})

$n = $runs.Count
$tf = ($runs | Measure-Object fails -Sum).Sum; if (-not $tf) { $tf = 0 }
$tg = ($runs | Measure-Object gates -Sum).Sum; if (-not $tg) { $tg = 0 }
$tk = ($runs | Measure-Object skips -Sum).Sum; if (-not $tk) { $tk = 0 }

$trend = 'n/a'
if ($n -ge 4) {
  $h = [math]::Floor($n/2)
  $o = $runs[0..($h-1)]; $w = $runs[$h..($n-1)]
  $fo = ($o | Measure-Object fails -Sum).Sum; if (-not $fo) { $fo = 0 }
  $go = ($o | Measure-Object gates -Sum).Sum; if (-not $go) { $go = 0 }
  $fn = ($w | Measure-Object fails -Sum).Sum; if (-not $fn) { $fn = 0 }
  $gn = ($w | Measure-Object gates -Sum).Sum; if (-not $gn) { $gn = 0 }
  if ($go -eq 0 -or $gn -eq 0) { $trend = 'n/a' }
  elseif (($fn*$go) -lt ($fo*$gn)) { $trend = 'improving' }
  elseif (($fn*$go) -gt ($fo*$gn)) { $trend = 'worsening' }
  else { $trend = 'flat' }
}

function ToEpoch($s) {
  $dt = [datetime]::ParseExact($s, 'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal)
  [int][math]::Floor(($dt - [datetime]'1970-01-01T00:00:00Z').TotalSeconds)
}

$window = if ($Since) { "since $Since" } else { 'all' }
$lines = @('ss-stats: loop trends', $SEP, "runs: $n   window: $window", $SEP)
$lines += ('{0,-16}{1,-8}{2,-8}{3,-7}{4,-7}{5}' -f 'change','date','phases','fails','skips','span')
$recent = @($runs); [Array]::Reverse($recent)
$recent = @($recent | Select-Object -First $lim)
foreach ($r in $recent) {
  $chg = if ($r.change.Length -gt 15) { $r.change.Substring(0,15) } else { $r.change }
  $mins = [math]::Floor(((ToEpoch $r.last) - (ToEpoch $r.first)) / 60)
  $lines += ('{0,-16}{1,-8}{2,-8}{3,-7}{4,-7}+{5}m' -f $chg, $r.first.Substring(5,5), $r.phases, $r.fails, $r.skips, $mins)
}
$lines += $SEP
if ($tg -gt 0) {
  $rate = [math]::Floor(100*$tf/$tg)
  $lines += "gate-fail rate: $rate% ($tf/$tg)   skips: $tk   trend: $trend"
} else {
  $lines += "gate-fail rate: n/a (0 gates)   skips: $tk   trend: $trend"
}
Write-Output ($lines -join "`n")
exit 0
