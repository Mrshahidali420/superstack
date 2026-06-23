---
name: ss-audit
description: Use before shipping, or any time you want to confirm the loop actually ran, to verify every mandatory phase cleared its gate. Reads the loop ledger and reports a COMPLETE/INCOMPLETE verdict.
---

# Audit — proof of process

Verifies the loop was actually followed for this change, using the ledger the phases recorded.

## Steps

1. Run `scripts/ss-audit` (it reads `.superstack/ledger.jsonl` for the current branch and the
   mandatory phases from `.superstack/config`, default `review,secure`).
2. If the verdict is INCOMPLETE, do not paper over it — either run the missing phase now, or
   record an explicit skip with a reason: `ledger <phase> skip skip "<why>"`.
3. Re-run until COMPLETE. `scripts/ss-audit --attest` prints the one-line attestation for the PR.

## Gate

`ss-audit` reports COMPLETE for this change. Record the outcome: `ledger audit gate pass`.

## Lineage

Original to SuperStack — enabled by the explicit gated loop and the Loop Ledger.
