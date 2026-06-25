# /ss-stats (cross-run loop analytics) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/ss-stats` — a read-only cross-run analytics command (bash `scripts/ss-stats` using jq + PowerShell twin using `ConvertFrom-Json`, skill, tests, docs) that aggregates the ledger into a per-run table + a trend rollup.

**Architecture:** Group ledger entries by `change` into runs (ordered by first `ts`); per run derive phases/fails/skips/span; render the most-recent N as a table and a rollup (runs, gate-fail rate, skips, improving/worsening/flat trend). All arithmetic is integer (floor division, integer cross-multiplication) so jq and PowerShell produce byte-identical numbers.

**Tech Stack:** Bash + `jq`; PowerShell 7 (`ConvertFrom-Json`); the `chk`/`newrepo` harness with a fixed-timestamp seeded ledger.

## Global Constraints

(Verbatim from the spec; every task implicitly includes these.)

- **Byte-identical ASCII stdout** across `scripts/ss-stats` (bash/jq) and `scripts/ss-stats.ps1` (PowerShell). No Unicode.
- **Read-only, never a gate.** CLI `ss-stats [--since <Nd|Nh|YYYY-MM-DD>] [--limit N]` (PowerShell `-Since`/`-Limit`). Exit `0` always on success; `1` usage (unknown flag, bad `--since`, non-positive-integer `--limit`); `2` missing `jq` (bash only).
- A **run** = entries sharing one `change`; runs ordered by first `ts` ascending (tiebreak `change` ascending). `--limit` (default `10`) caps the **table** only; the **rollup spans the full window**.
- **Per run:** `change`; `date` = `MM-DD` of first ts (`ts[5:10]`); `phases` = distinct phase count (any event); `fails` = `event==gate && status==fail` count; `skips` = `event==skip` count; `span` = `+<floor((lastEpoch-firstEpoch)/60)>m`.
- **Rollup:** `runs`; `gates` = all `event==gate`; `fails` = gate-fails; **gate-fail rate** = `floor(100*fails/gates)% (fails/gates)`, or `n/a (0 gates)` when `gates==0`; `skips` total; **trend** needs `runs>=4` (else `n/a`): split chronological runs into older `[0:floor(n/2)]` and newer `[floor(n/2):n]`; with `(fo,go)`,`(fn,gn)` summed per half, `n/a` if `go==0||gn==0`, else `fn*go < fo*gn`→`improving`, `>`→`worsening`, `==`→`flat`.
- **Output:** header `ss-stats: loop trends`, 54-dash separator, `runs: <n>   window: <all|since <arg>>`, separator, table (header + rows), separator, rollup line. Empty: header, separator, `ss-stats: no runs yet` (absent/empty ledger) or `ss-stats: no runs in window` (filtered empty).
- **Table format:** `'%-16s%-8s%-8s%-7s%-7s%s'` (bash) / `'{0,-16}{1,-8}{2,-8}{3,-7}{4,-7}{5}'` (ps1); `change` truncated to 15 chars; columns `change date phases fails skips span`.
- **Rollup line:** `gate-fail rate: <r>% (<f>/<g>)   skips: <s>   trend: <t>` (3 spaces between fields), or `gate-fail rate: n/a (0 gates)   skips: <s>   trend: <t>`.
- Reuse evolve's `--since` parser and the `--ts` lexicographic compare; ps1 must **re-normalize `ts`** (ConvertFrom-Json coerces ISO strings to `[datetime]`) to the canonical `yyyy-MM-ddTHH:mm:ssZ` string before any compare.
- Commits: conventional-commit, no AI attribution. Ships next release (`[Unreleased]`); skills → 27.

Reference siblings: `scripts/ss-replay` (jq + U+001F row separator, span formatter, ts handling), `scripts/ss-evolve` (`--since` parser, ps1 ts re-normalization), `scripts/ss-doctor` (style, exit codes). Spec: `docs/specs/2026-06-25-ss-stats-design.md`.

---

## File Structure

- `scripts/ss-stats` — bash/jq (Task 1)
- `scripts/ss-stats.ps1` — PowerShell twin (Task 2)
- `tests/stats.test.sh` — behavior tests (Task 1) + parity test (Task 2)
- `tests/run.sh` — wire `[12/12]`, bump `[N/11]`→`[N/12]` (Task 1)
- `skills/stats/SKILL.md` — the skill (Task 3)
- `README.md`, `CHANGELOG.md` — surface it (Task 4)

