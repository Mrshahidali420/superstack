#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Standing-context budget cockpit (read-only). Front 1 of the context all-rounder.
param([string]$Budget='8000', [switch]$Check, [Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)
$ErrorActionPreference = 'Stop'
if ($Rest -and $Rest.Count -gt 0) { [Console]::Error.WriteLine("ss-context: unknown flag '$($Rest -join ' ')' (usage: ss-context [--budget N] [--check])"); exit 1 }
if ($Budget -notmatch '^[0-9]+$' -or [int]$Budget -lt 1) { [Console]::Error.WriteLine("ss-context: --budget must be a positive integer"); exit 1 }
$budget = [int]$Budget

$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
if ($dir -match '^/[a-zA-Z]/') { try { $dir = (& cygpath -w $dir 2>$null).Trim() } catch {} }
$homeDir = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }

function FBytes($p) { if (Test-Path -LiteralPath $p -PathType Leaf) { (Get-Item -LiteralPath $p).Length } else { 0 } }
$rows = New-Object System.Collections.Generic.List[object]
$total = 0
function AddRow($name, $file) {
  $b = [int](FBytes $file); if ($b -le 0) { return }
  $t = [math]::Floor($b / 4); $script:total += $t
  $script:rows.Add([pscustomobject]@{ n=$name; b=$b; t=$t })
}
AddRow 'CLAUDE.md' 'CLAUDE.md'; AddRow 'AGENTS.md' 'AGENTS.md'; AddRow 'STATE.md' 'STATE.md'; AddRow 'CONTEXT.md' 'CONTEXT.md'
$skBytes = 0; $skCount = 0
if (Test-Path 'skills' -PathType Container) {
  foreach ($f in (Get-ChildItem -Path 'skills' -Filter 'SKILL.md' -Recurse -File -ErrorAction SilentlyContinue)) {
    $line = (Get-Content -LiteralPath $f.FullName | Where-Object { $_ -match '^description:' } | Select-Object -First 1)
    if ($null -ne $line) { $d = ($line -replace '^description:[ ]*',''); $skCount++; $skBytes += [System.Text.Encoding]::UTF8.GetByteCount($d) }
  }
}
if ($skCount -gt 0) { $skT = [math]::Floor($skBytes / 4); $total += $skT; $rows.Add([pscustomobject]@{ n="skill descs ($skCount)"; b=$skBytes; t=$skT }) }

$pct = [int][math]::Floor((100*$total + [math]::Floor($budget/2)) / $budget)
$verdict = if ($pct -lt 60) { 'OK' } elseif ($pct -le 100) { 'WARN' } else { 'OVER' }

$flags = New-Object System.Collections.Generic.List[string]
$cb = [int](FBytes 'CLAUDE.md'); if ($cb -gt 16384) { $flags.Add("  ! CLAUDE.md $cb bytes - trim to stable instructions (it is never evicted)") }
foreach ($sf in @('STATE.md','CONTEXT.md')) { $sb=[int](FBytes $sf); if ($sb -gt 8192) { $flags.Add("  ! $sf $sb bytes - compact via /ss-learn") } }
$ledger = Join-Path $dir 'ledger.jsonl'
if (Test-Path -LiteralPath $ledger -PathType Leaf) { $ll = @(Get-Content -LiteralPath $ledger).Count; if ($ll -gt 1000) { $flags.Add("  ! ledger.jsonl $ll lines - archive old entries") } }
$rpf = 0; foreach ($d2 in @((Join-Path $dir 'replays'), (Join-Path $dir 'proposals'))) { if (Test-Path $d2 -PathType Container) { $rpf += @(Get-ChildItem -Path $d2 -Recurse -File -ErrorAction SilentlyContinue).Count } }
if ($rpf -gt 50) { $flags.Add("  ! replays/+proposals/ $rpf files - archive") }

function Detect($nativeScript, $cfgName) {
  if (Test-Path -LiteralPath $nativeScript -PathType Leaf) { return @('detected', "$([System.IO.Path]::GetFileName($nativeScript)) (native)") }
  foreach ($c in @('.mcp.json', (Join-Path $homeDir '.claude.json'))) {
    if ((Test-Path -LiteralPath $c -PathType Leaf) -and (Select-String -LiteralPath $c -SimpleMatch $cfgName -CaseSensitive -Quiet)) { return @('detected', "$cfgName (mcp)") }
  }
  return @($null, $null)
}
$rt = Detect 'scripts/ss-ctx' 'context-mode'
$rtDet = if ($rt[0]) { 'detected' } else { 'not detected' }; $rtHint = if ($rt[1]) { $rt[1] } else { 'front 2 (ss-ctx) or install context-mode' }
$cx = Detect 'scripts/ss-munch' 'jcodemunch'
$cxDet = if ($cx[0]) { 'detected' } else { 'not detected' }; $cxHint = if ($cx[1]) { $cx[1] } else { 'front 3 (ss-munch) or install jcodemunch' }

if ($Check) {
  if ($pct -ge 60) {
    $rec = if ($flags.Count -gt 0) { ($flags[0] -replace '^.* - ','') } else { 'review /ss-context' }
    Write-Output "[ss-context] standing context ~$total tok = $pct% of $budget budget - $rec (run /ss-context)"
  }
  exit 0
}

$SEP = '-' * 54
$out = New-Object System.Collections.Generic.List[string]
$out.Add('ss-context: standing context budget'); $out.Add($SEP)
$out.Add(('{0,-18}{1,-8}{2}' -f 'artifact','bytes','~tokens'))
foreach ($r in $rows) { $out.Add(('{0,-18}{1,-8}{2}' -f $r.n, $r.b, $r.t)) }
$out.Add($SEP)
$out.Add("session-start: ~$total tokens / $budget budget ($pct%)   $verdict")
$out.Add($SEP)
$out.Add('context stack:')
$out.Add(('  {0,-18} {1,-13} {2}' -f 'runtime sandbox', $rtDet, $rtHint))
$out.Add(('  {0,-18} {1,-13} {2}' -f 'code exploration', $cxDet, $cxHint))
$out.Add($SEP)
$out.Add('flags:')
if ($flags.Count -gt 0) { foreach ($fl in $flags) { $out.Add($fl) } } else { $out.Add('  (none)') }
$out.Add("verdict: $verdict   (warn >=60%, over >100%)")
Write-Output ($out -join "`n")
if ($verdict -eq 'OVER') { exit 1 } else { exit 0 }
