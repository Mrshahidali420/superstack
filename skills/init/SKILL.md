---
name: ss-init
description: Use once in a new project (after installing SuperStack) to make the loop ready - it writes a default .superstack/config, ensures .superstack/ is gitignored, and records a genesis ledger entry. Idempotent and safe to re-run.
---

# Init - bootstrap a project for the loop

Per-project setup. Run it once after the plugin is installed; it makes the loop work in this repo.
(`install.sh` is the global, per-agent install; `/ss-init` is the per-project runtime setup.)

## Steps

1. Run `scripts/ss-init` (PowerShell: `scripts/ss-init.ps1`). It is idempotent - safe to run again;
   it only creates what is missing.
2. It performs three create-if-missing actions and reports each:
   - **config** - writes `.superstack/config` with the tunable defaults (`mandatory_phases`,
     `evolve_threshold`). Use `--force` to reset an edited config back to defaults.
   - **gitignore** - adds `.superstack/` to the project's `.gitignore` once, so the runtime dir is
     not committed. Skipped outside a git repo.
   - **ledger** - writes a genesis entry so the ledger exists and the toolchain is proven.
3. Preview without writing using `--dry-run`. When it reports `ready`, start the loop with `/ss-frame`.

## Note

`/ss-init` never installs skills (that is `install.sh`) and never verifies your setup (that is
the planned /ss-doctor). It only prepares this project's `.superstack/` runtime.

## Lineage

Original to SuperStack - the per-project counterpart to the global `install.sh`.