---

## Task 1: `scripts/ss-stats` (bash/jq) + tests + run.sh wiring

**Model:** sonnet.

**Files:**
- Create: `scripts/ss-stats`
- Create: `tests/stats.test.sh`
- Modify: `tests/run.sh`

**Interfaces:**
- Produces: `scripts/ss-stats [--since W] [--limit N]` printing the dashboard + exit 0/1/2.
- Consumes: `jq`, the ledger at `${SUPERSTACK_DIR:-.superstack}/ledger.jsonl`.

- [ ] **Step 1: Write the failing tests** — create `tests/stats.test.sh`

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavior + parity tests for scripts/ss-stats.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }
J() { printf '{"ts":"%s","change":"%s","phase":"%s","event":"%s","status":"%s","note":""}\n' "$1" "$2" "$3" "$4" "$5"; }

# 5-run fixture (deterministic): r1..r5. Returns the dir.
mkfix() {
  local d; d="$(mktemp -d)"; local L="$d/.superstack"; mkdir -p "$L"
  {
    J 2026-06-20T00:00:00Z r1 plan   gate pass
    J 2026-06-20T00:15:00Z r1 build  gate pass
    J 2026-06-20T00:30:00Z r1 review gate fail
    J 2026-06-21T00:00:00Z r2 plan   gate pass
    J 2026-06-21T00:20:00Z r2 build  gate pass
    J 2026-06-22T00:00:00Z r3 plan   gate pass
    J 2026-06-22T00:20:00Z r3 review gate fail
    J 2026-06-22T00:40:00Z r3 secure skip skip
    J 2026-06-23T00:00:00Z r4 plan   gate pass
    J 2026-06-23T00:10:00Z r4 build  gate pass
    J 2026-06-23T00:25:00Z r4 ship   gate pass
    J 2026-06-24T00:00:00Z r5 plan   gate pass
    J 2026-06-24T00:10:00Z r5 plan   note na
  } > "$L/ledger.jsonl"
  printf '%s' "$d"
}

# --- full table + rollup ---
D="$(mkfix)"; export SUPERSTACK_DIR="$D/.superstack"
out="$(bash "$ROOT/scripts/ss-stats")"; rc=$?
chk "runs/window line"  'printf "%s" "$out" | grep -qF "runs: 5   window: all"'
chk "row r5"  'printf "%s" "$out" | grep -qE "^r5 +06-24 +1 +0 +0 +\+10m"'
chk "row r3"  'printf "%s" "$out" | grep -qE "^r3 +06-22 +3 +1 +1 +\+40m"'
chk "row r1"  'printf "%s" "$out" | grep -qE "^r1 +06-20 +3 +1 +0 +\+30m"'
chk "table order r5 before r1" 'printf "%s" "$out" | awk "/^r5 /{a=NR} /^r1 /{b=NR} END{exit !(a&&b&&a<b)}"'
chk "rollup"  'printf "%s" "$out" | grep -qF "gate-fail rate: 18% (2/11)   skips: 1   trend: improving"'
chk "exit 0"  '[ "$rc" -eq 0 ]'

# --- --limit caps table, not rollup ---
outl="$(bash "$ROOT/scripts/ss-stats" --limit 2)"
chk "limit shows r5"     'printf "%s" "$outl" | grep -qE "^r5 "'
chk "limit shows r4"     'printf "%s" "$outl" | grep -qE "^r4 "'
chk "limit hides r3"     '! printf "%s" "$outl" | grep -qE "^r3 "'
chk "limit rollup full"  'printf "%s" "$outl" | grep -qF "gate-fail rate: 18% (2/11)"'

# --- --since drops older runs from table AND rollup; small-n trend n/a ---
outs="$(bash "$ROOT/scripts/ss-stats" --since 2026-06-23)"
chk "since runs 2"     'printf "%s" "$outs" | grep -qF "runs: 2   window: since 2026-06-23"'
chk "since drops r3"   '! printf "%s" "$outs" | grep -qE "^r3 "'
chk "since rate"       'printf "%s" "$outs" | grep -qF "gate-fail rate: 0% (0/4)"'
chk "since trend n/a"  'printf "%s" "$outs" | grep -qF "trend: n/a"'

