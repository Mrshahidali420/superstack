#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Change provenance: spec docs + ledger gates interleaved with git commits (read-only).
# Usage: ss-trace.ps1 [-Change <c>] [-Base <b>]   Exit: 0 ok, 1 usage.
param([string]$Change='', [string]$Base='', [Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if ($Rest -and $Rest.Count -gt 0) { [Console]::Error.WriteLine("ss-trace: too many args (usage: ss-trace [<change>] [base])"); exit 1 }

$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
if ($dir -match '^/[a-zA-Z]/') { try { $dir = (& cygpath -w $dir 2>$null).Trim() } catch {} }
$ledger = Join-Path $dir 'ledger.jsonl'

$change = $Change
if (-not $change) { $change = "$(git branch --show-current 2>$null)".Trim() }
if (-not $change) { $change = 'default' }
$base = $Base
if (-not $base) {
  if (git rev-parse --verify -q main 2>$null) { $base = 'main' }
  elseif (git rev-parse --verify -q master 2>$null) { $base = 'master' }
  else { $base = 'main' }
}

$SEP = '-' * 54
$slug = ($change -split '/')[-1]
$haveRef = [bool](git rev-parse --verify -q $change 2>$null)

$rows = New-Object System.Collections.Generic.List[string]
if ((Test-Path $ledger) -and (Get-Item $ledger).Length -gt 0) {
  foreach ($line in (Get-Content $ledger)) {
    if ($line.Trim() -eq '') { continue }
    $o = $line | ConvertFrom-Json
    if ([string]$o.change -ne $change) { continue }
    $ev = [string]$o.event
    if ($ev -ne 'gate' -and $ev -ne 'skip') { continue }
    $ts = if ($o.ts -is [datetime]) { $o.ts.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { [string]$o.ts }
    $rows.Add($ts + "`t" + 'G' + "`t" + [string]$o.phase + "`t" + ([string]$o.status).ToUpper() + "`t" + [string]$o.note)
  }
}
if ($haveRef) {
  $env:TZ = 'UTC'
  $log = git log "$base..$change" --date=format-local:'%Y-%m-%dT%H:%M:%SZ' --format='%cd%x09C%x09%h%x09%s' 2>$null
  foreach ($l in @($log)) { if ($l) { $rows.Add([string]$l) } }
}
$arr = $rows.ToArray()
[Array]::Sort($arr, [System.StringComparer]::Ordinal)

$out = New-Object System.Collections.Generic.List[string]
if ($arr.Count -eq 0) {
  Write-Output ("ss-trace: provenance for $change`n$SEP`nss-trace: no trace for $change")
  exit 0
}

$out.Add("ss-trace: provenance for $change")
$out.Add($SEP)
$out.Add('intent:')
$specs = @(Get-ChildItem -Path 'docs/specs' -Filter "*$slug*.md" -File -ErrorAction SilentlyContinue | ForEach-Object { 'docs/specs/' + $_.Name })
[Array]::Sort($specs, [System.StringComparer]::Ordinal)
if ($specs.Count -gt 0) { foreach ($s in $specs) { $out.Add('  ' + $s) } } else { $out.Add('  (no spec/plan docs found)') }
$out.Add($SEP)
$out.Add('lineage (gates + commits, chronological):')
$gates = 0; $commits = 0
foreach ($r in $arr) {
  $p = $r -split "`t"
  $t = $p[0].Substring(5,5) + ' ' + $p[0].Substring(11,5)
  if ($p[1] -eq 'G') {
    $out.Add( ('  {0}  {1,-8} {2,-5} {3}' -f $t, $p[2], $p[3], $p[4]).TrimEnd() )
    $gates++
  } else {
    $out.Add( ('  {0}  {1,-8} {2}  {3}' -f $t, '*', $p[2], $p[3]) )
    $commits++
  }
}
if (-not $haveRef) { $out.Add("  (branch '$change' not found; git commits omitted)") }
$out.Add($SEP)
$files = 0; $head = 'n/a'
if ($haveRef) {
  $files = @(git diff --name-only "$base..$change" 2>$null | Where-Object { $_ -ne '' }).Count
  $h = "$(git rev-parse --short $change 2>$null)".Trim()
  if ($h) { $head = $h }
}
$out.Add("origin: $change   gates: $gates   commits: $commits   files: $files   head: $head")
Write-Output ($out -join "`n")
exit 0
