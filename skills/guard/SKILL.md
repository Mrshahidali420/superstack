---
name: ss-guard
description: Use before or during risky work to stay safe. Warns before destructive commands (rm -rf, force-push, DROP TABLE, hard reset) and can lock edits to a single directory while debugging. Say "be careful" or "freeze to X" to activate.
---

# Guard — safety on demand

Two guardrails, activated on request.

## Careful

Before running any destructive or irreversible command — `rm -rf`, `git push --force`,
`git reset --hard`, `DROP` / `TRUNCATE`, mass deletes — **stop and show it for confirmation**,
naming what it destroys and whether it's reversible. Proceed only on an explicit yes.

## Freeze

When told to freeze to a directory, **restrict edits to that path** for the session. If a change
outside it seems needed, surface the request instead of making it — so unrelated code can't be
"helpfully" altered while you debug.

## Gate

No destructive command runs without confirmation; no edit lands outside the frozen path.

## Note

This is an agent-followed discipline, and SuperStack also ships a matching **enforcement hook**
(off by default): set `SUPERSTACK_GUARD=1` to hard-block destructive commands, and
`SUPERSTACK_FREEZE_DIR=<path>` to hard-block edits outside that directory. The skill and the hook
reinforce each other. See `docs/hooks.md`.

## Lineage

gstack `/careful`, `/freeze`, `/guard`.
