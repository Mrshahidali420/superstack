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

## Run report

`/ss-report` (`scripts/ss-report`, + PowerShell twin) turns the ledger into a copy-pasteable
Markdown summary — phases run, skip reasons, elapsed time, and change size (commits/files/±/test
files) — for a PR, release notes, or a status update. It's read-only and never gates; with no
ledger it still reports the git change size. `--save` writes `.superstack/run-report-<change>.md`.

## Evolve

`/ss-evolve` (`scripts/ss-evolve`, + PowerShell twin) turns accumulated ledger signal into
improvement. It detects recurring patterns (a phase skipped >= a threshold, a gate that
repeatedly fails) and either auto-applies a low-risk `CONTEXT.md` insight as a revertable
`chore(evolve):` commit, or — for a brand-new skill — drafts it to `.superstack/proposals/`
for your review. Deduped via `.superstack/evolve-state`; threshold via `.superstack/config`
`evolve_threshold` (default 3); `--dry-run` previews. New skills never auto-commit.
