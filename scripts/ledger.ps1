#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Append a validated entry to .superstack/ledger.jsonl. Usage: ledger.ps1 <phase> <event> [status] [note]
param([string]$Phase, [string]$Event, [string]$Status = "na", [string]$Note = "")
$ErrorActionPreference = 'Stop'
if (-not $Phase -or -not $Event) { Write-Error "usage: ledger.ps1 <phase> <event> [status] [note]"; exit 1 }
if ($Event  -notin 'enter','gate','skip','note') { Write-Error "invalid event '$Event'";  exit 1 }
if ($Status -notin 'pass','fail','skip','na')     { Write-Error "invalid status '$Status'"; exit 1 }
$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
$ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$change = "$(git branch --show-current 2>$null)".Trim(); if (-not $change) { $change = 'default' }
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$obj = [ordered]@{ ts = $ts; change = $change; phase = $Phase; event = $Event; status = $Status; note = $Note }
($obj | ConvertTo-Json -Compress) | Add-Content -Path (Join-Path $dir 'ledger.jsonl')
