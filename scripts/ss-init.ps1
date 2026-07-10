#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Bootstrap a project's SuperStack runtime (config, gitignore, genesis ledger entry,
# context-routing doctrine). Idempotent.
# Usage: ss-init.ps1 [-Force] [-DryRun] [-NoRouting]
param([switch]$Force, [switch]$DryRun, [switch]$NoRouting)
$ErrorActionPreference = 'Stop'
$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
if ($dir -match '^/[a-zA-Z]/') { try { $dir = (& cygpath -w $dir 2>$null).Trim() } catch {} }
$config = Join-Path $dir 'config'
$ledger = Join-Path $dir 'ledger.jsonl'

$body = @(
  '# SuperStack project config (key=value). Delete a line to use the built-in default.'
  'mandatory_phases=review,secure'
  'evolve_threshold=3'
) -join "`n"

$wrote = $false

# config
if (-not (Test-Path $config)) {
  if ($DryRun) { $cfg = '[dry-run] would create .superstack/config' }
  else { New-Item -ItemType Directory -Force -Path $dir | Out-Null; Set-Content -Path $config -Value $body -Encoding utf8; $cfg = 'created (.superstack/config)'; $wrote = $true }
} elseif ($Force) {
  if ($DryRun) { $cfg = '[dry-run] would reset .superstack/config' }
  else { Set-Content -Path $config -Value $body -Encoding utf8; $cfg = 'reset (.superstack/config)'; $wrote = $true }
} else {
  $cfg = 'already present (use --force to reset)'
}

# gitignore
$root = (git rev-parse --show-toplevel 2>$null)
if (-not $root) {
  $gi = 'skipped (not a git repo)'
} else {
  $gif = Join-Path $root '.gitignore'
  $ignored = (Test-Path $gif) -and (@(Get-Content $gif) | Where-Object { $_ -eq '.superstack/' -or $_ -eq '.superstack' }).Count -gt 0
  if ($ignored) { $gi = 'already ignored' }
  elseif ($DryRun) { $gi = '[dry-run] would add .superstack/ to .gitignore' }
  else {
    $pre = if ((Test-Path $gif) -and (Get-Item $gif).Length -gt 0 -and -not ((Get-Content -Raw $gif).EndsWith("`n"))) { "`n" } else { '' }
    Add-Content -Path $gif -Value ($pre + '.superstack/')
    $gi = 'added .superstack/ to .gitignore'; $wrote = $true
  }
}

# ledger genesis
if (-not (Test-Path $ledger)) {
  if ($DryRun) { $lg = '[dry-run] would write a genesis entry' }
  else {
    $sib = Join-Path $PSScriptRoot 'ledger.ps1'
    if (Test-Path $sib) { & $sib init note na 'superstack loop initialized' *>$null; $lg = 'created (genesis entry)'; $wrote = $true }
    else { $lg = 'skipped (ledger script missing)' }
  }
} else { $lg = 'already present' }

# routing doctrine - single source: templates/context-routing.md, installed into
# ./CLAUDE.md between markers. LF-only writes via [IO.File] (byte-parity with bash);
# paths anchored to Get-Location because .NET does not track the pwsh location.
$tpl = Join-Path $PSScriptRoot '..' 'templates' 'context-routing.md'
$claude = Join-Path (Get-Location).Path 'CLAUDE.md'
$m1 = '<!-- superstack:context-routing -->'
$m2 = '<!-- /superstack:context-routing -->'
if ($NoRouting) { $rt = 'skipped (--no-routing)' }
elseif (-not (Test-Path -LiteralPath $tpl -PathType Leaf)) { $rt = 'skipped (template missing)' }
else {
  $block = ([IO.File]::ReadAllText($tpl) -replace "`r`n", "`n").TrimEnd("`n")
  $raw = $null; $cur = $null; $i1 = -1; $i2 = -1
  if (Test-Path -LiteralPath $claude -PathType Leaf) {
    $raw = [IO.File]::ReadAllText($claude)
    $i1 = $raw.IndexOf($m1, [StringComparison]::Ordinal)
    if ($i1 -ge 0) {
      $i2 = $raw.IndexOf($m2, [StringComparison]::Ordinal)
      if ($i2 -gt $i1) { $cur = $raw.Substring($i1, $i2 + $m2.Length - $i1) }
    }
  }
  $curLf = if ($null -ne $cur) { $cur -replace "`r`n", "`n" } else { $null }
  if ($curLf -ceq $block) { $rt = 'already current' }
  elseif ($DryRun) { $rt = '[dry-run] would install the routing block into CLAUDE.md' }
  elseif ($null -ne $cur) {
    [IO.File]::WriteAllText($claude, ($raw.Substring(0, $i1) + $block + $raw.Substring($i2 + $m2.Length)))
    $rt = 'updated (CLAUDE.md)'; $wrote = $true
  }
  elseif ($null -ne $raw -and $raw.Length -gt 0) {
    $sep = if ($raw.EndsWith("`n")) { "`n" } else { "`n`n" }
    [IO.File]::WriteAllText($claude, ($raw + $sep + $block + "`n"))
    $rt = 'installed (CLAUDE.md)'; $wrote = $true
  }
  else {
    [IO.File]::WriteAllText($claude, ($block + "`n"))
    $rt = 'installed (CLAUDE.md)'; $wrote = $true
  }
}

# report
$lines = @(
  'ss-init: SuperStack project setup (.superstack/)'
  ('  {0,-10} {1}' -f 'config:', $cfg)
  ('  {0,-10} {1}' -f 'gitignore:', $gi)
  ('  {0,-10} {1}' -f 'ledger:', $lg)
  ('  {0,-10} {1}' -f 'routing:', $rt)
)
if ($DryRun) { $lines += '[dry-run] no changes written.' }
elseif ($wrote) { $lines += 'ready - run /ss-frame to start the loop (see CLAUDE.md).' }
else { $lines += 'already initialized.' }
Write-Output ($lines -join "`n")