# --- worsening trend (4-run fixture) ---
W="$(mktemp -d)"; mkdir -p "$W/.superstack"
{ J 2026-06-20T00:00:00Z w1 plan gate pass
  J 2026-06-21T00:00:00Z w2 plan gate pass
  J 2026-06-22T00:00:00Z w3 plan gate fail
  J 2026-06-23T00:00:00Z w4 plan gate fail; } > "$W/.superstack/ledger.jsonl"
export SUPERSTACK_DIR="$W/.superstack"
outw="$(bash "$ROOT/scripts/ss-stats")"
chk "worsening trend" 'printf "%s" "$outw" | grep -qF "trend: worsening"'

# --- empty + bad inputs ---
E="$(mktemp -d)"; export SUPERSTACK_DIR="$E/.superstack"
oute="$(bash "$ROOT/scripts/ss-stats")"; rce=$?
chk "empty no runs yet" 'printf "%s" "$oute" | grep -qF "ss-stats: no runs yet"'
chk "empty exit 0"      '[ "$rce" -eq 0 ]'
export SUPERSTACK_DIR="$D/.superstack"
( bash "$ROOT/scripts/ss-stats" --limit 0 ) >/dev/null 2>&1; chk "limit 0 exit 1" '[ "$?" -eq 1 ]'
( bash "$ROOT/scripts/ss-stats" --limit x ) >/dev/null 2>&1; chk "limit x exit 1" '[ "$?" -eq 1 ]'
( bash "$ROOT/scripts/ss-stats" --bogus ) >/dev/null 2>&1; chk "bad flag exit 1" '[ "$?" -eq 1 ]'
outn="$(bash "$ROOT/scripts/ss-stats" --since 2030-01-01)"
chk "no runs in window" 'printf "%s" "$outn" | grep -qF "ss-stats: no runs in window"'

