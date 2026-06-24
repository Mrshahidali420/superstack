# /ss-doctor — project health check (the verify leg) (v0.6.0+)

- **Date:** 2026-06-24
- **Status:** Approved (design)
- **Target version:** next release (`[Unreleased]`); skills count → 25.
- **Related:** `/ss-init` (the setup counterpart — init writes, doctor verifies), `scripts/ledger`, `scripts/ss-audit`/`ss-report`/`ss-replay`/`ss-evolve` (the jq-dependent consumers), `install.sh` (global — out of scope), `scripts/lint-skills.sh` (repo-dev linter — not duplicated).

## 1. Context

`/ss-init` makes a project loop-ready. `/ss-doctor` is its diagnostic counterpart: a **read-only, project-scoped** health check that verifies the same setup is present and the runtime is sound, and tells the user exactly how to fix anything that isn't. Together they are the adoption track — init sets up, doctor verifies.

Live research (CLI `doctor` best practices, 2026-06-24 — flutter doctor, brew/npm doctor, health-check CLIs) gives the shape: a **three-state checklist** (✓ pass / ! warn / ✗ fail; ASCII `[OK]`/`[WARN]`/`[FAIL]`), an **actionable fix on every non-OK line** (the exact command, not vague advice), and an **exit code usable as a CI preflight** (0 healthy, non-zero on real problems; warnings advisory). `--fix`/`--json` exist in some tools but are add-ons, not core.

## 2. Goals / Non-goals

**Goals**
- One read-only command that reports whether *this* project's SuperStack runtime is healthy, with an actionable fix per problem.
- Three-state checklist + a fixed-label summary footer + a CI-usable exit code.
- Works **even when `jq` (a dependency it checks) is absent** — doctor must not need the thing it diagnoses.
- Byte-identical bash + PowerShell twins; deterministic, parity-tested.

**Non-goals (deliberate, YAGNI)**
- `--fix` — the fix *is* `/ss-init` (idempotent); doctor diagnoses, init repairs. (`--fix`/`--json`/`--strict` deferred.)
- Global/install checks — doctor is project-scoped; it does not probe `~/.claude` or verify the plugin install (that's `install.sh`'s domain).
- Skill-authoring validation — that's `scripts/lint-skills.sh` (a repo-dev tool), not a user-project concern.

## 3. Repo facts relied on

- A healthy project (per `/ss-init`) has: `.superstack/config` (keys `mandatory_phases` default `review,secure`; `evolve_threshold` default `3`), `.superstack/` in the git-root `.gitignore`, and a valid `.superstack/ledger.jsonl`. Runtime dir = `${SUPERSTACK_DIR:-.superstack}`.
- `jq` is a hard dependency of `ss-audit`/`ss-report`/`ss-replay`/`ss-evolve` (they parse the ledger with it). `git` is used for branch/root detection and degrades to `change=default` if absent (`scripts/ledger:12`).
- Ledger line shape `{ts,change,phase,event,status,note}`; `event ∈ {enter,gate,skip,note}`, `status ∈ {pass,fail,skip,na}`, `phase` among the 8 loop phases. Each entry is one JSON object per line.
- Git idioms (match siblings): repo root `git rev-parse --show-toplevel`, branch `git branch --show-current`, inside-repo `git rev-parse --is-inside-work-tree`.

## 4. CLI surface

```
ss-doctor
```
- No flags (read-only diagnostic). PowerShell twin: `ss-doctor.ps1` (no params). Output identical.
- Unknown argument → stderr usage, **exit 2** (usage error, distinct from the health verdict).
- **Exit codes:** `0` = healthy or warnings-only; `1` = at least one `[FAIL]`; `2` = usage error.

## 5. The five checks

Let `dir = ${SUPERSTACK_DIR:-.superstack}`. Each check yields a state (`OK`/`WARN`/`FAIL`) and a detail string. Fix hints (`-> ...`) appear in the detail for non-OK states. **User-facing dir text uses the literal `.superstack/`** (display convention).

