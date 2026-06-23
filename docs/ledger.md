# The Loop Ledger

SuperStack records its loop's execution to `.superstack/ledger.jsonl` (runtime, gitignored). Each
phase appends its gate outcome via the `ledger` helper:

    ledger <phase> <event> [status] [note]    # e.g. ledger review gate pass "no critical"

`ss-audit` reads the ledger and verifies the mandatory phases (`.superstack/config` →
`mandatory_phases`, default `review,secure`) each have a passing gate or an explicit
skip-with-reason. `/ss-ship` runs it as its first gate and attaches the attestation
(`ss-audit --attest`) to the PR — the durable, shareable proof of how the change was built.

**Hard enforcement (opt-in):** set `SUPERSTACK_AUDIT=1` and the audit hook blocks
`git push` / `gh pr create` until the process is complete.
