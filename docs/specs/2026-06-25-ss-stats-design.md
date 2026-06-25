# /ss-stats — cross-run loop analytics (v0.7.0+)

- **Date:** 2026-06-25
- **Status:** Approved (design)
- **Target version:** next release (`[Unreleased]`); skills count → 27.
- **Related:** `/ss-report` (single-run summary), `/ss-replay` (single-run timeline), `/ss-evolve` (pattern detection → action), the `/ss-retro` reflection skill (can consume this). Reuses evolve's `--since` parser and replay's span formatter.

## 1. Context

SuperStack records every gate to the ledger, and `/ss-report` / `/ss-replay` turn *one run* into a summary/timeline. What's missing is the **cross-run** view: across the last N runs, is the process getting better? `/ss-stats` is that read-only dashboard.

Live research (2026-06-25) shapes it. The [DORA](https://getdx.com/blog/dora-metrics/) metrics map onto the ledger: **gate-fail rate** ≈ change-failure rate, run cadence ≈ deployment frequency, run span ≈ lead time. The governing lessons: **"the trend matters more than the absolute number — is it improving? Compare against your own history, not benchmarks."** And the vanity-metric / Goodhart warning: **"frequency in isolation is a vanity metric… never read without change-failure-rate next to it"** — so cadence is always shown beside quality, and the numbers are reflection signal, not a gameable target. ASCII-only rules out Unicode sparklines, so the presentation is a **per-run table + a worded trend** (improving/worsening/flat).

## 2. Goals / Non-goals

**Goals**
- One read-only command that aggregates the ledger across runs into a per-run table + a trend rollup.
- Emphasize **direction** (improving/worsening/flat) over absolute counts; pair cadence with gate-fail rate.
- Reuse evolve's `--since` window and replay's metric/format definitions for consistency.
- Byte-identical bash (jq) + PowerShell (`ConvertFrom-Json`) twins; deterministic, parity-tested.

**Non-goals (deliberate)**
- **Per-phase recurring-pattern detection** — that's `/ss-evolve` (which then *acts*). `/ss-stats` is read-only aggregate reporting only; it never flags "phase X keeps failing" or drafts fixes.
- Single-run detail — that's `/ss-report` / `/ss-replay`.
- Unicode sparklines/charts, `--json`, benchmark comparisons — YAGNI / ASCII-only.
- A gate — `/ss-stats` never fails the build; a "bad" trend is informational.

## 3. Repo facts relied on

- Ledger entry `{ts,change,phase,event,status,note}`, one JSON per line (`scripts/ledger`). `ts` is `YYYY-MM-DDTHH:MM:SSZ` (lexicographically sortable). `event ∈ {enter,gate,skip,note}`, `status ∈ {pass,fail,skip,na}`.
- A **run** = all entries sharing one `change` (git branch). Runs are ordered chronologically by each run's **first `ts`**.
- Reused definitions: span formatter = `+<floor(seconds/60)>m` (minutes-only, `scripts/ss-replay:23`); `--since <Nd|Nh|YYYY-MM-DD>` cutoff = jq `now - $off | todate` (bash) / `[DateTime]::UtcNow.AddDays/AddHours` (ps1), then lexicographic `.ts >= cutoff` (`scripts/ss-evolve`).
- House conventions: bash reads `jq … < "$ledger"`; ps1 uses `ConvertFrom-Json` + `tr -d '\r'`; `${SUPERSTACK_DIR:-.superstack}`; ASCII-only; 54-dash separators; exit `0` success / `1` usage / `2` missing-jq (sibling convention); `chk`/`newrepo` tests with fixed-timestamp seeded ledgers (`tests/replay.test.sh`); `tests/run.sh` now `[1/11]..[11/11]`.

## 4. CLI surface

```
ss-stats [--since <Nd|Nh|YYYY-MM-DD>] [--limit N]
```
- `--since`: restrict to runs whose entries fall in the window (cutoff applied per-entry, lexicographic). Default: all.
- `--limit N`: cap the **per-run table** to the N most recent runs (default `10`). The **rollup spans the full window** regardless of `--limit`.
- Unknown flag / bad `--since` / bad `--limit` (non-positive-integer) → stderr usage, **exit 1**. `jq` missing (bash) → stderr, **exit 2**.
- Absent/empty ledger → `ss-stats: no runs yet`; a non-empty ledger whose runs are all filtered out by `--since` → `ss-stats: no runs in window`. Either way exit 0.
- PowerShell: `-Since`, `-Limit`. Output identical.
- **Exit:** `0` always on success (read-only; never a gate); `1` usage; `2` missing jq.

## 5. Computation

Filter entries by the `--since` cutoff (lexicographic `ts >= cutoff`), then group into runs by `change`, ordered by each run's first `ts` (ascending). **Per run:**
- `change` — the run's branch.
- `date` — `substr(first_ts, 6, 5)` → `MM-DD`.
- `phases` — count of distinct `phase` values in the run (any event).
- `fails` — count of entries with `event=="gate" and status=="fail"`.
- `skips` — count of entries with `event=="skip"`.
- `span` — `+<floor((last_ts_epoch - first_ts_epoch)/60)>m` (replay's formatter).

**Rollup** (over all runs in the window, not limited by `--limit`):
- `runs` — number of runs.
- `gates` — count of all `event=="gate"` entries; `fails` — count of gate-fails; **gate-fail rate** = `floor(100*fails/gates)%` shown as `<r>% (<fails>/<gates>)`. If `gates==0` → `n/a (0 gates)`. (Floor, not round — identical in jq `floor` and `[math]::Floor`, avoiding rounding-mode mismatch.)
- `skips` — total skip events in the window.
- **trend** — needs `runs >= 4`, else `n/a`. Split the chronologically-ordered runs into older half `runs[0 : floor(n/2)]` and newer half `runs[floor(n/2) : n]`. Let `(fo,go)` and `(fn,gn)` be (gate-fails, gates) summed over each half. If `go==0 or gn==0` → `n/a`. Else compare via integer cross-multiplication (exact, no floats): `fn*go < fo*gn` → **improving**; `>` → **worsening**; `==` → **flat**. (Improving = the newer half has a lower gate-fail rate.)

All arithmetic is integer; the span uses floor-division; the rate uses floor — so bash (jq) and ps1 (`[math]::Floor`, integer ops) produce identical numbers.

## 6. Output (ASCII, byte-identical twins)

```
ss-stats: loop trends
------------------------------------------------------
runs: 5   window: all
------------------------------------------------------
change          date    phases  fails  skips  span
feat/ss-drift   06-24   6       0      1      +70m
feat/ss-doctor  06-24   6       1      0      +52m
feat/ss-replay  06-24   7       1      1      +66m
feat/ss-evolve  06-24   5       0      0      +38m
feat/ss-report  06-23   6       1      2      +44m
------------------------------------------------------
gate-fail rate: 12% (3/24)   skips: 4   trend: improving
```
Empty:
```
ss-stats: loop trends
------------------------------------------------------
ss-stats: no runs yet
```

- **Header:** `ss-stats: loop trends`, then a 54-dash separator.
- **Window line:** `runs: <n>   window: <all | since <arg>>` (3 spaces between fields), then a separator.
- **Table:** a header row then one row per run (most recent first, capped at `--limit`), fixed columns: `change` left-truncated to 15 chars in a width-16 field, `date` width-8, `phases` width-8, `fails` width-7, `skips` width-7, `span`. Format `'%-16s%-8s%-8s%-7s%-7s%s'` (bash) / `'{0,-16}{1,-8}{2,-8}{3,-7}{4,-7}{5}'` (ps1). Then a separator.
- **Rollup line:** `gate-fail rate: <r>% (<fails>/<gates>)   skips: <n>   trend: <improving|worsening|flat|n/a>` (3 spaces between fields). When `gates==0`: `gate-fail rate: n/a (0 gates)   skips: <n>   trend: n/a`.
- **Empty case:** header, separator, then `ss-stats: no runs yet` (absent/empty ledger) or `ss-stats: no runs in window` (everything filtered out by `--since`) — no table/rollup. Exit 0.

## 7. Parity mechanics

bash uses `jq … < "$ledger"` for grouping/aggregation; ps1 uses `ConvertFrom-Json` + `Group-Object change` + integer arithmetic. The span formatter, the floor-based rate, the trend cross-multiplication, the `MM-DD` slice, and the fixed column widths are defined identically. ps1 strips `\r` (`-replace "\r",""` per line / `tr -d '\r'` in the test) and re-normalizes the `ts` if `ConvertFrom-Json` coerces it (same handling as `ss-evolve --since`). The run ordering is by first `ts` (a total order on distinct fixed timestamps); ties are broken by `change` ascending (byte order) so both twins agree.

## 8. Test plan

New `tests/stats.test.sh`, wired into `tests/run.sh` (`[N/11]`→`[N/12]`). A seeded ledger with **fixed timestamps** across several runs makes every metric deterministic.

1. **Per-run table** — a 5-run seeded ledger: rows appear most-recent-first; each row's `phases`/`fails`/`skips`/`span` match the seed; `date` is the `MM-DD` of the run's first entry.
2. **Rollup rate** — `gate-fail rate: <r>% (<fails>/<gates>)` matches the seed (incl. a `gates==0` window → `n/a (0 gates)`).
3. **Trend** — seed an improving sequence (older runs fail more than newer) → `trend: improving`; a worsening seed → `worsening`; a `<4`-run seed → `n/a`.
4. **`--limit`** — `--limit 2` shows 2 table rows but the rollup still counts all runs.
5. **`--since`** — `--since 1d` (or a date) drops older runs from both table and rollup; verify count drops.
6. **Empty** — absent/empty ledger → `no runs yet`, exit 0; bad `--limit 0`/`--limit x` → exit 1.
7. **Parity** — bash vs `pwsh` byte-identical on the 5-run fixture and on a `--limit`+`--since` invocation (skipped when `pwsh` absent, same guard as the suite).

## 9. Docs / version impact

- `skills/stats/SKILL.md` — the `/ss-stats` skill (run periodically, or feed `/ss-retro`). Lineage notes it as the cross-run companion to `/ss-report` (one run) and a read-only dashboard distinct from `/ss-evolve`.
- `README.md` — add `/ss-stats` to the supporting-skills surface; skills count → **27**.
- `CHANGELOG.md` — `[Unreleased]` `### Added` entry.

## 10. Risks

- **jq↔ConvertFrom-Json parity on aggregation** — the most error-prone part; mitigated by all-integer arithmetic (floor div, cross-multiplication), identical column widths, and a parity test on a fixed-timestamp fixture.
- **Run ordering ties** — distinct fixed timestamps avoid ties in practice; the `change`-ascending tiebreak makes any tie deterministic across twins.
- **Trend on small N** — `<4` runs → `n/a` (a 1-vs-1 "trend" is noise; the research values real direction, not single-run swings). Threshold documented; tunable later.
- **`change` truncation** — branch names > 15 chars are truncated in the table (display only; the rollup is unaffected). Acceptable; the full name is in the ledger.
