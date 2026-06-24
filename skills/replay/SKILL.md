---
name: ss-replay
description: Use to see the story of a loop run — replays the ledger as a chronological timeline (each phase entered, every gate pass/fail, retries, skips, with elapsed time) so you can review or share what actually happened, end to end.
---

# Replay - the story of a run

The third leg of the proof trio: `/ss-audit` is the gate, `/ss-report` is the stats,
`/ss-replay` is the **story** — what happened, in order.

## Steps

1. Run `scripts/ss-replay` to replay the latest run (the most recent `change` in the ledger),
   or `scripts/ss-replay <branch>` to replay a specific one.
2. Read the timeline top to bottom: elapsed time (`+Nm` from the start), the phase, the event,
   a `PASS`/`FAIL`/`SKIP` marker, and the note. A `(retry)` tag marks a gate that passed only
   after an earlier failure — the friction worth noticing.
3. Check the footer stats: `phases`, `gate-retries`, `skips`, `open-fails` (a phase whose last
   gate still failed), and total elapsed.
4. To share it, run `scripts/ss-replay <branch> --save` — it writes a fenced Markdown file to
   `.superstack/replays/<branch>.md` you can drop into a PR or postmortem.

## Note

Read-only: replay never changes code or the ledger. It complements `/ss-report` (which
aggregates) by showing the actual sequence. PowerShell users: `scripts/ss-replay.ps1`.

## Lineage

Original to SuperStack - powered by the Loop Ledger that `/ss-audit` and `/ss-report` also read.
