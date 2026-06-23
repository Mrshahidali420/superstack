# Shareable Run Report — Design

**Status:** Approved (2026-06-23)
**Feature:** Slate item #11. A copy-pasteable summary of *how* a change was built — phases run, timing, and change size — sourced from the Loop Ledger + git. A portfolio / PR / social artifact that makes the disciplined process visible.

## Problem

The Loop Ledger records that the loop ran, and `/ss-ship` attaches a one-line attestation to the PR. But there's no human-friendly, shareable summary — "built X through the full loop in ~3h, 11 commits, 5 test files touched." `/ss-report` produces that artifact on demand.

## Scope

**In:** a new `scripts/ss-report` (+ `.ps1`) and a `/ss-report` skill that read the ledger for the current change plus git diff stats, and print a Markdown block (optionally saved to a file). No changes to the phase skills.

**Non-goals (v1):**
- Rich per-phase counts that require phases to log new data (tests-added, review finding counts) — see "Forward compatibility."
- HTML, image, or README-badge output; auto-posting anywhere.
- Any gating: `/ss-report` never blocks; it only reports. Exit 0 except on a usage error.

## Data sources

1. **Ledger** — `${SUPERSTACK_DIR:-.superstack}/ledger.jsonl`, filtered to the current `change` (git branch, else `default`). Schema per line: `{ts, change, phase, event, status, note}`, `event ∈ enter|gate|skip|note`, `status ∈ pass|fail|skip|na`.
   - **Phases run** = distinct phases with a `gate` event (any status).
   - **Phases skipped** = phases with a `skip` event (and their `note` = reason).
   - **Elapsed** = last `ts` − first `ts` across the change's entries.
   - **Notes** = any `note` events, surfaced as `phase: <note>`.
2. **Git** (when inside a repo) — over `merge-base..HEAD` where merge-base = `git merge-base HEAD main` (fallback `master`; if neither, omit git stats):
   - commits = `git rev-list --count <mb>..HEAD`
   - files / insertions / deletions = parsed from `git diff --shortstat <mb>..HEAD`
   - test files touched = `git diff --name-only <mb>..HEAD` filtered by the regex `(^|/)(tests?|spec|__tests__)/|\.(test|spec)\.` , counted.
3. **Attestation** — the sibling `scripts/ss-audit --attest` line (DRY; located beside `ss-report`). If `ss-audit` is absent, the attestation line is omitted.

## CLI

```
ss-report [change] [--save]
```
- `change` — optional; defaults to the current git branch (else `default`).
- `--save` — also write the block to `${SUPERSTACK_DIR:-.superstack}/run-report-<change>.md` (with `/` in the change replaced by `-`). The block always prints to stdout regardless.
- Exit 0 normally; exit 1 only on an unknown flag / usage error.

## Output block

```
### 🏗️ SuperStack run — <change>
Built through the loop in <Xh Ym>.

`SuperStack process: frame OK plan OK build OK review OK qa OK secure OK ship OK`

- Phases: <N> run · <M> skipped
- Change: <C> commits · <F> files · +<A> / −<D> · <T> test files touched
- Skipped: secure (no IO), qa (no UI)
- Notes: review: 3 findings
```

Rules:
- Line 2 (elapsed): shown as `Built through the loop in <Xh Ym>.` when elapsed is computable; otherwise `Built through the loop.`
- The attestation backtick line is included only when `ss-audit` produced one.
- The `Change:` bullet appears only inside a git repo with a resolvable merge-base.
- The `Skipped:` bullet appears only if ≥1 phase was skipped.
- The `Notes:` bullet appears only if ≥1 `note` event exists.
- **Empty/partial ledger:** if no ledger entries exist for the change, the block still prints the heading and (if available) the git `Change:` bullet, with `- Phases: 0 run · 0 skipped` and no attestation. The report degrades gracefully; it never errors on a missing ledger.

## Cross-platform parity

`scripts/ss-report` (bash) and `scripts/ss-report.ps1` (PowerShell) produce the **identical** ledger-derived content (heading, attestation, phases, skipped, notes, and the git `Change:` bullet given the same repo). Both start with the shebang then `# SPDX-License-Identifier: MIT`.

**Elapsed (the one platform nuance):** bash parses `ts` via `date -u -d "<ts>" +%s` (GNU date — present on Linux and Git-bash/Windows); if that fails (e.g. BSD/macOS date), bash omits the duration and prints `Built through the loop.`. PowerShell parses via `[datetime]::Parse` (always available). The parity tests compare the process / phases / git portions, not the elapsed line.

## Components

- `scripts/ss-report` — bash implementation (above).
- `scripts/ss-report.ps1` — PowerShell twin.
- `skills/report/SKILL.md` — the `/ss-report` skill (name `ss-report`; "Use …" description). Brings the skill count to **21**.
- `skills/ship/SKILL.md` — one added line in `## Steps`: after landing, optionally run `/ss-report` for a shareable summary. (Surgical; no renumber needed if appended as the final optional note.)
- `tests/report.test.sh` — behavior suite (own temp **git** repo + seeded ledger). Wired into `tests/run.sh` as `[5/5]` (existing checks become `[1/5]..[4/5]`).
- `docs/ledger.md` — append a short "Run report" paragraph.
- `CHANGELOG.md` — `## [Unreleased]` → `### Added` bullet.

## Forward compatibility

Because the report already surfaces any `note` events present in the ledger, the "rich metrics" upside (slate #11 variant B) arrives for free later: a phase that runs `ledger review note na "3 findings"` will show up under `Notes:` with **no change to `ss-report`**. v1 ships lean; richer counts are an opt-in follow-up that only edits phase skills.

## Testing

`tests/report.test.sh` (bash), run from a fresh temp dir:
1. `git init` a temp repo; create + commit a source file and a `*.test.sh` file (≥1 test file, ≥2 commits).
2. Seed a ledger via `scripts/ledger` (e.g. frame/plan/build/review gate pass; secure skip with a reason).
3. Run `scripts/ss-report` and assert the block contains: the heading with the change, `SuperStack process:`, `Phases:` with the right run/skip counts, a `Change:` line with a commit count, and the `Skipped:` reason.
4. `--save` writes `${SUPERSTACK_DIR}/run-report-<change>.md`; assert the file exists and matches stdout.
5. **Parity:** run `scripts/ss-report.ps1` in the same repo/ledger; assert its heading + attestation + `Phases:` + `Skipped:` lines equal bash's (elapsed line excluded).
6. **Empty-ledger:** with no ledger, assert it still prints the heading and `Phases: 0 run · 0 skipped` and exits 0.

Wire `tests/report.test.sh` into `tests/run.sh` as `[5/5]`; renumber the existing labels to `[1/5]..[4/5]`. `bash scripts/lint-skills.sh` must report `OK: 21 skill(s)`; `bash tests/run.sh` must end `ALL TESTS PASS`.

## Acceptance criteria

- `scripts/ss-report` and `.ps1` exist, are SPDX-headed, and produce the identical ledger-derived block (bash exec bit recorded in git).
- `/ss-report` skill exists; lint reports **21 skills**; `/ss-ship` references it.
- `tests/report.test.sh` passes and is wired into `tests/run.sh` `[5/5]`; full self-test + lint green; CI green.
- Works against an empty ledger (degrades gracefully) and outside a git repo (omits the `Change:` bullet).