echo
[ "$fail" -eq 0 ] && echo "STATS TESTS PASS" || echo "STATS TESTS FAILED"
exit "$fail"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/stats.test.sh`
Expected: FAIL — `scripts/ss-stats` does not exist yet.

- [ ] **Step 3: Write `scripts/ss-stats`**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Cross-run loop analytics from the ledger (read-only).
# Usage: ss-stats [--since <Nd|Nh|YYYY-MM-DD>] [--limit N]   Exit: 0 ok, 1 usage, 2 missing jq.
set -uo pipefail
export LC_ALL=C
dir="${SUPERSTACK_DIR:-.superstack}"
ledger="$dir/ledger.jsonl"

since=""; limit=10
while [ "$#" -gt 0 ]; do
  case "$1" in
    --since) since="${2:-}"; shift 2;;
    --since=*) since="${1#*=}"; shift;;
    --limit) limit="${2:-}"; shift 2;;
    --limit=*) limit="${1#*=}"; shift;;
    *) echo "ss-stats: unknown flag '$1' (usage: ss-stats [--since <Nd|Nh|YYYY-MM-DD>] [--limit N])" >&2; exit 1;;
  esac
done
case "$limit" in ''|*[!0-9]*) echo "ss-stats: --limit must be a positive integer" >&2; exit 1;; esac
[ "$limit" -ge 1 ] 2>/dev/null || { echo "ss-stats: --limit must be a positive integer" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ss-stats: jq not found (required)" >&2; exit 2; }

cutoff=""
if [ -n "$since" ]; then
  case "$since" in
    [0-9]*d) n="${since%d}"; cutoff="$(jq -rn --argjson off "$((n*86400))" 'now - $off | todate')";;
    [0-9]*h) n="${since%h}"; cutoff="$(jq -rn --argjson off "$((n*3600))" 'now - $off | todate')";;
    [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) cutoff="${since}T00:00:00Z";;
    *) echo "ss-stats: bad --since '$since' (use Nd, Nh, or YYYY-MM-DD)" >&2; exit 1;;
  esac
fi

SEP="$(printf -- '-%.0s' {1..54})"
emit_empty() { printf 'ss-stats: loop trends\n'; printf '%s\n' "$SEP"; printf 'ss-stats: %s\n' "$1"; }

[ -s "$ledger" ] || { emit_empty "no runs yet"; exit 0; }

data="$(jq -rn --arg cutoff "$cutoff" --argjson limit "$limit" '
  [inputs]
  | map(select($cutoff=="" or .ts >= $cutoff))
  | (group_by(.change) | map({
      change: .[0].change,
      first:  (map(.ts) | min),
      last:   (map(.ts) | max),
      phases: (map(.phase) | unique | length),
      fails:  (map(select(.event=="gate" and .status=="fail")) | length),
      gates:  (map(select(.event=="gate")) | length),
      skips:  (map(select(.event=="skip")) | length)
    }) | sort_by(.first, .change)) as $runs
  | if ($runs|length)==0 then "E"
    else
      ($runs|length) as $n
      | ($runs|map(.fails)|add) as $tf
      | ($runs|map(.gates)|add) as $tg
      | ($runs|map(.skips)|add) as $tk
      | (if $n>=4 then
           ($n/2|floor) as $h
           | ($runs[0:$h]) as $o | ($runs[$h:$n]) as $w
           | ($o|map(.fails)|add) as $fo | ($o|map(.gates)|add) as $go
           | ($w|map(.fails)|add) as $fn | ($w|map(.gates)|add) as $gn
           | (if $go==0 or $gn==0 then "n/a"
              elif ($fn*$go) < ($fo*$gn) then "improving"
              elif ($fn*$go) > ($fo*$gn) then "worsening"
              else "flat" end)
         else "n/a" end) as $trend
      | ( ($runs | reverse | .[0:$limit] | map(
            "R\t" + .change
            + "\t" + (.first[5:10])
            + "\t" + (.phases|tostring)
            + "\t" + (.fails|tostring)
            + "\t" + (.skips|tostring)
            + "\t" + (((.last|fromdateiso8601)-(.first|fromdateiso8601))|tostring) ))
          + ["S\t" + ($n|tostring) + "\t" + ($tf|tostring) + "\t" + ($tg|tostring) + "\t" + ($tk|tostring) + "\t" + $trend]
        ) | .[]
    end
' < "$ledger" 2>/dev/null || true)"

[ -n "$data" ] || { emit_empty "no runs yet"; exit 0; }
if [ "$data" = "E" ]; then
  [ -n "$since" ] && emit_empty "no runs in window" || emit_empty "no runs yet"
  exit 0
fi

window="all"; [ -n "$since" ] && window="since $since"
S_line="$(printf '%s\n' "$data" | grep '^S' | head -1)"
IFS=$'\t' read -r _ runs tfails tgates tskips trend <<< "$S_line"

printf 'ss-stats: loop trends\n'
printf '%s\n' "$SEP"
printf 'runs: %s   window: %s\n' "$runs" "$window"
printf '%s\n' "$SEP"
printf '%-16s%-8s%-8s%-7s%-7s%s\n' 'change' 'date' 'phases' 'fails' 'skips' 'span'
printf '%s\n' "$data" | grep '^R' | while IFS=$'\t' read -r _ change date phases fails skips span_s; do
  printf '%-16s%-8s%-8s%-7s%-7s+%dm\n' "${change:0:15}" "$date" "$phases" "$fails" "$skips" "$((span_s/60))"
done
printf '%s\n' "$SEP"
if [ "$tgates" -gt 0 ]; then
  printf 'gate-fail rate: %d%% (%d/%d)   skips: %d   trend: %s\n' "$((100*tfails/tgates))" "$tfails" "$tgates" "$tskips" "$trend"
else
  printf 'gate-fail rate: n/a (0 gates)   skips: %d   trend: %s\n' "$tskips" "$trend"
fi
exit 0
```

- [ ] **Step 4: Make it executable and run the tests**

Run: `chmod +x scripts/ss-stats && bash tests/stats.test.sh`
Expected: `STATS TESTS PASS`. If `rollup` fails, recompute against the fixture (runs=5, fails=2, gates=11 → `floor(200/11)=18`); if a row fails, check the `%-16s%-8s...` widths and the U+001F field split.

- [ ] **Step 5: Wire the suite into `tests/run.sh`**

In `tests/run.sh`: change the eleven labels `[1/11]`…`[11/11]` to `[1/12]`…`[11/12]`. Then insert after the `[11/12] drift behavior` block (after its closing `fi`, before the final summary `echo`):

