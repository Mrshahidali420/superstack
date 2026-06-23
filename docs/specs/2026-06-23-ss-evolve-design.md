# ss-evolve — Design

**Status:** Approved (2026-06-23)
**Feature:** Slate item #7, the headline frontier feature. `/ss-evolve` learns from how the loop actually ran in *this* project (the Loop Ledger) and automatically improves the project's own setup — closing the loop from "record what happened" (ledger) to "act on what was learned."

## Problem

The ledger records every gate, skip, and note, and `/ss-audit` verifies the loop ran — but nothing turns that accumulated signal back into improvement. A human has to notice "we skip Secure every time" and act. `/ss-evolve` detects such patterns deterministically and either applies a safe documentation/config fix automatically or drafts a higher-risk change (a new skill) for review.

## Scope

**In:** a deterministic detection engine (`scripts/ss-evolve` + `.ps1`) over the project's ledger, a templated auto-apply path in the script, and a `/ss-evolve` skill that adds LLM-authored drafting on top, with risk-tiered application.

**Non-goals (v1):**
- Framework-level evolution (PRs to the SuperStack repo). This is project-local only.
- An `--explore` mode (relaxed thresholds / free LLM synthesis). The pipeline is designed to accept it later as a flag; v1 ships detect + draft only.
- Recurring-*note*-theme clustering (needs semantic grouping). v1 detects two clean, countable patterns.
- Periodic / automatic triggering. v1 is on-demand (`/ss-evolve`).
- Auto-committing brand-new skills. New skills are always routed to `.superstack/proposals/` for human review (the tiering decision).

## Architecture — one pipeline, two layers

```
ledger.jsonl ──▶ DETECTION (scripts/ss-evolve, deterministic)
                   │  findings: {id, type, phase, count, evidence}
                   ├──▶ scripts/ss-evolve --apply  (templated, no LLM)  ── auto-commit low-risk
                   └──▶ /ss-evolve skill (agent)    (LLM-authored)
                          ├─ low-risk  → tailored CONTEXT.md edit ── auto-commit
                          └─ new skill → .superstack/proposals/<name>/  (review, not committed)
```

The deterministic detection is the auditable heart (the "heuristic" engine). The skill layer is the "hybrid" (deterministic trigger + LLM draft). A future `--explore` flag relaxing the threshold is the "LLM-synthesis" mode.

## Detection — `scripts/ss-evolve` (+ `.ps1`)

Reads `${SUPERSTACK_DIR:-.superstack}/ledger.jsonl`, aggregating across **all** changes/branches (project-wide learning, not one branch). Emits findings; `--json` for the skill, human-readable by default.

**v1 patterns (countable, evidence-clear):**
1. `skipped-phase` — a phase with ≥ *threshold* `skip` events. Evidence: count + the most common skip reason(s).
2. `failing-gate` — a phase with ≥ *threshold* `gate` events of `status=fail`. Evidence: count.

**Finding fields:** `{id, type, phase, count, reason}` where `id` is a stable fingerprint: `skipped:<phase>` or `failing:<phase>`.

**Threshold:** `.superstack/config` key `evolve_threshold` (default `3`).

**Dedup:** `.superstack/evolve-state` is a newline-delimited list of finding `id`s already handled. `scripts/ss-evolve --new-only` omits any finding whose `id` is in `evolve-state`. (Plain `ss-evolve` lists all; `--new-only` lists unhandled.)

