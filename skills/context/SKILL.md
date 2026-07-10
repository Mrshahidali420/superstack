---
name: ss-context
description: Use to keep your standing (always-loaded) context lean - /ss-context audits the on-disk footprint (CLAUDE.md, STATE.md/CONTEXT.md, skill descriptions) against a token budget, flags bloat, and detects the rest of your context stack. It also runs automatically at session start, warning only when you are over budget. Front 1 of SuperStack's context all-rounder.
---

# Context - is my standing context lean?

`/ss-context` watches the **standing context** - the always-loaded files that are never evicted from
the window (CLAUDE.md especially). It estimates their token footprint (bytes/4) against a budget,
flags bloat, and detects the other context fronts (runtime sandbox, code exploration, routing doctrine). It is
read-only - it recommends, it never deletes. It also runs **automatically** in the SessionStart hook,
emitting a one-line advisory only when you are over budget.

## Steps

1. It runs on its own at session start; to inspect on demand run `scripts/ss-context`
   (PowerShell: `scripts/ss-context.ps1`). `--budget N` sets the token budget (default 8000).
2. Read the budget line: `OK` (<60%), `WARN` (60-100%), `OVER` (>100%, exits 1 for CI).
3. Read the `context stack` rows - are the runtime sandbox, code exploration, and routing doctrine
   wired? A missing routing row means [[ss-init]] has not installed the block into CLAUDE.md yet.
4. Act on the flags / the advisory (below).

## Note - the autopilot playbook

When the advisory or the report says WARN/OVER, apply the levers (smaller curated context beats brute
force):
- `/compact` proactively at ~50% fill and at phase boundaries (a healthy session summarises better);
  `/clear` when switching tasks.
- Offload verbose research/reading to fresh-context subagents (the loop already does this per phase).
- Trim `CLAUDE.md` to stable instructions (it is never evicted); compact `STATE.md`/`CONTEXT.md` via
  [[ss-learn]]; archive a huge ledger.
- **Routing doctrine:** prefer the runtime sandbox (Front 2 `ss-ctx`, or context-mode) for verbose tool
  output, and the code-exploration tool (Front 3 `ss-munch`, or jcodemunch) over brute-reading files;
  fall back to Read/Grep when neither is present. [[ss-init]] installs this doctrine into the project's
  CLAUDE.md as a marker-delimited block (Front 4), so it stands in every session.
- **Right-size (Plan):** keep each planned task within one context window; split before starting if not.

## Lineage

Original to SuperStack - Front 1 of the context all-rounder (standing context). Complements [[ss-doctor]]
(dependency/config health, not size) and composes with the runtime/exploration tools rather than
replacing them.