```bash
echo "[12/12] stats behavior"
if bash "$ROOT/tests/stats.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - stats suite"; fail=1
fi
```

- [ ] **Step 6: Run the full suite + lint**

Run: `bash tests/run.sh && bash scripts/lint-skills.sh .`
Expected: `[1/12]`…`[12/12]` PASS, `ALL TESTS PASS`; lint clean. (Full suite is slow — pwsh parity; allow a longer timeout. A `[1/12]` JSON-lint failure in a sandbox is a known jq false alarm.)

- [ ] **Step 7: Commit**

```bash
git add scripts/ss-stats tests/stats.test.sh tests/run.sh
git commit -m "feat(stats): add ss-stats cross-run analytics (bash)"
```

---

## Task 2: `scripts/ss-stats.ps1` (PowerShell twin) + parity test

**Model:** sonnet.

**Files:**
- Create: `scripts/ss-stats.ps1`
- Modify: `tests/stats.test.sh` (append a parity block before the summary)

**Interfaces:**
- Consumes: the bash `scripts/ss-stats` output from Task 1 (must match byte-for-byte).
- Produces: `scripts/ss-stats.ps1 [-Since W] [-Limit N]` with byte-identical stdout + exit 0/1/2 (no jq dependency — exit 2 N/A here, but keep 0/1).

- [ ] **Step 1: Append the failing parity test** to `tests/stats.test.sh`, immediately before the final `echo`/summary:

```bash
# parity: read-only, compare a real run on the fixture (full) and with --limit + --since
if command -v pwsh >/dev/null 2>&1; then
  if command -v cygpath >/dev/null 2>&1; then ps1arg="$(cygpath -w "$ROOT/scripts/ss-stats.ps1")"; else ps1arg="$ROOT/scripts/ss-stats.ps1"; fi
  P="$(mkfix)"; export SUPERSTACK_DIR="$P/.superstack"
  for args in "" "--limit 2 --since 2026-06-21"; do
    pb="$(bash "$ROOT/scripts/ss-stats" $args)"
    # translate bash flags to ps1 flags
    ppargs="$(printf '%s' "$args" | sed 's/--limit/-Limit/; s/--since/-Since/')"
    pp="$(pwsh -NoProfile -File "$ps1arg" $ppargs | tr -d '\r')"
    chk "ps1 parity [$args]" '[ "$pb" = "$pp" ]'
  done
else
  echo "  SKIP ps1 parity (pwsh not installed)"
fi
```

- [ ] **Step 2: Run the tests to confirm the parity check fails**

Run: `bash tests/stats.test.sh`
Expected: behavior checks PASS; `ps1 parity` FAIL (ps1 missing) — or SKIP if no `pwsh`.

- [ ] **Step 3: Write `scripts/ss-stats.ps1`**

```powershell
#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Cross-run loop analytics from the ledger (read-only).
# Usage: ss-stats.ps1 [-Since <Nd|Nh|YYYY-MM-DD>] [-Limit N]   Exit: 0 ok, 1 usage.
param([string]$Since='', [string]$Limit='10')
$ErrorActionPreference = 'Stop'

if ($Limit -notmatch '^[0-9]+$' -or [int]$Limit -lt 1) { [Console]::Error.WriteLine("ss-stats: --limit must be a positive integer"); exit 1 }
$lim = [int]$Limit

$cutoff = ''
if ($Since) {
  if ($Since -match '^([0-9]+)d$') { $cutoff = [DateTime]::UtcNow.AddDays(-[int]$Matches[1]).ToString('yyyy-MM-ddTHH:mm:ssZ') }
  elseif ($Since -match '^([0-9]+)h$') { $cutoff = [DateTime]::UtcNow.AddHours(-[int]$Matches[1]).ToString('yyyy-MM-ddTHH:mm:ssZ') }
  elseif ($Since -match '^[0-9]{4}-[0-1][0-9]-[0-3][0-9]$') { $cutoff = "$Since" + 'T00:00:00Z' }
  else { [Console]::Error.WriteLine("ss-stats: bad --since '$Since' (use Nd, Nh, or YYYY-MM-DD)"); exit 1 }
}

$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
if ($dir -match '^/[a-zA-Z]/') { try { $dir = (& cygpath -w $dir 2>$null).Trim() } catch {} }
$ledger = Join-Path $dir 'ledger.jsonl'
$SEP = '-' * 54
function EmitEmpty($m) { Write-Output (@('ss-stats: loop trends', $SEP, "ss-stats: $m") -join "`n") }