**Exit:** 0 always (it's a reporter); 1 only on usage error.

## Deterministic apply — `scripts/ss-evolve --apply`

For each **new** finding (respecting `evolve-state`), append a **templated** entry to `CONTEXT.md` at the repo root (create the file with an `## Evolved insights` heading if absent), then make one `chore(evolve):` commit, append the finding `id` to `.superstack/evolve-state`, and record a ledger `note` event (`ledger evolve note na "<summary>"`). Templates:

- `skipped-phase` (phase P, count K, reason R):
  `- **\`P\` is routinely skipped** (K×; usual reason: "R"). If that's expected here, keep recording the skip reason or drop \`P\` from \`.superstack/config\` \`mandatory_phases\`; if not, it's a process gap to close.`
- `failing-gate` (phase P, count K):
  `- **\`P\` gate often fails first pass** (K×). Recurring friction — see the ledger notes; consider tightening the upstream phase or adding a checklist.`

`--apply` is deterministic and LLM-free — it is the unit-testable auto-apply path and a zero-LLM "heuristic" mode. `--dry-run` (with `--apply`) prints what it *would* do without writing or committing.

This path only ever touches `CONTEXT.md` (+ state/ledger) — never `skills/`. New skills come only from the skill layer (below).

## Authoring — the `/ss-evolve` skill

The primary UX. Steps:
1. Run `scripts/ss-evolve --json --new-only` to get unhandled findings. If none → report "loop's running clean, nothing to evolve" and stop.
2. For each finding, the agent reads the evidence (and, if useful, the relevant ledger `note`s / recent diffs) and decides the improvement:
   - **Low-risk** (documentation/config insight): author a *tailored* `CONTEXT.md` entry (richer than the template), append it, and commit as `chore(evolve): <summary>`.
   - **New skill warranted** (a recurring multi-step fix worth codifying): write a complete draft to `.superstack/proposals/<name>/SKILL.md`, run `scripts/lint-skills.sh`-style frontmatter validation on it, and **do not commit it live** — announce its path for the human to move into `skills/`.
3. After each applied/proposed change: append the finding `id` to `.superstack/evolve-state` and log `ledger evolve note na "<what happened>"`.
4. **Announce** a summary: what was auto-applied (+ the `chore(evolve):` commits and how to `git revert` them), and what was proposed (+ the proposal paths).
5. Honor a dry-run request: draft and show everything, apply/commit nothing.

## Guardrails (always)

- **Lint-gate:** a proposed skill must pass frontmatter/structure validation before it's written as a proposal; an invalid draft is discarded with a note.
- **Revertable:** exactly one `chore(evolve):` commit per applied change — `git revert` undoes it cleanly; the announcement names the commit.
- **Dedup:** `evolve-state` ensures a pattern is acted on once, never re-applied on re-runs.
- **Threshold:** only patterns at/above `evolve_threshold` (default 3) qualify — no acting on noise.
- **Audit trail:** every action is logged as a ledger `note` event, so `/ss-report` and `/ss-audit` see it.
- **Tiering:** new skills never auto-commit; they land in `.superstack/proposals/` (gitignored) for review.
- **Dry-run:** preview without side effects.

## Cross-platform parity

`scripts/ss-evolve` (bash) and `scripts/ss-evolve.ps1` produce identical findings (`--json`) and identical templated `--apply` output for the same ledger/repo. ASCII-only output (same parity rule as `ss-report`). Shebang + `# SPDX-License-Identifier: MIT`. `SUPERSTACK_DIR` override. Reads the ledger via shell stdin redirection (the portable `jq … < "$ledger"` pattern established in `ss-audit`/`ss-report`).

## Files

- Create: `scripts/ss-evolve`, `scripts/ss-evolve.ps1`, `skills/evolve/SKILL.md` (name `ss-evolve`; the **22nd** skill), `tests/evolve.test.sh`.
- Modify: `tests/run.sh` (add `[6/6]` → `tests/evolve.test.sh`; renumber `[1/5]..[5/5]`→`[1/6]..[5/6]`), `docs/ledger.md` (append an "Evolve" paragraph), `CHANGELOG.md` (`[Unreleased]` → `### Added`). No `.gitignore` change — `.superstack/` (holding `evolve-state` + `proposals/`) is already ignored.

## Testing

`tests/evolve.test.sh` (bash), in a temp git repo with a seeded ledger:
1. Seed 3 `secure skip skip "no IO"` + 4 `review gate fail` (and a couple of passes). Run `scripts/ss-evolve --json` → assert a `skipped-phase` finding for `secure` (count ≥3, reason "no IO") and a `failing-gate` finding for `review` (count ≥4).
2. **Threshold:** seed only 2 skips of `plan` → assert NO `skipped:plan` finding (below default 3).
3. **`--apply`:** run `scripts/ss-evolve --apply` → assert `CONTEXT.md` gained the templated `secure`/`review` lines, a `chore(evolve):` commit exists, and `.superstack/evolve-state` contains `skipped:secure` + `failing:review`.
4. **Dedup:** run `--apply` again → assert NO new commit and CONTEXT.md unchanged (ids already in evolve-state); `--new-only` lists nothing.
5. **Dry-run:** fresh state + `--apply --dry-run` → prints intended changes, writes/commits nothing.
6. **Parity:** `scripts/ss-evolve.ps1 --json` emits the same findings as bash for the same ledger.

Wire `tests/evolve.test.sh` into `tests/run.sh` as `[6/6]`. `bash scripts/lint-skills.sh` → `OK: 22 skill(s)`; `bash tests/run.sh` → `ALL TESTS PASS`. (The skill's LLM-authoring/proposal flow is validated in review + manually, like other agent-driven skills; the deterministic detection + `--apply` carry the automated coverage.)

## Acceptance criteria

- `scripts/ss-evolve` (+ `.ps1`) detect the two patterns identically, honor `evolve_threshold` and `evolve-state` dedup, and `--apply` makes one revertable `chore(evolve):` commit per new finding touching only `CONTEXT.md` (+ state/ledger).
- `/ss-evolve` skill exists (lint → **22 skills**); it auto-applies tailored low-risk edits and routes new skills to `.superstack/proposals/` (never auto-committed); it logs a ledger `note` and announces revert instructions; it honors dry-run.
- `tests/evolve.test.sh` passes and is wired into `tests/run.sh [6/6]`; full self-test + lint green; CI green.
- Degrades gracefully: empty/missing ledger → "nothing to evolve", exit 0.

## Out of scope / future

`--explore` (relaxed-threshold free synthesis); recurring-note-theme clustering; periodic auto-trigger; framework-level evolution (PR to the superstack fork); richer pattern types (slow phases via `ts` deltas, phase-order anomalies).
