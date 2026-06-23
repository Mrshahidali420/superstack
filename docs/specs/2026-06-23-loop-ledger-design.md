# Loop Ledger — Design Spec

- **Date:** 2026-06-23
- **Status:** Approved (design); pending implementation plan
- **Feature:** The Loop Ledger primitive + `ss-audit` proof-of-process gate

## Problem

SuperStack's differentiator is an explicit, gated loop (Frame → … → Ship). But nothing
**records** that the loop actually ran, and nothing **verifies** it before shipping. The "skills
are mandatory" promise is currently advisory: an agent can skip Review or Secure and ship anyway,
and there's no trail of how a change was built.

## Goal

A structured, append-only record of the loop's execution per change — `.superstack/ledger.jsonl` —
plus an `ss-audit` skill that reads it to verify mandatory phases ran. This is the foundational
primitive that later unlocks attestation, decision-trace, run-reports, replay, and `ss-evolve`.

## Non-goals (future, built on this)

`ss-trace`, shareable run-report, loop replay, and `ss-evolve` are explicitly **out of scope** for
this spec. So is committing the ledger to git (default is gitignored; see Decisions).

## Design

### 1. Ledger storage & format

- Location: `.superstack/ledger.jsonl` in the consuming project. Append-only. Runtime artifact —
  **gitignored** by default (the durable, shareable proof is the attestation written into the PR).
- One JSON object per line:

  ```json
  {"ts":"2026-06-23T12:00:00Z","change":"feature/x","phase":"secure","event":"gate","status":"pass","note":"OWASP + secrets clean"}
  ```

  | Field | Meaning |
  |-------|---------|
  | `ts` | ISO-8601 UTC, stamped by the helper |
  | `change` | branch name (`git branch --show-current`) or `"default"` outside a repo |
  | `phase` | one of the loop/supporting phases (`frame`,`plan`,`build`,`review`,`qa`,`secure`,`ship`,`learn`,…) |
  | `event` | `gate` (phase cleared its gate), `skip` (deliberately skipped — `note` is the reason), or `note` |
  | `status` | `pass` \| `fail` \| `skip` \| `na` |
  | `note` | short free text |

### 2. The `ledger` helper

- `scripts/ledger` (bash) and `scripts/ledger.ps1` (Windows). Interface:

  ```
  ledger <phase> <event> [status] [note]
  # e.g.  ledger review gate pass "no critical/high"
  #       ledger qa skip skip "no UI in this change"
  ```

- Behavior: stamp `ts` (`date -u +%Y-%m-%dT%H:%M:%SZ`), compute `change` from git, validate the
  `phase`/`event`/`status` enums, create `.superstack/` if absent, append the line. Exit 0 on
  success; non-zero only on an invalid enum (so a typo is noticed).
- Fallback: if the helper is missing, skills append a single line in the documented format directly.
  The helper is preferred (consistent timestamp + validation).

### 3. Skill integration

Each of the eight phase skills gains **one line** in its `## Gate` section:

> Record the outcome: `ledger <phase> gate <pass|fail>` — or `ledger <phase> skip skip "<reason>"`
> if you deliberately skipped this phase.

`CLAUDE.md` documents the ledger convention so the loop leaves a trail by default. No other skill
logic changes.

### 4. `ss-audit` (skill + script)

- `scripts/ss-audit [change]` reads the ledger (filtered to the current `change`, default = current
  branch) and checks that every **mandatory phase** has either a `gate pass` or a `skip` with a
  non-empty reason.
- Output: a report (`phase → pass | skip(reason) | MISSING`) and a verdict line.
- Exit code: `0` = complete, `1` = incomplete. (Pure status — the *caller* decides warn vs block.)
- `ss-audit --attest` prints the one-line attestation (see §6).
- `skills/audit/SKILL.md` (name `ss-audit`) wraps the script: run it; if incomplete, complete the
  missing phase or record an explicit skip-with-reason; never paper over it.

### 5. Config

`.superstack/config` (simple `key=value`), with defaults applied when the file is absent:

```
mandatory_phases=review,secure
audit_mode=warn            # warn | block
```

Parsed by `ss-audit` with grep/sed — no dependency beyond coreutils.

### 6. Attestation

`/ss-ship` runs `ss-audit` as its **first gate**, then emits a compact proof into the PR body
(and an optional `SuperStack-Process:` commit trailer):

```
SuperStack process: Framed ✓  Planned ✓  Built(TDD) ✓  Reviewed ✓  Secured ✓  QA ⊘(no UI)
```

This is the durable, shareable artifact (the ledger itself stays local).

### 7. Enforcement hook (opt-in, off by default)

- `hooks/audit-check` (bash) + a `PreToolUse` (Bash matcher) entry in `hooks/hooks.json`, run via the
  existing `run-hook.cmd` launcher.
- Inert unless `SUPERSTACK_AUDIT=1`. When enabled, it inspects the command; if it's `git push` or
  `gh pr create` and `ss-audit` reports incomplete, it exits 2 with the missing phases. Mirrors the
  guard hook's opt-in, env-gated model.

### 8. Testing

Extend `tests/run.sh` with a `[4/4]` check using a temp `.superstack/ledger.jsonl`:
- review + secure `gate pass` → `ss-audit` exits 0 (complete).
- remove secure → exits 1 (incomplete).
- add `secure skip skip "n/a"` → exits 0 (complete via explicit skip).

`scripts/lint-skills.sh` continues to validate `hooks/hooks.json`; CI runs the self-test.

## Files

**New:** `skills/audit/SKILL.md`, `scripts/ledger`, `scripts/ledger.ps1`, `scripts/ss-audit`,
`scripts/ss-audit.ps1`, `hooks/audit-check`, `docs/ledger.md`.

**Edit:** the 8 phase skills (one Gate line each), `skills/ship/SKILL.md` (audit-first-gate +
attestation), `hooks/hooks.json` (opt-in audit PreToolUse), `.gitignore` (`.superstack/`),
`tests/run.sh` (ledger/audit check), `CLAUDE.md` + `README.md` + `CHANGELOG.md` (mention).

## Acceptance criteria

1. Running the loop on a change appends `gate` entries to `.superstack/ledger.jsonl`.
2. `ss-audit` reports COMPLETE when review + secure passed; INCOMPLETE (exit 1) when a mandatory
   phase is missing; COMPLETE when the missing phase has an explicit skip-with-reason.
3. `/ss-ship` warns (or blocks, per `audit_mode`) on an incomplete ledger and emits the attestation.
4. With `SUPERSTACK_AUDIT=1`, the hook blocks `git push` / `gh pr create` on an incomplete ledger.
5. Self-test `[4/4]` green in CI; linter green; skill count 20 (adds `ss-audit`).

## Decisions & risks

- **Self-reported ledger** can be incomplete if the agent doesn't call `ledger`. Accepted: same
  advisory tradeoff as the rest of the framework; the SessionStart hook reinforces the convention,
  and a future hook/`ss-evolve` can tighten it. The opt-in audit hook is the hard-enforcement path.
- **Gitignored vs committed ledger:** default gitignored; attestation in the PR is the durable
  proof. A project can choose to commit `.superstack/ledger.jsonl` for a full in-repo trail.
- **Cross-platform:** every script ships bash + PowerShell, consistent with the rest of the repo.