**1. `jq`** — presence via `command -v jq`.
- OK → `<jq --version> on PATH` (e.g. `jq-1.7 on PATH`; fall back to `jq` if the version string is empty).
- FAIL → `not found -> install jq (needed by audit/report/replay/evolve)`.

**2. `git`** — `command -v git` then `git rev-parse --is-inside-work-tree`.
- OK (inside a repo) → `git repo (branch: <branch>)` (`<branch>` = `git branch --show-current`, or `detached` if empty).
- WARN (git not on PATH) → `git not on PATH -> branch detection degrades (change=default)`.
- WARN (not inside a repo) → `not a git repo -> ledger change will be "default"; gitignore check skipped`.

**3. `config`** — `dir/config`.
- present + valid → `mandatory_phases=<v>  evolve_threshold=<v>` (the parsed values).
- present + invalid → WARN with the first problem: `unknown phase "<x>" in mandatory_phases -> edit .superstack/config` or `evolve_threshold "<x>" not a positive integer -> edit .superstack/config`.
- missing → WARN → `.superstack/config missing -> run /ss-init`.
- Parsing: value = last line matching `^<key>=` (matches how `ss-audit` reads it), `key=value`. Valid phases: `frame plan build review qa secure ship learn`. `evolve_threshold` must match `^[0-9]+$` and be `>= 1`.

**4. `gitignore`** — only meaningful inside a git repo.
- not a git repo → OK → `n/a (not a git repo)` (the git check already surfaced the repo state; not a problem here).
- git repo + `.superstack/` (or `.superstack`) ignored at the git-root `.gitignore` → OK → `.superstack/ is gitignored`.
- git repo + not ignored → WARN → `.superstack/ not gitignored -> run /ss-init`.
- The ignore test strips `\r` (`tr -d '\r'`) and matches a whole line equal to `.superstack/` or `.superstack` (same robustness as `ss-init`).

**5. `ledger`** — `dir/ledger.jsonl`. **Validated jq-free** (so doctor works when jq is the missing dep).
- absent → WARN → `no ledger yet -> run /ss-init or start the loop`.
- present, 0 non-empty lines → WARN → `ledger is empty -> run /ss-init or start the loop`.
- present, all non-empty lines well-formed → OK → `<N> entries, all well-formed`.
- present, M malformed → FAIL → `<M> of <N> lines malformed -> inspect .superstack/ledger.jsonl`.
- Well-formed = a non-empty line matching `^{.*}$`. Counts via `awk` (bash) / regex over `Get-Content` (ps1): `bad = NF && !/^\{.*\}$/`; `total = NF`. (A deeper enum check is YAGNI — the `ledger` script validates on write; real-world corruption is truncation, which the structural check catches.)

## 6. Output (ASCII, byte-identical twins)

```
ss-doctor: SuperStack project health (.superstack/)
------------------------------------------------------
  [OK]   jq          jq-1.7 on PATH
  [OK]   git         git repo (branch: main)
  [WARN] config      .superstack/config missing -> run /ss-init
  [OK]   gitignore   .superstack/ is gitignored
  [WARN] ledger      no ledger yet -> run /ss-init or start the loop
------------------------------------------------------
ok: 3   warnings: 2   problems: 0   verdict: WARNINGS
```
Healthy:
```
ss-doctor: SuperStack project health (.superstack/)
------------------------------------------------------
  [OK]   jq          jq-1.7 on PATH
  [OK]   git         git repo (branch: main)
  [OK]   config      mandatory_phases=review,secure  evolve_threshold=3
  [OK]   gitignore   .superstack/ is gitignored
  [OK]   ledger      42 entries, all well-formed
------------------------------------------------------
ok: 5   warnings: 0   problems: 0   verdict: HEALTHY
```

