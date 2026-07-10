---
name: ss-panel
description: Use to see one change's whole story in a single view - /ss-panel composes the shareable summary (report), the chronological timeline (replay), and the spec-to-commit provenance (trace) for one ledger run, with the change resolved once so all three legs agree. Read-only; --save writes a fenced markdown panel.
---

# Panel - the whole run in one view

Understanding one change used to take three commands read in the right order: [[ss-report]]
(the summary), [[ss-replay]] (the story), [[ss-trace]] (the provenance) - and each resolved its
own default run. `/ss-panel` is a thin composer: it resolves the change **once** (latest ledger
entry, or the argument you pass) and runs the three legs verbatim in reading order.

## Steps

1. Run `scripts/ss-panel [change]` (PowerShell: `scripts/ss-panel.ps1`). No argument = the
   latest run in the ledger.
2. Read top to bottom: **report** (what shipped and how), **replay** (the timeline with
   elapsed minutes and gate outcomes), **trace** (spec docs -> ledger gates -> commits).
3. `--save` writes the whole panel to `.superstack/replays/panel-<change>.md` for sharing.

## Note

Read-only - it never writes the ledger. A leg that cannot run here (e.g. trace outside a git
repo) reports itself unavailable and the panel continues. Cross-run analytics stay in
[[ss-stats]]; the panel is one change deep, not many wide. Requires `jq` (exit 2 without it,
same as trace/stats).

## Lineage

Original to SuperStack - the unified dashboard promised on the roadmap, closing the insight
suite: report + replay + trace composed over the same Loop Ledger they already read.
