---
name: ss-report
description: Use after shipping (or any time) to generate a shareable Markdown summary of how a change was built — phases run, skip reasons, timing, and change size — from the loop ledger and git.
---

# Report — shareable proof of work

Turns the loop ledger into a copy-pasteable summary you can drop in a PR, a changelog, or a post.

## Steps

1. Run `scripts/ss-report` (optionally pass a branch name, or `--save` to also write
   `.superstack/run-report-<change>.md`). It reads the ledger for the current change plus git
   diff stats and prints a Markdown block.
2. Paste the block where it's useful — the PR description, release notes, or a status update.
   It pairs naturally with the `/ss-ship` attestation.

## Note

The report never gates anything; it's read-only. With no ledger yet, it still reports the git
change size and an empty phase line — it degrades gracefully.

## Lineage

Original to SuperStack — powered by the Loop Ledger ([[ss-audit]]).