- **Header:** `ss-doctor: SuperStack project health (.superstack/)` then a separator of exactly 54 `-` (matches `ss-replay`).
- **Row:** `printf '  %-6s %-10s %s\n' "<status>" "<label>" "<detail>"` — status token (`[OK]`/`[WARN]`/`[FAIL]`) left-padded to 6, label left-padded to 10, then detail. PowerShell: `'  {0,-6} {1,-10} {2}'`. No trailing padding (detail is last).
- **Footer:** the separator, then fixed-label counts + verdict token (no pluralization → no parity ambiguity): `ok: <n>   warnings: <n>   problems: <n>   verdict: <TOKEN>` (3 spaces between fields). `<TOKEN>` = `HEALTHY` (0 warn, 0 fail) · `WARNINGS` (warn>0, fail==0) · `PROBLEMS` (fail>0).
- **Exit:** `1` if `problems > 0`, else `0`.

## 7. Parity mechanics

bash + `.ps1` twins, ASCII only, identical stdout. Because doctor is **read-only**, running it twice doesn't mutate state — the parity test compares a real (non-dry) run on the same healthy fixture (no `--dry-run` trick needed, unlike `ss-init`). The `jq --version` and `git branch` substrings are identical across twins on the same machine. Strip `\r` with `tr -d '\r'`.

## 8. Test plan

New `tests/doctor.test.sh`, wired into `tests/run.sh` (`[N/9]`→`[N/10]`). Fresh `git init` tmp dirs with `SUPERSTACK_DIR` set under them; `chk`/`newrepo` helpers.

1. **Healthy** — run `ss-init` then `ss-doctor` in a fresh repo: every line `[OK]`, footer `verdict: HEALTHY`, exit 0.
2. **Not initialized** — fresh repo, no init: `config`/`gitignore`/`ledger` are `[WARN]`, `jq`/`git` `[OK]`, footer `verdict: WARNINGS`, exit 0.
3. **Corrupt ledger** — seed a ledger with a malformed line (e.g. `{"ts":"...` truncated): `ledger` `[FAIL]` with the `M of N` count, footer `verdict: PROBLEMS`, exit 1.
4. **Invalid config** — write `mandatory_phases=review,bogus`: `config` `[WARN]` naming `bogus`; and `evolve_threshold=x` → `[WARN]` "not a positive integer".
5. **jq-free resilience** — run `ss-doctor` with a curated `PATH` that omits `jq` (temp bindir of symlinks to the real tools minus jq): `jq` line `[FAIL]`, **but the `ledger` check still reports correctly** (proving awk-based, not jq-based validation), exit 1. Guarded by an `ln -s` capability probe (skip with a note where symlinks are unavailable, same spirit as the pwsh guard).
6. **Non-git dir** — in a non-git tmp dir: `git` `[WARN]` (not a repo), `gitignore` `[OK]` (`n/a`); exit reflects only real fails.
7. **Parity** — bash vs `pwsh` byte-identical on the healthy fixture (skipped when `pwsh` absent, same guard as the suite).

## 9. Docs / version impact

- `skills/doctor/SKILL.md` — the `/ss-doctor` skill (run to verify a project; the verify leg paired with `/ss-init`). Lineage notes the init/doctor adoption track.
- **Re-link** `skills/init/SKILL.md`: change the plain-text `the planned /ss-doctor` back to the `[[ss-doctor]]` wikilink (it now resolves, so the linter passes).
- `README.md` — add `/ss-doctor` to the supporting-skills surface; skills count → **25**.
- `CHANGELOG.md` — `[Unreleased]` `### Added` entry.

## 10. Risks

- **jq-free ledger validation is structural, not semantic** — `^{.*}$` catches truncation/corruption but not a syntactically-valid line with a bad enum. Acceptable: the `ledger` writer validates enums on write; doctor's job is to flag obvious breakage, and staying jq-free is the higher priority.
- **`SUPERSTACK_DIR` override** — checks operate on the overridden dir, but display + the gitignore line use the literal `.superstack/` (documented, consistent with `ss-init`).
- **jq version string in the OK detail** — varies by machine, so behavior tests assert the line shape (regex), not an exact version; the parity test runs both twins on one machine where the version is identical.
- **Curated-PATH jq test portability** — symlink creation may be unavailable on some Windows shells; the test guards on `ln -s` capability and skips with a note (CI/Linux exercises it).
