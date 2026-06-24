# /ss-replay — loop replay (the "story" leg) (v0.5.0)

- **Date:** 2026-06-24
- **Status:** Approved (design)
- **Target version:** v0.5.0 (minor; new skill + script, additive)
- **Related:** [2026-06-23-ss-evolve-design.md](2026-06-23-ss-evolve-design.md), the `ledger` / `ss-audit` / `ss-report` trio.

## 1. Context

The SuperStack proof-of-process story has two of three legs:
- **`/ss-audit`** — the *gate* (did the loop run? block ship if not).
- **`/ss-report`** — the *aggregate stats* (phases, timing, change size as a shareable summary).

Missing is the third leg: a **chronological narrative of a single run** — what happened, in order, with the friction beats (gate failures, retries, skips) called out. `/ss-replay` reads `.superstack/ledger.jsonl` and reconstructs that story.

Research backing (live, 2026-06-24): CLI-UX guidance is that output should "tell a clear, detailed story of the command's execution"; CI trace/flame-graph views surface bottlenecks by **duration**; the interesting beats are the **anomalies** (fails/retries/skips), not the happy path; keep it plain, grep-friendly, `NO_COLOR`-safe text (we are ASCII-only, so that is free). Sources: Evil Martians CLI-UX, Datadog CI Visibility, asciinema, DebugBear waterfall.

## 2. Goals / Non-goals

**Goals**
- Turn one run's ledger entries into a readable, copy-pasteable ASCII timeline.
- Show **elapsed-since-start** per event (where the time/friction went) and tag **retries**.
- A one-line footer of "story stats" (phases, gate-retries, skips, open-fails, total span).
- Byte-identical bash + PowerShell twins; deterministic, parity-tested.

**Non-goals (deferred)**
- `--json` (replay is for humans; `/ss-report` and the raw ledger already serve machines).
- `--all` (replay every run at once) — default-to-latest + `--change` covers the common case.
- Duration *bar charts* / waterfalls — an elapsed column is enough; bars add parity surface for little gain.

## 3. Ledger facts relied on

- One JSON object per line: `{ts, change, phase, event, status, note}` (`scripts/ledger`).
- `ts` is `date -u +%Y-%m-%dT%H:%M:%SZ` (zero-padded UTC ISO-8601); `jq fromdateiso8601` parses it to epoch seconds (verified). PowerShell `ConvertFrom-Json` coerces `ts` to `[datetime]` (same coercion handled in `--since`).
- `event` ∈ `enter | gate | skip | note`; `status` ∈ `pass | fail | skip | na`.
- `change` = the git branch; **a "run" = all entries sharing one `change`**, in file order (append-only ⇒ file order is chronological).

## 4. CLI surface

```
ss-replay [--change <branch>] [--save]
```
- **Default (no `--change`):** replay the **latest run** = the `change` of the last ledger entry.
- `--change <branch>`: replay that specific run.
- `--save`: also write the replay to `<dir>/replays/<safe-change>.md` (a fenced code block so alignment survives Markdown rendering) and print `saved -> .superstack/replays/<safe-change>.md`. `<safe-change>` = `change` with `/` replaced by `-`.
- Native flag style per platform: bash `--change`/`--save`; PowerShell `-Change`/`-Save`. Output identical.
- Unknown flag → stderr usage, exit 1.

## 5. Computation

For the selected run's rows (chronological), with `t0` = first row's epoch:

- **elapsed** (per row) = `epoch(ts) - t0`, in seconds (cumulative from run start). bash: jq `fromdateiso8601`; PowerShell: `($_.ts - $t0).TotalSeconds` (both already `[datetime]` after `ConvertFrom-Json`).
- **marker** (per row) = `status` upper-cased, except `na`/null → empty. So gate-pass→`PASS`, gate-fail→`FAIL`, skip→`SKIP`, enter/note→`` (blank).
- **retry** (per row) = `true` when this row is a gate-pass **and** an earlier row in the same run is a gate-fail for the **same phase**. Computed in jq for bash (prior-fail lookup over `$rows[0:$i]`) and inline in PowerShell (a hashtable of phases seen failing). Avoids bash associative arrays (macOS bash 3.2 lacks them).
- **Duration formatter** (single-sourced per twin, byte-identical): given whole seconds `s`, let `m = floor(s/60)`. If `m < 60` → `+<m>m`; else → `+<m/60>h<m%60>m`. Examples: `0→+0m`, `1770→+29m`, `3720→+1h2m`. Hours may exceed 24 (no day rollover — rare, acceptable).

