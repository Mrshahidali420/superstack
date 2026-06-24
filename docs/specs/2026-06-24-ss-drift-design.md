# /ss-drift — plan-vs-build drift detection (v0.6.0+)

- **Date:** 2026-06-24
- **Status:** Approved (design)
- **Target version:** next release (`[Unreleased]`); skills count → 26.
- **Related:** the writing-plans plan format (`docs/specs/*-plan.md`), `scripts/ss-doctor` (freshest sibling), `scripts/ledger`, the opt-in guard hook (`hooks/guard-check`). Deferred siblings: a PreToolUse drift hook, phase-order drift.

## 1. Context

SuperStack's thesis is a *verifiable* process. One thing it can't yet verify: did the BUILD stay within the approved PLAN? `/ss-drift` answers that — it compares the files a plan **declared** against the files the branch **actually changed**, and reports the divergence. This directly attacks scope creep (we hit exactly that this session — an implementer added an out-of-scope skill stub).

Live research (2026-06-24) frames it: drift is the **desired-vs-actual** model from [Terraform](https://spacelift.io/blog/terraform-drift-detection) (config = desired, live = actual, `plan` shows the diff). Here the **plan's declared files = desired**, **git's changed files = actual**. Drift is **bidirectional** — changed-but-unplanned (*scope creep*) and planned-but-untouched (*incomplete*). Drift is *informational*: you accept it (update the plan) or revert it (out of scope). Agent scope-guardrails ([logi-cmd/agent-guardrails](https://github.com/logi-cmd/agent-guardrails): "the agent only operates on authorized file paths") validate this as a category.

## 2. Goals / Non-goals

**Goals**
- One read-only command that reports how far a build has drifted from its plan, both directions, with a CI-usable exit code.
- Parse the plan's declared files deterministically; diff against git's actual changes.
- Byte-identical bash + PowerShell twins; deterministic, parity-tested.

**Non-goals (deferred, deliberate)**
- **PreToolUse blocking hook** — proactively blocking an edit to an unplanned file needs a new `.superstack/current-plan` *linkage* (so a hook knows the active plan mid-build); its own design. The command delivers detection now with no new state.
- **Phase-order drift** — the loop *explicitly allows re-entry* (a bug report starts at QA), so "phases out of order" from the ledger would produce false positives. Out of scope; file-drift is crisp.
- Auto-remediation, `--json` — YAGNI (the exit code serves CI; the report serves humans).

## 3. Repo facts relied on

- Plans live at `docs/specs/YYYY-MM-DD-<feature>-plan.md`. Each task has a `**Files:**` block whose bullets are `- Create: \`path\``, `- Modify: \`path\``, `- Test: \`path\``. The path is the **first backticked token**; a Modify/Test line may carry a trailing parenthetical annotation or a `:line-range` suffix (e.g. `- Modify: \`tests/run.sh\` (append…)`, `- Modify: \`file.py:123-145\``). Format is 100% consistent across existing plans.
- The `**Interfaces:**` block and `- [ ]` step bullets also contain backticks — so the parser must scope strictly to the `**Files:**` block.
- Changed files: `git diff --name-only <base>...HEAD` (committed, merge-base form) ∪ `git diff --name-only HEAD` (uncommitted tracked). Branch via `git branch --show-current`; base default `main`.
- House conventions: bash + `.ps1` twins, `${SUPERSTACK_DIR:-.superstack}` (not needed here — drift reads the plan + git, not the runtime dir), ASCII-only `printf`, 54-dash separators, exit 0/1/2, the `chk`/`newrepo` test harness, `tests/run.sh` currently `[1/10]..[10/10]`.

## 4. CLI surface

```
ss-drift <plan-file> [base]
```
- `<plan-file>` (required): path to the plan markdown. Missing/nonexistent → stderr usage, **exit 2**.
- `[base]` (optional, default `main`): the ref the branch diverged from. If the ref doesn't resolve (`git rev-parse --verify`), or not in a git repo → stderr error, **exit 2**.
- Unknown flag (any `-…` arg) → stderr usage, exit 2.
- PowerShell: `ss-drift.ps1 <plan-file> [base]`. Output identical.
- **Exit codes:** `0` = no unplanned changes (CLEAN); `1` = unplanned changes present (DRIFT); `2` = usage/precondition error.

## 5. Computation

**Declared set** — parse `<plan-file>` with an awk/Get-Content state machine:
- Enter "files mode" when a line matches `^\*\*Files:\*\*`.
- While in files mode, for a line matching `^- (Create|Modify|Test):`, extract the text inside the **first** backtick pair; strip a trailing `:<digits>[-<digits>]` line-range; that path joins the declared set.
- Leave files mode at the first line that is blank, or starts with `**` (next bold header), `### ` (next task), or `- [ ]` (a step).
- Union across all tasks; de-duplicate.

**Changed set** — union of:
- `git diff --name-only <base>...HEAD` (committed branch changes; `...` = since merge-base),
- `git diff --name-only HEAD` (uncommitted tracked changes),
then de-duplicate. **Exclude** any path under `docs/specs/` (the plan/spec docs are meta, not implementation). Gitignored scratch (`.superstack/`, `.superpowers/`) never appears in `git diff`, so needs no explicit exclude.

**Comparison** (set algebra over the two sorted-unique sets):
- `unplanned` = changed ∖ declared (the scope-creep signal).
- `untouched` = declared ∖ changed (incomplete / over-declared — advisory).
- counts: `declared` = |declared|, `changed` = |changed|, `unplanned` = |unplanned|, `untouched` = |untouched|.
- bash uses `comm` over `sort -u` streams (process substitution); PowerShell uses `HashSet`/`Where-Object -notin`. Output paths sorted ascending.

**Verdict / exit:** `DRIFT` + exit 1 if `unplanned > 0`; else `CLEAN` + exit 0. (Untouched alone never fails — a build may be mid-flight.)

## 6. Output (ASCII, byte-identical twins)

DRIFT:
```
ss-drift: plan vs build
------------------------------------------------------
plan:     2026-06-24-ss-doctor-plan.md
base:     main
declared: 6   changed: 7   unplanned: 2   untouched: 1
------------------------------------------------------
unplanned changes (not in the plan):
  + README.md
  + scripts/extra
planned but untouched (not yet built / over-declared):
  - tests/extra.test.sh
verdict: DRIFT
```
CLEAN:
```
ss-drift: plan vs build
------------------------------------------------------
plan:     2026-06-24-ss-doctor-plan.md
base:     main
declared: 6   changed: 6   unplanned: 0   untouched: 0
------------------------------------------------------
verdict: CLEAN
```

- **Header:** `ss-drift: plan vs build`, then a 54-dash separator.
- **Info block:** `plan:` shows the **basename** of the plan file; `base:` the base ref; then the counts line. Labels left-padded to width 9 (`printf '%-9s %s\n'`), so `plan:`/`base:`/`declared:` values align; the counts line is `declared: %d   changed: %d   unplanned: %d   untouched: %d` (3 spaces between fields, no pluralization).
- **Separator**, then (only if non-empty) the `unplanned changes (not in the plan):` section with `  + <path>` lines, then the `planned but untouched (not yet built / over-declared):` section with `  - <path>` lines.
- **Verdict** is the last line: `verdict: DRIFT` or `verdict: CLEAN`. (No third separator — the verdict follows the lists, or the info separator when there are no lists.)

## 7. Parity mechanics

bash + `.ps1` twins, ASCII only, identical stdout. `/ss-drift` is **read-only**, so the parity test compares a real run on a deterministic fixture (a seeded git repo with a known plan and a known base→HEAD diff). git-diff order is stabilized by `sort -u` / sorted HashSet enumeration, so both twins emit identical lists. The ps1 twin sets `$PSNativeCommandUseErrorActionPreference = $false` so git's non-zero exits (e.g. a bad base ref) are handled, not thrown.

## 8. Test plan

New `tests/drift.test.sh`, wired into `tests/run.sh` (`[N/10]`→`[N/11]`). Fixtures use `newrepo` + a hand-written plan file and real commits so the base→HEAD diff is deterministic.

1. **Drift detected** — base commit declares files A/B/C in a plan; HEAD commit creates A, B, and an unplanned D, leaving C untouched. `ss-drift <plan> <base>` → `unplanned: 1` listing `+ D`, `untouched: 1` listing `- C`, `verdict: DRIFT`, exit 1.
2. **Clean** — HEAD changes exactly the declared A/B/C → `unplanned: 0   untouched: 0`, `verdict: CLEAN`, exit 0.
3. **Declared-path parsing** — a plan with `Create`/`Modify`/`Test` bullets, a `:line-range` suffix, and a trailing parenthetical annotation all parse to the bare path; backticks in an adjacent `**Interfaces:**` block are NOT counted.
4. **docs/specs excluded** — a change to the plan file itself (under `docs/specs/`) does not count as unplanned.
5. **Uncommitted changes counted** — an unplanned file left in the working tree (uncommitted) appears in `unplanned`.
6. **Missing/bad inputs** — nonexistent plan file → exit 2; a `base` ref that doesn't resolve → exit 2; not a git repo → exit 2.
7. **Parity** — bash vs `pwsh` byte-identical on the drift fixture (skipped when `pwsh` absent, same guard as the suite).

## 9. Docs / version impact

- `skills/drift/SKILL.md` — the `/ss-drift` skill (run during Review/Ship to confirm the build matched the plan). Lineage notes it as the build-vs-plan verification.
- `README.md` — add `/ss-drift` to the supporting-skills surface; skills count → **26**.
- `CHANGELOG.md` — `[Unreleased]` `### Added` entry.

## 10. Risks

- **Plan-format coupling** — the parser depends on the writing-plans `**Files:**` convention; if the format changes, the declared set is wrong. Mitigated: the format is consistent and tested; a plan with zero parseable Files: blocks yields `declared: 0` (everything reads as unplanned) — a loud, obvious signal rather than a silent miss.
- **Base-ref ambiguity** — defaults to `main`; a branch off something else needs the explicit `[base]` arg. Documented.
- **Rename detection** — `git diff --name-only` lists a rename as delete+add (or the new path); a renamed-but-planned file could show as unplanned. Acceptable for v1 (renames are rare in a single feature branch); `--find-renames` is a possible later refinement.
- **Annotations in Modify lines** — only the first backticked token is taken, so trailing prose/line-ranges don't corrupt the path. Tested.