if (-not (Test-Path $ledger) -or (Get-Item $ledger).Length -eq 0) { EmitEmpty 'no runs yet'; exit 0 }

# parse + normalize ts (ConvertFrom-Json coerces ISO strings to [datetime])
$entries = @()
foreach ($line in (Get-Content $ledger)) {
  if ($line.Trim() -eq '') { continue }
  $o = $line | ConvertFrom-Json
  $ts = if ($o.ts -is [datetime]) { $o.ts.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { [string]$o.ts }
  $entries += [PSCustomObject]@{ ts=$ts; change=[string]$o.change; phase=[string]$o.phase; event=[string]$o.event; status=[string]$o.status }
}
if ($cutoff) { $entries = @($entries | Where-Object { [string]::CompareOrdinal($_.ts, $cutoff) -ge 0 }) }

# build run records
$runs = @()
foreach ($g in ($entries | Group-Object change)) {
  $es = $g.Group
  $tss = [string[]]@($es | ForEach-Object { $_.ts }); [Array]::Sort($tss, [System.StringComparer]::Ordinal)
  $runs += [PSCustomObject]@{
    change = [string]$g.Name
    first  = $tss[0]
    last   = $tss[-1]
    phases = @($es.phase | Select-Object -Unique).Count
    fails  = @($es | Where-Object { $_.event -eq 'gate' -and $_.status -eq 'fail' }).Count
    gates  = @($es | Where-Object { $_.event -eq 'gate' }).Count
    skips  = @($es | Where-Object { $_.event -eq 'skip' }).Count
  }
}
if ($runs.Count -eq 0) {
  if ($cutoff) { EmitEmpty 'no runs in window' } else { EmitEmpty 'no runs yet' }
  exit 0
}
# order by first ts (ordinal), tiebreak change
$runs = @($runs | Sort-Object @{Expression='first'}, @{Expression='change'})

$n = $runs.Count
$tf = ($runs | Measure-Object fails -Sum).Sum; if (-not $tf) { $tf = 0 }
$tg = ($runs | Measure-Object gates -Sum).Sum; if (-not $tg) { $tg = 0 }
$tk = ($runs | Measure-Object skips -Sum).Sum; if (-not $tk) { $tk = 0 }

$trend = 'n/a'
if ($n -ge 4) {
  $h = [math]::Floor($n/2)
  $o = $runs[0..($h-1)]; $w = $runs[$h..($n-1)]
  $fo = ($o | Measure-Object fails -Sum).Sum; if (-not $fo) { $fo = 0 }
  $go = ($o | Measure-Object gates -Sum).Sum; if (-not $go) { $go = 0 }
  $fn = ($w | Measure-Object fails -Sum).Sum; if (-not $fn) { $fn = 0 }
  $gn = ($w | Measure-Object gates -Sum).Sum; if (-not $gn) { $gn = 0 }
  if ($go -eq 0 -or $gn -eq 0) { $trend = 'n/a' }
  elseif (($fn*$go) -lt ($fo*$gn)) { $trend = 'improving' }
  elseif (($fn*$go) -gt ($fo*$gn)) { $trend = 'worsening' }
  else { $trend = 'flat' }
}

function ToEpoch($s) {
  $dt = [datetime]::ParseExact($s, 'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal)
  [int][math]::Floor(($dt - [datetime]'1970-01-01T00:00:00Z').TotalSeconds)
}

$window = if ($Since) { "since $Since" } else { 'all' }
$lines = @('ss-stats: loop trends', $SEP, "runs: $n   window: $window", $SEP)
$lines += ('{0,-16}{1,-8}{2,-8}{3,-7}{4,-7}{5}' -f 'change','date','phases','fails','skips','span')
$recent = @($runs); [Array]::Reverse($recent)
$recent = @($recent | Select-Object -First $lim)
foreach ($r in $recent) {
  $chg = if ($r.change.Length -gt 15) { $r.change.Substring(0,15) } else { $r.change }
  $mins = [math]::Floor((ToEpoch $r.last - ToEpoch $r.first) / 60)
  $lines += ('{0,-16}{1,-8}{2,-8}{3,-7}{4,-7}+{5}m' -f $chg, $r.first.Substring(5,5), $r.phases, $r.fails, $r.skips, $mins)
}
$lines += $SEP
if ($tg -gt 0) {
  $rate = [math]::Floor(100*$tf/$tg)
  $lines += "gate-fail rate: $rate% ($tf/$tg)   skips: $tk   trend: $trend"
} else {
  $lines += "gate-fail rate: n/a (0 gates)   skips: $tk   trend: $trend"
}
Write-Output ($lines -join "`n")
exit 0
```

Parity notes for the implementer:
- **ts re-normalization is mandatory** — `ConvertFrom-Json` turns the ISO `ts` into `[datetime]`; convert back to the canonical `yyyy-MM-ddTHH:mm:ssZ` string before any compare/slice (matches `ss-evolve.ps1`). Without it `Substring(5,5)`/`CompareOrdinal` break.
- **All integer math** mirrors jq: `[math]::Floor(100*$tf/$tg)` ≡ jq `floor`; the trend cross-multiplication is identical; the span is `floor(seconds/60)`.
- **Ordinal everywhere** — `[StringComparer]::Ordinal` for the `--since` compare and the ts min/max, so it matches bash `LC_ALL=C` + jq codepoint order. Run ordering: `Sort-Object first, change` (timestamps are distinct → matches jq `sort_by(.first,.change)`).
- **Format strings** `'{0,-16}{1,-8}{2,-8}{3,-7}{4,-7}{5}'` mirror bash `'%-16s%-8s%-8s%-7s%-7s%s'`; the rollup line and `runs:`/window line strings match byte-for-byte. `change` truncated to 15.
- `Measure-Object -Sum` returns `$null` for an empty set — the `if (-not $x){$x=0}` guards keep it 0.

- [ ] **Step 4: Run the tests to verify parity passes**

Run: `bash tests/stats.test.sh`
Expected: all PASS including both `ps1 parity` cases (or SKIP if no `pwsh`) → `STATS TESTS PASS`. If parity fails, diff `bash scripts/ss-stats` vs `pwsh -NoProfile -File scripts/ss-stats.ps1 | tr -d '\r'` on the same `SUPERSTACK_DIR` fixture; likely causes are ts coercion (date/span wrong), a rounding difference (must be floor), or column widths.

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh`
Expected: `[1/12]`…`[12/12]` PASS, `ALL TESTS PASS`.

- [ ] **Step 6: Commit**

```bash
git add scripts/ss-stats.ps1 tests/stats.test.sh
git commit -m "feat(stats): PowerShell parity for ss-stats"
```

---

## Task 3: `skills/stats/SKILL.md`

**Model:** haiku (pure markdown).

**Files:**
- Create: `skills/stats/SKILL.md`

**Interfaces:** documents Task 1–2 behavior; nothing depends on it.

- [ ] **Step 1: Write the skill**

```markdown
---
name: ss-stats
description: Use periodically (or before a retro) to see how the loop is trending across runs - a read-only dashboard of the per-run table (phases, gate-fails, skips, span) plus a rollup (gate-fail rate, skips, and an improving/worsening/flat trend). Distinct from /ss-report (one run) and /ss-evolve (acts on patterns).
---

# Stats - is the loop getting better?

Read-only cross-run analytics. It groups the ledger into runs (one per `change`/branch) and shows the
recent ones as a table plus a trend rollup. The point is **direction** - is your process improving? -
not absolute scores (after the DORA guidance that trend beats any single number).

## Steps

1. Run `scripts/ss-stats` (PowerShell: `scripts/ss-stats.ps1`). Optional:
   - `--since <Nd|Nh|YYYY-MM-DD>` - restrict to a recent window.
   - `--limit N` - cap the table to the N most recent runs (default 10; the rollup still spans the window).
2. Read the table (most recent run first): `change` / `date` / `phases` / `fails` (gate-fails) /
   `skips` / `span`.
3. Read the rollup: `gate-fail rate` (cadence shown beside quality, never alone), total `skips`, and
   `trend` - `improving` / `worsening` / `flat` (older half vs newer half; `n/a` under 4 runs).

## Note

`/ss-stats` is read-only and never a gate - a "bad" trend is a signal to reflect, not a failure. It
does NOT flag per-phase recurring patterns or propose fixes; that is [[ss-evolve]]. Feed its output
into a periodic [[ss-retro]].

## Lineage

Original to SuperStack - the cross-run companion to [[ss-report]] (one run), applying DORA-style
trend thinking (gate-fail rate as the change-failure-rate analog) to the loop ledger.
```

- [ ] **Step 2: Verify it lints**

Run: `bash scripts/lint-skills.sh .`
Expected: PASS — reports 27 skills; `[[ss-evolve]]`, `[[ss-retro]]`, `[[ss-report]]` all resolve (those skills exist). Name `ss-stats`, description 40–500 chars, exactly one H1.

- [ ] **Step 3: Commit**

```bash
git add skills/stats/SKILL.md
git commit -m "docs(stats): add /ss-stats skill"
```

---

## Task 4: README + CHANGELOG

**Model:** haiku (pure markdown).

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update the CHANGELOG**

Read `CHANGELOG.md`. Under the top `## [Unreleased]` heading, add a `### Added` group (create it if absent — `[Unreleased]` is currently empty after the v0.6.0 cut) with:

```markdown
### Added
- **`/ss-stats`:** read-only cross-run loop analytics — a per-run table (phases, gate-fails, skips,
  span) plus a rollup (gate-fail rate, skips, and an improving/worsening/flat trend over the window).
  `--since`/`--limit`; the cross-run companion to `/ss-report`, distinct from `/ss-evolve`. bash +
  PowerShell. (27 skills.)
```

Do NOT rename `[Unreleased]`. Don't disturb the dated version sections below it.

- [ ] **Step 2: Surface it in the README**

Read `README.md`. Two surgical edits:
1. Add `/ss-stats` to the **Supporting skills** inline list (the line with `/ss-init` … `/ss-drift` … `run /ss-help`), right after `/ss-drift`. (Inline list only — NOT a standalone table.)
2. Bump the skills count: first GREP for the current count (badge `skills-26` and `**26 skills, ...**` prose); change **26 → 27** in both. If you find a different number, bump that actual number by one and note it in your report.

Match surrounding style; don't restructure.

- [ ] **Step 3: Verify nothing regressed**

Run: `bash scripts/lint-skills.sh .`
Expected: clean, 27 skills. (Authoritative quick check; `tests/run.sh` is slow.)

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: surface /ss-stats in README + CHANGELOG"
```

---

## Self-Review (completed by plan author)

- **Spec coverage:** CLI + `--since`/`--limit` + exit 0/1/2 (T1) · run grouping/ordering (T1 jq + T2 Sort) · per-run metrics incl. span/date (T1+T2) · rollup rate/skips/trend incl. floor + cross-multiplication (T1+T2) · empty + windowed-empty messages (T1+T2) · output format/widths/separators (T1, spec §6) · byte-identical twins incl. ts re-normalization + Ordinal + integer math (T2) · read-only parity on full + limit/since (T2) · tests→`run.sh [12/12]` (T1–T2) · skill (T3) · README 27 + CHANGELOG (T4). All spec sections map to a task.
- **Placeholder scan:** none — every code/test/doc block is complete; the fixture arithmetic is verified (runs=5, fails=2, gates=11→18%, skips=1, trend improving via fn·go=5 < fo·gn=6).
- **Type/name consistency:** the jq fields (`change/first/last/phases/fails/gates/skips`) ≡ the ps1 PSCustomObject properties; the trend tokens `improving/worsening/flat/n/a`, the `%-16s%-8s%-8s%-7s%-7s` ≡ `{0,-16}{1,-8}{2,-8}{3,-7}{4,-7}` widths, the U+001F row protocol, the floor-rate, and the `no runs yet`/`no runs in window` strings are identical across bash, PowerShell, and the tests.

---

## Execution Handoff

Recommended: **subagent-driven** — Task 1 (bash/jq) and Task 2 (PowerShell parity) on sonnet (the jq↔ConvertFrom-Json aggregation is the session's most intricate parity), Tasks 3–4 (markdown) on haiku; per-task spec+quality review, opus whole-branch review at the end.
