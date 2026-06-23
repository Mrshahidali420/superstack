---
name: ss-resume
description: Use at the start of a session to pick up work from a previous one. Reconstructs context from STATE.md, CONTEXT.md, git history, and any handoff note so you continue correctly instead of starting cold.
---

# Resume — restore context

## Steps

1. **Read `STATE.md`** — what's done, what's next, what's blocked.
2. **Read `CONTEXT.md`** — decisions, conventions, and gotchas that still apply.
3. **Scan recent git** (`git log --oneline -20`) and any open branch/PR for the real latest state.
4. **Reconcile.** If the notes and the code disagree, trust the code and fix the notes.
5. **State the plan** for this session before acting.

## Gate

You can accurately say what was done, what's next, and why — without re-deriving it from scratch.
Then re-enter the loop at the right phase.

## Lineage

GSD `resume-work` + the context-engineering layer ([[ss-pause]] writes what this reads).
