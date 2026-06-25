---
name: ss-trace
description: Use to see one change's provenance - a read-only 'birth certificate' that joins its spec/plan docs (intent), its ledger gate/skip events, and its actual git commits into one chronological lineage, plus an origin footer (gates, commits, files, head SHA). Distinct from /ss-replay (ledger-only timeline) and /ss-report (run stats).
---

# Trace - where did this change come from?

Read-only change provenance. For one change (branch), `/ss-trace` joins the three things the loop
already records - the spec/plan docs (intent), the ledger gate/skip events (the review trail), and the
git commits (the output) - into a single chronological lineage. It surfaces the trail the loop left;
it builds no new data and passes no judgement (after SLSA's "build provenance" idea: a birth
certificate answering *where did this come from*).

## Steps

1. Run `scripts/ss-trace` (PowerShell: `scripts/ss-trace.ps1`). Optional args:
   - `<change>` (`-Change`) - the branch / ledger change to trace. Default: the current branch.
   - `base` (`-Base`) - the commit-range base (default `main`, falling back to `master`).
2. Read the `intent:` block - the `docs/specs/` design/plan docs matched to the change.
3. Read the `lineage` - ledger gate/skip events (`PHASE STATUS note`) interleaved by time with the git
   commits (marked `*`, `sha subject`).
4. Read the `origin:` footer - gates, commits, files changed, and the head SHA.

## Note

`/ss-trace` is read-only and never a gate. It degrades gracefully: a merged/deleted branch shows
ledger-only lineage with a note; an unknown change prints `no trace`. It does NOT verify the loop ran
(that is [[ss-audit]]) or diff the plan's files (that is [[ss-drift]]).

## Lineage

Original to SuperStack - the provenance view that joins intent ([[ss-frame]] specs), the gate trail
([[ss-audit]]), and commits. Complements [[ss-replay]] (ledger-only timeline) and [[ss-report]]
(run stats) by being the one command that links the ledger to git and the specs.
