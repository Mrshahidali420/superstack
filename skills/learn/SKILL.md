---
name: ss-learn
description: Use at the end of a task or session. Persists discovered patterns, decisions, and gotchas to durable state files and memory so the next session resumes smart instead of cold.
---

# Learn

The eighth phase. Make the work compound — what you learned this session should be
available, automatically, the next time.

## Steps

1. **Update `STATE.md`** — what is done and what is next. A cold session should be able
   to pick up from here.
2. **Update `CONTEXT.md`** — decisions made and why, conventions discovered, and gotchas
   ("X must be updated whenever Y changes"). This is the project's long-term memory.
3. **Promote auto-loading conventions** — when you discover a rule future sessions must
   follow, add it to the project's `AGENTS.md` / `CLAUDE.md` so it loads without being asked.
4. **Prune.** Keep these files lean and durable — they are memory, not a journal. Delete
   notes that are stale or no longer true.

## Gate

A brand-new session, reading only these artifacts, could resume the work correctly.

Record the outcome: `ledger learn gate pass` — or `ledger learn skip skip "<reason>"` if you deliberately skipped this phase.

## Lineage

gstack `/learn` + GSD `STATE.md` / `CONTEXT.md` + Ralph's append-only progress log.
