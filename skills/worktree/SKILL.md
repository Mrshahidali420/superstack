---
name: ss-worktree
description: Use before risky or parallel work to isolate it from your main checkout. Creates a git worktree on a new branch so experiments, big refactors, or parallel tasks can't disturb the working tree you depend on.
---

# Worktree — isolate the work

## Steps

1. **Branch + worktree:** `git worktree add ../<proj>-<task> -b <branch>` for an isolated
   checkout on a new branch.
2. **Set it up** — install deps and confirm a clean test baseline *before* changing anything,
   so any later failure is yours.
3. **Do the work there.** Parallel tasks each get their own worktree; they never collide.
4. **Finish** via `/ss-ship`, then remove it: `git worktree remove ../<proj>-<task>`.

## Gate

The main checkout is untouched; the work lives on its own branch with a clean baseline.

## Lineage

Superpowers `using-git-worktrees`.
