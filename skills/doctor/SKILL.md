---
name: ss-doctor
description: Use to verify a project's SuperStack setup is healthy - it checks jq, git, the .superstack/config, gitignore, and the ledger, printing a pass/warn/fail checklist with an actionable fix for each problem. Read-only; the verify counterpart to /ss-init.
---

# Doctor - verify a project's loop setup

Read-only health check. Run it to confirm this project's `.superstack/` runtime is sound, or to
diagnose why a loop command is misbehaving. It never changes anything - it tells you what to fix.

## Steps

1. Run `scripts/ss-doctor` (PowerShell: `scripts/ss-doctor.ps1`). No arguments.
2. Read the checklist - each line is `[OK]`, `[WARN]`, or `[FAIL]` with a one-line detail and, for
   anything not OK, the exact fix (usually `run /ss-init`):
   - **jq** - required by audit/report/replay/evolve (`[FAIL]` if missing).
   - **git** - repo + branch detection (`[WARN]` outside a repo; the loop still runs).
   - **config** - `.superstack/config` present with valid `mandatory_phases` / `evolve_threshold`.
   - **gitignore** - `.superstack/` is ignored so the runtime dir is not committed.
   - **ledger** - `.superstack/ledger.jsonl` is present and every line is well-formed.
3. Act on the footer verdict: `HEALTHY` (exit 0), `WARNINGS` (exit 0, advisory), or `PROBLEMS`
   (exit 1 - safe to use as a CI preflight gate).

## Note

`/ss-doctor` only diagnoses; it does not repair. The fix for a missing config/gitignore/ledger is
[[ss-init]] (idempotent). Doctor validates the ledger without `jq`, so it still works while telling
you `jq` is missing.

## Lineage

Original to SuperStack - the verify leg of the adoption track ([[ss-init]] sets up, ss-doctor verifies).
