#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# ss-ctx: read-only access to the PostToolUse shrink store (.superstack/ctx). Front 2a.
# bash twin uses `prune --keep N`; PowerShell intercepts `--keep` as a param name, so the ps1 takes a
# native `-Keep N` (the project's bash `--flag` <-> ps1 `-Flag` convention). Output stays byte-identical.
param([Parameter(Position=0)][string]$Cmd='', [Parameter(Position=1)][string]$A1='', [int]$Keep=50)
$ErrorActionPreference = 'Stop'
$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
if ($dir -match '^/[a-zA-Z]/') { try { $dir = (& cygpath -w $dir 2>$null).Trim() } catch {} }
$store = Join-Path $dir 'ctx'
function San($s) { ($s -replace '[^A-Za-z0-9_-]','_') }
function Entries { Get-ChildItem -LiteralPath $store -Filter '*.txt' -File -ErrorAction SilentlyContinue }

# Ordinal byte-order comparison — mirrors bash LC_ALL=C sort.
# Compares two strings by their raw UTF-8/ASCII byte values (uppercase < lowercase).
function OrdinalCompare([string]$a, [string]$b) {
  $ba = [System.Text.Encoding]::UTF8.GetBytes($a)
  $bb = [System.Text.Encoding]::UTF8.GetBytes($b)
  $len = [Math]::Min($ba.Length, $bb.Length)
  for ($i = 0; $i -lt $len; $i++) {
    if ($ba[$i] -ne $bb[$i]) { return [int]$ba[$i] - [int]$bb[$i] }
  }
  return $ba.Length - $bb.Length
}

# Sort FileInfo items: newest mtime first (epoch desc), then ordinal basename asc on ties.
function SortRowsOrdinal($items) {
  $arr = @($items)
  if ($arr.Count -le 1) { return $arr }
  # Build sortable records
  $records = $arr | ForEach-Object {
    $epoch = [long]([datetimeoffset]$_.LastWriteTimeUtc).ToUnixTimeSeconds()
    [pscustomobject]@{ Epoch = $epoch; Name = $_.BaseName; Item = $_ }
  }
  # Group by epoch
  $groups = @{}
  foreach ($r in $records) {
    if (-not $groups.ContainsKey($r.Epoch)) { $groups[$r.Epoch] = [System.Collections.Generic.List[pscustomobject]]::new() }
    $groups[$r.Epoch].Add($r)
  }
  # Sort epochs descending
  $epochs = @($groups.Keys | Sort-Object -Descending)
  $result = [System.Collections.Generic.List[object]]::new()
  foreach ($ep in $epochs) {
    $grp = @($groups[$ep])
    if ($grp.Count -gt 1) {
      # Ordinal sort within tie group using byte comparison
      $sorted = $grp | Sort-Object -Property @{Expression={
          [System.Text.Encoding]::UTF8.GetBytes($_.Name) | ForEach-Object { $_.ToString('X2') } | Join-String
        }; Ascending=$true }
      foreach ($s in $sorted) { $result.Add($s.Item) }
    } else {
      $result.Add($grp[0].Item)
    }
  }
  return $result.ToArray()
}

# Ordinal sort of FileInfo entries by BaseName — for search file iteration order.
function SortEntriesOrdinal($items) {
  $arr = @($items)
  if ($arr.Count -le 1) { return $arr }
  $arr | Sort-Object -Property @{Expression={
    [System.Text.Encoding]::UTF8.GetBytes($_.BaseName) | ForEach-Object { $_.ToString('X2') } | Join-String
  }; Ascending=$true }
}

switch ($Cmd) {
  'list' {
    if (-not (Test-Path -LiteralPath $store -PathType Container)) { Write-Output "ss-ctx: store empty ($store)"; exit 0 }
    $items = @(Entries); if ($items.Count -eq 0) { Write-Output "ss-ctx: store empty ($store)"; exit 0 }
    $sorted = @(SortRowsOrdinal $items)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($f in $sorted) {
      # Gotcha 1: left-justified 12-wide bytes field, one space, id — matches bash printf '%-12s %s\n'
      $out.Add(('{0,-12} {1}' -f $f.Length, $f.BaseName))
    }
    Write-Output ($out -join "`n")
  }
  'show' {
    $id = San $A1
    if (-not $A1 -or -not $id) { [Console]::Error.WriteLine('ss-ctx: show needs an id'); exit 2 }
    $f = Join-Path $store "$id.txt"
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { [Console]::Error.WriteLine("ss-ctx: no entry '$id'"); exit 1 }
    # Gotcha 4: byte-exact — ReadAllText + Out.Write, no extra newline
    [Console]::Out.Write([System.IO.File]::ReadAllText($f))
  }
  'search' {
    $term = $A1
    if (-not $term) { [Console]::Error.WriteLine('ss-ctx: search needs a term'); exit 2 }
    if (-not (Test-Path -LiteralPath $store -PathType Container)) { Write-Output "ss-ctx: no matches for '$term'"; exit 0 }
    $hit = $false
    $out = New-Object System.Collections.Generic.List[string]
    # Gotcha 2+3: ordinal file order; emit '<id>: <line>' directly, ordinal substring match
    foreach ($f in (SortEntriesOrdinal @(Entries))) {
      foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        if ($line.IndexOf($term, [System.StringComparison]::Ordinal) -ge 0) {
          $hit = $true
          $out.Add(('{0}: {1}' -f $f.BaseName, $line))
        }
      }
    }
    # Gotcha 5: no-match to stdout, exit 0
    if ($hit) { Write-Output ($out -join "`n") } else { Write-Output "ss-ctx: no matches for '$term'" }
  }
  'prune' {
    $keep = $Keep   # native -Keep int param (default 50); mirrors bash `prune [--keep N]`
    if (-not (Test-Path -LiteralPath $store -PathType Container)) { Write-Output 'ss-ctx: store empty'; exit 0 }
    $i = 0
    foreach ($f in (SortRowsOrdinal @(Entries))) { $i++; if ($i -gt $keep) { Remove-Item -LiteralPath $f.FullName -Force } }
    Write-Output "ss-ctx: kept up to $keep newest"
  }
  default { [Console]::Error.WriteLine('usage: ss-ctx {list | show <id> | search <term> | prune [--keep N]}'); exit 2 }
}