**Footer stats** (computed over the run):
- `phases` = count of distinct `phase` values appearing in the run (any event) — robust to runs that don't log an `enter` for every phase.
- `gate-retries` = count of rows where `retry` is true.
- `skips` = count of `skip` events.
- `open-fails` = count of phases whose **last** gate event is a `fail` (never recovered).
- `total` = elapsed of the last row, run through the duration formatter.

## 6. Output format (ASCII, byte-identical)

```
loop replay: feat/loop-replay
------------------------------------------------------
   +0m   FRAME    enter
   +3m   PLAN     enter
   +3m   PLAN     gate   PASS   spec approved
  +29m   BUILD    enter
  +56m   REVIEW   gate   FAIL   2 findings
  +68m   REVIEW   gate   PASS   (retry) fixed
  +70m   SHIP     gate   PASS   CI green
  +70m   SECURE   skip   SKIP   no IO in diff
------------------------------------------------------
phases: 6   gate-retries: 1   skips: 1   open-fails: 0   total: ~70m
```

- **Header:** `loop replay: <change>` then a separator of exactly 54 `-`.
- **Row:** elapsed right-aligned width 6, two spaces, phase left width 7, space, event left width 5, space, marker left width 4, space, note. `(retry) ` prefixes the note when `retry` is true.
- **Footer:** the fixed-label stats line (no pluralization → no parity ambiguity), preceded by the separator.
- **No run found** (missing ledger, or `--change` with no matching rows): print `ss-replay: no run to replay` (default) or `ss-replay: no run found for <change>` (explicit `--change`) and exit 0.

The exact printf format strings and PowerShell formatters are specified in the implementation plan; both twins MUST emit byte-identical text (verified by a parity test).

## 7. Parity mechanics

Same patterns as the rest of the suite: bash reads the ledger via `jq … < "$ledger"`; strip `\r` with `tr -d '\r'`; ASCII only; PowerShell parses with `ConvertFrom-Json`, normalizes the `ts` coercion, and uses `Write-Output`. The duration formatter and column widths are defined identically in both twins.

## 8. Test plan

New `tests/replay.test.sh`, wired into `tests/run.sh` (bumping `[N/7]`→`[N/8]`). All seeds use **fixed, hand-written ledger timestamps** so elapsed/footer are deterministic.

1. **Latest-run default** — seed two runs (two `change` values); `ss-replay` (no flag) replays only the most recent run's rows.
2. **`--change` selection** — `--change <older>` replays the older run, not the latest.
3. **Elapsed + formatter** — rows show the expected `+0m` / `+29m` / `+1h2m` given seeded gaps (covers the `<60m` and `>=60m` branches).
4. **Marker mapping** — gate-pass→`PASS`, gate-fail→`FAIL`, skip→`SKIP`, enter→blank.
5. **Retry tag** — a phase with gate-fail then gate-pass shows `(retry)` on the pass; a clean pass does not.
6. **Footer stats** — `phases` / `gate-retries` / `skips` / `open-fails` / `total` match the seed (incl. an `open-fails: 1` case where a phase's last gate is a fail).
7. **No run** — empty/absent ledger → `no run to replay`; bad `--change` → `no run found for <branch>`.
8. **`--save`** — writes `<dir>/replays/<safe-change>.md` (fenced), prints the path; `/` in branch → `-` in filename.
9. **Parity** — bash vs `pwsh` byte-identical for default replay and `--change` (skipped when `pwsh` absent, same guard as the suite).

## 9. Docs / version impact

- `skills/replay/SKILL.md` — the `/ss-replay` skill (Frame-to-Learn loop: replay belongs near `/ss-report` / `/ss-learn`); Lineage notes the proof trio.
- `README.md` — add `/ss-replay` to the proof/commands surface ("23 skills").
- `CHANGELOG.md` — `[Unreleased]` → `[0.5.0]` Added.
- `.claude-plugin/plugin.json` + `marketplace.json` — version bump + skills count at release time.

## 10. Risks

- **`ts` format dependency** — elapsed assumes the `scripts/ledger` `ts` format; documented, and the test seeds assert it.
- **PowerShell `ts` coercion** — `ConvertFrom-Json` turns `ts` into `[datetime]`; the twin must compute elapsed from the `[datetime]` (as `--since` already does), not from a string.
- **Interleaved runs** — if two branches' entries interleave in the ledger, filtering by `change` still collects one run's rows in chronological (file) order; elapsed is computed within the selected run only.
- **Custom phase names longer than the column width** print without truncation (slight misalignment) — acceptable; SuperStack's own phases are ≤ 6 chars.
