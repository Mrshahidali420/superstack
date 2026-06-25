# /ss-trace — change provenance / lineage (v0.7.0+)

- **Date:** 2026-06-25
- **Status:** Approved (design)
- **Target version:** next release (`[Unreleased]`, the pending v0.7.0 cut); skills count → 28.
- **Related:** `/ss-replay` (ledger-events timeline), `/ss-report` (single-run stats), `/ss-audit` (gate pass/fail), `/ss-drift` (plan-vs-changed files). Reuses replay's UTC-ISO/time handling and ss-report's `merge-base` base resolution.

## 1. Context

The loop records its work in three independent places — **spec/plan docs** (`docs/specs/`, the *intent*), the **ledger** (`.superstack/ledger.jsonl`, the gate/*review trail*), and **git commits** (the *output*) — but **no command joins them**. `/ss-audit` checks gate pass/fail, `/ss-report` counts a run's stats, `/ss-replay` lists ledger events over time, `/ss-stats` trends across runs, `/ss-drift` diffs a plan's declared files against the changed set. None answers *"where did this change come from, and how was it built?"*.

`/ss-trace` is that view: a read-only **provenance "birth certificate"** for one change. Live research (2026-06-25) frames it. [Build provenance / SLSA](https://slsa.dev/spec/draft/build-provenance) is "a birth certificate for code — an audit trail answering *where did this come from?*" by "tying specific commits to the review audit trail." [Requirements-traceability practice](https://www.jamasoftware.com/requirements-management-guide/requirements-traceability/what-is-traceability/) adds the key insight: the win comes from **links built *as you work*, not a documentation matrix stitched together at the end**. SuperStack already produces those links (ledger gates + conventional commits + spec docs); `/ss-trace` simply *surfaces the trail* the loop recorded — joining intent → gate trail → commits into one chronological lineage.

## 2. Goals / Non-goals

**Goals**
- One read-only command that, for a single change, shows: its spec/plan docs (intent), its ledger gate/skip events **interleaved chronologically with the branch's git commits** (process + output), and an origin/birth-certificate footer.
- Derive every link from artifacts that already exist — no new recording, no manual matrix.
- Degrade gracefully when a piece is missing (no docs, no ledger, or a merged/deleted branch).
- Byte-identical bash (jq + git) + PowerShell (`ConvertFrom-Json` + git) twins; deterministic, parity-tested.

**Non-goals (deliberate)**
- A verdict — `/ss-trace` never passes/fails; it's a narrative (that's `/ss-audit` and `/ss-drift`).
- Single-run stats / counts (`/ss-report`) or a ledger-only timeline (`/ss-replay`).
- Per-file lineage or a requirement↔gate matrix (the two framings we rejected).
- Cryptographic attestation/signing, cross-change tracing, `--save` — YAGNI for v1.
- Reconstructing provenance for a long-merged change whose branch is gone *with full commit detail* — post-merge we show ledger-only lineage gracefully (see §5).

## 3. Repo facts relied on

- Ledger entry `{ts,change,phase,event,status,note}`, one JSON/line (`scripts/ledger`). `ts` = `YYYY-MM-DDTHH:MM:SSZ` (lexicographically sortable UTC). `event ∈ {enter,gate,skip,note}`, `status ∈ {pass,fail,skip,na}`. A run/change = entries sharing one `change` (git branch).
- Git commit UTC-ISO is obtained with `TZ=UTC git log <base>..<change> --date=format-local:'%Y-%m-%dT%H:%M:%SZ' --format='%cd%x09%h%x09%s'` → `<utc-iso>\t<sha7>\t<subject>` per commit, **same timestamp format as the ledger** → a single lexicographic sort interleaves both streams chronologically (no epoch math).
- Base resolution mirrors `scripts/ss-report:54`: default base `main`, falling back to `master`.
- Spec/plan docs live in `docs/specs/` named `YYYY-MM-DD-<slug>-{design,plan}.md` (`scripts/ss-drift` parses these; the slug is the feature name, e.g. `ss-trace`).
- House conventions: bash `jq … < "$ledger"`; ps1 `ConvertFrom-Json` + `tr -d '\r'` + ts re-normalization (ConvertFrom-Json coerces ISO `ts` → `[datetime]`); `${SUPERSTACK_DIR:-.superstack}`; ASCII-only; 54-dash separators; exit `0`/`1`/`2`; **`$PSNativeCommandUseErrorActionPreference=$false`** in the ps1 (it calls native git); `chk`/`newrepo` tests with fixed-timestamp ledgers; `tests/run.sh` now `[1/12]..[12/12]`.

## 4. CLI surface

```
ss-trace [<change>] [base]
```
- `<change>`: the branch / ledger-`change` to trace. Default: current branch (`git branch --show-current`); if empty (detached HEAD) → `default` (matching `ledger`'s own fallback).
- `base`: commit-range base. Default: `main`, falling back to `master` if `main` is absent. Commits = `git log <base>..<change>`.
- More than 2 args → stderr usage, **exit 1**. `jq` missing → stderr, **exit 2**.
- PowerShell: `ss-trace.ps1 [-Change <c>] [-Base <b>]`. Output identical.
- **Exit:** `0` always on success (read-only; never a gate — including the graceful "no trace" / "branch not found" cases); `1` usage; `2` missing jq.

## 5. Computation (the join)

**Intent** — derive `slug` from `<change>` by stripping any prefix up to and including the last `/` (`feat/ss-trace` → `ss-trace`). Glob `docs/specs/*<slug>*.md`, list matches sorted (`LC_ALL=C`). None → the literal line `  (no spec/plan docs found)`.

**Lineage** — build one tagged, chronologically-sorted stream from two sources:
- **Ledger** (gate/skip events for the change): jq filter `.change==$c and (.event=="gate" or .event=="skip")` → for each, a row `<ts>\tG\t<phase>\t<STATUS>\t<note>` where `STATUS = (.status|ascii_upcase)` (`PASS`/`FAIL`/`SKIP`).
- **Commits** (`git log <base>..<change>`, UTC-ISO as above): for each, a row `<ts>\tC\t<sha7>\t<subject>`.
- Concatenate, **sort by the whole line under `LC_ALL=C` / `[StringComparer]::Ordinal`** (ts is the leading fixed-width field, so this orders by time; the `G`/`C` type tag is a deterministic, twin-identical tie-break when a gate and a commit share a timestamp — `C` sorts before `G`).

**Origin footer** — `origin: <change>   gates: <Ng>   commits: <Nc>   files: <Nf>   head: <sha7>` where `Ng` = count of lineage gate/skip rows, `Nc` = commit rows, `Nf` = `git diff --name-only <base>..<change> | wc -l`, `head` = `git rev-parse --short <change>`.

**Graceful degradation:**
- `<change>` is **not a resolvable git ref** (e.g. merged & deleted): `git log`/`diff`/`rev-parse` yield nothing → omit commit rows, set `commits: 0`, `files: 0`, `head: n/a`, and emit a `  (branch '<change>' not found; git commits omitted)` note in the lineage block. Ledger entries persist by name, so the ledger lineage + intent docs still render. Exit 0.
- **Neither** ledger gate/skip events **nor** commits exist for the change → after the header/separator, print `ss-trace: no trace for <change>` and exit 0.
- Empty ledger but commits exist → commit-only lineage, `gates: 0`. And vice-versa.

All timestamps are compared as UTC-ISO strings; no locale/epoch arithmetic. The `git log`/`rev-parse` calls tolerate a missing ref (bash: `2>/dev/null || true`; ps1: `$PSNativeCommandUseErrorActionPreference=$false`).

## 6. Output (ASCII, byte-identical twins)

```
ss-trace: provenance for feat/ss-stats
------------------------------------------------------
intent:
  docs/specs/2026-06-25-ss-stats-design.md
  docs/specs/2026-06-25-ss-stats-plan.md
------------------------------------------------------
lineage (gates + commits, chronological):
  06-25 10:30  plan     PASS
  06-25 11:00  *        f50ca7d  feat(stats): add ss-stats bash
  06-25 11:40  review   PASS   no critical/high
  06-25 12:00  *        0a6a278  feat(stats): PowerShell parity
  06-25 12:30  secure   PASS
------------------------------------------------------
origin: feat/ss-stats   gates: 4   commits: 3   files: 9   head: f57454e
```

- **Header:** `ss-trace: provenance for <change>`, then a 54-dash separator.
- **intent:** the label `intent:` then one `  <path>` per matched doc (or `  (no spec/plan docs found)`), then a separator.
- **lineage:** the label `lineage (gates + commits, chronological):` then the sorted rows, then a separator. Row formats (time = `<ts[5:10]> <ts[11:16]>` = `MM-DD HH:MM`):
  - gate/skip: `  %s  %-8s %-5s %s` → time, phase, STATUS, note (trailing-space-trimmed).
  - commit: `  %s  %-8s %s  %s` → time, `*`, sha7, subject.
  - the graceful `  (branch '<change>' not found; git commits omitted)` note (ASCII only — no em-dash) appears here when applicable.
- **origin footer:** the birth-certificate line (3 spaces between fields).
- **no-trace:** header, separator, then `ss-trace: no trace for <change>`. Exit 0.

## 7. Parity mechanics

bash uses `jq … < "$ledger"` + `git log`/`git diff`/`git rev-parse`, merges the tagged rows, and sorts with `LC_ALL=C sort`. ps1 uses `ConvertFrom-Json` (with `ts` re-normalized to the canonical `yyyy-MM-ddTHH:mm:ssZ` string before any compare/slice), the same `git log` invocation (it sets `$env:TZ='UTC'` for the child git call, or uses `--date=format-local` which honours `TZ`), and sorts the tagged rows with `[System.StringComparer]::Ordinal` (NOT culture-aware `Sort-Object`). `$PSNativeCommandUseErrorActionPreference=$false` is set early so git's non-zero exit on a missing ref returns gracefully instead of throwing. The time slice (`MM-DD HH:MM`), the row `printf`/`-f` widths, the `slug` derivation, the `G`/`C` tie-break, and the footer field formats are defined identically. The `subject` is taken as-is from git (first line only via `%s`); any non-ASCII in a real subject is the user's commit text — fixtures use ASCII subjects.

## 8. Test plan

New `tests/trace.test.sh`, wired into `tests/run.sh` (`[12/12]`→`[13/13]`). A `newrepo`-style fixture with **fixed commit timestamps** (`GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`) + a seeded fixed-timestamp ledger makes the interleave deterministic.

1. **Interleave order** — seed gates and commits at known interleaved timestamps; assert the lineage rows appear in the exact chronological order, with commits marked `*` and gates showing `PHASE STATUS`.
2. **Intent glob** — a `docs/specs/*-<slug>-*.md` pair is listed under `intent:`; a change with no matching docs → `(no spec/plan docs found)`.
3. **Footer** — `origin: <change>   gates: N   commits: M   files: F   head: <sha7>` matches the fixture (gates counts gate+skip rows; SKIP event rendered `SKIP`).
4. **Graceful: branch not found** — trace a `<change>` that has ledger entries but is not a git ref → ledger-only lineage + the `(branch ... not found ...)` note + `commits: 0   files: 0   head: n/a`, exit 0.
5. **No trace** — a change with neither events nor commits → `ss-trace: no trace for <change>`, exit 0; `>2` args → exit 1.
6. **Parity** — bash vs `pwsh` byte-identical on the main interleave fixture and on the branch-not-found fixture (skipped when `pwsh` absent, same guard as the suite).

## 9. Docs / version impact

- `skills/trace/SKILL.md` — the `/ss-trace` skill. Lineage notes it as the provenance/"birth-certificate" view that joins intent ([[ss-frame]] specs) ↔ the gate trail ([[ss-audit]]) ↔ commits; distinct from [[ss-replay]] (ledger-only timeline) and [[ss-report]] (stats). (Only wikilink skills that exist: `ss-frame`, `ss-audit`, `ss-replay`, `ss-report` all do.)
- `README.md` — add `/ss-trace` to the supporting-skills inline list (after `/ss-stats`); skills count → **28**.
- `CHANGELOG.md` — `[Unreleased]` `### Added` entry (joins the `/ss-stats` entry already there for the v0.7.0 cut).

## 10. Risks

- **Cross-source parity (ledger jq ↔ git ↔ ps1)** — the highest-risk surface; mitigated by the shared UTC-ISO string representation (one lexicographic/Ordinal sort, no epoch/locale math), the `G`/`C` tie-break, fixed commit + ledger timestamps in the fixture, and a parity test.
- **slug-glob over/under-matching** — a short slug could match unrelated specs, or a renamed branch could miss its docs. Acceptable v1 heuristic (display-only; the lineage/footer are unaffected); documented. The intent block degrades to `(no spec/plan docs found)` rather than failing.
- **Merged/deleted branch** — full commit detail is unavailable post-merge; trace degrades to ledger-only lineage with an explicit note (the common, valuable case is an active or just-finished branch).
- **Timestamp ties** — a gate and a commit at the same second are ordered deterministically by the `C`-before-`G` type tag, identical across twins.
