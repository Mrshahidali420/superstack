#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Bootstrap a project's SuperStack runtime (config, gitignore, genesis ledger entry). Idempotent.
# Usage: ss-init.ps1 [-Force] [-DryRun]
param([switch]$Force, [switch]$DryRun)
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

# report
$lines = @(
  'ss-init: SuperStack project setup (.superstack/)'
  ('  {0,-10} {1}' -f 'config:', $cfg)
  ('  {0,-10} {1}' -f 'gitignore:', $gi)
  ('  {0,-10} {1}' -f 'ledger:', $lg)
)
if ($DryRun) { $lines += '[dry-run] no changes written.' }
elseif ($wrote) { $lines += 'ready - run /ss-frame to start the loop (see CLAUDE.md).' }
else { $lines += 'already initialized.' }
Write-Output ($lines -join "`n")
