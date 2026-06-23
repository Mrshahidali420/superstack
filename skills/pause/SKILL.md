---
name: ss-pause
description: Use when stopping work mid-task so the next session — you or someone else — can resume cleanly. Writes an honest handoff into STATE.md and CONTEXT.md instead of leaving state only in your head.
---

# Pause — clean handoff

## Steps

1. **Update `STATE.md`** — exactly where you stopped, the very next step, and anything
   in-progress or uncommitted.
2. **Capture fresh `CONTEXT.md` entries** — decisions made this session and any gotcha discovered.
3. **Leave the tree sane** — commit, or clearly note uncommitted work. Never leave a half-broken
   build without saying so in `STATE.md`.
4. **Note the open question** (if any) the next session must answer first.

## Gate

A cold reader could run [[ss-resume]] and continue without asking you anything.

## Lineage

GSD `pause-work` (context handoff).
