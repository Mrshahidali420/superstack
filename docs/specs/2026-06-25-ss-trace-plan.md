# /ss-trace (change provenance / lineage) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/ss-trace` — a read-only change-provenance command (bash `scripts/ss-trace` + PowerShell twin, skill, tests, docs) that, for one change, shows its spec/plan docs, its ledger gate/skip events **interleaved chronologically with the branch's git commits**, and an origin footer.

**Architecture:** Tag each lineage row with its source (`G` = ledger gate/skip, `C` = git commit), normalize both to UTC-ISO timestamps, concatenate, and sort the whole rows ordinally so they interleave by time (no epoch/locale math). Spec docs are slug-globbed from `docs/specs/`; the footer pulls files-changed + head SHA from git. Everything degrades gracefully (no docs, no ledger, or a merged/deleted branch).

**Tech Stack:** Bash + `jq` + `git`; PowerShell 7 (`ConvertFrom-Json` + `git`); the `chk`/`newrepo` harness with fixed-date commits + a seeded ledger.

## Global Constraints

(Verbatim from the spec; every task implicitly includes these.)

- **Byte-identical ASCII stdout** across `scripts/ss-trace` (bash) and `scripts/ss-trace.ps1` (PowerShell). No Unicode (the graceful note uses an ASCII `;`, never an em-dash).
- CLI `ss-trace [<change>] [base]` (PowerShell `-Change`/`-Base`). `<change>` default = current branch (`git branch --show-current`), else `default`. `base` default = `main`, fallback `master`. More than 2 args → stderr usage, **exit 1**. `jq` missing → stderr, **exit 2** (bash only). Read-only; **exit 0 always on success**, including the graceful "no trace" / "branch not found" cases.
- A run/change = ledger entries sharing one `change`. `ts` = `YYYY-MM-DDTHH:MM:SSZ` (UTC, lexicographically sortable).
- **Lineage rows** (sorted by the whole tagged row, ordinal): ledger gate/skip → `<ts>\tG\t<phase>\t<STATUS>\t<note>` (`STATUS` = upper-cased status → `PASS`/`FAIL`/`SKIP`); git commit → `<ts>\tC\t<sha7>\t<subject>`. The `G`/`C` tag is the tie-break when a gate and commit share a timestamp (`C` sorts before `G`).
- **Commit UTC-ISO:** `TZ=UTC git log <base>..<change> --date=format-local:'%Y-%m-%dT%H:%M:%SZ' --format='%cd%x09C%x09%h%x09%s'` (bash; ps1 sets `$env:TZ='UTC'` then the same `git log`).
- **Display row** (time = `ts[5:10] + " " + ts[11:16]` = `MM-DD HH:MM`): gate = `  %s  %-8s %-5s %s` (time, phase, STATUS, note) **right-trimmed**; commit = `  %s  %-8s %s  %s` (time, `*`, sha7, subject), not trimmed.
- **Output blocks:** `ss-trace: provenance for <change>` · 54-dash sep · `intent:` + one `  <path>` per slug-matched `docs/specs/*<slug>*.md` (or `  (no spec/plan docs found)`) · sep · `lineage (gates + commits, chronological):` + rows (+ `  (branch '<change>' not found; git commits omitted)` when the change is not a git ref) · sep · `origin: <change>   gates: <Ng>   commits: <Nc>   files: <Nf>   head: <sha7|n/a>` (3 spaces between fields). No-trace (neither rows): header, sep, `ss-trace: no trace for <change>`.
- `slug` = `<change>` after the last `/` (`feat/ss-trace` → `ss-trace`). `Nf` = `git diff --name-only <base>..<change>` line count; `head` = `git rev-parse --short <change>` (or `n/a`).
- ps1: `$PSNativeCommandUseErrorActionPreference=$false` set early (it calls native git); `ts` re-normalized (ConvertFrom-Json coerces ISO → `[datetime]`); sort rows with `[System.StringComparer]::Ordinal`; reject extra args via `[Parameter(ValueFromRemainingArguments=$true)]$Rest` → exit 1.
- `${SUPERSTACK_DIR:-.superstack}/ledger.jsonl`; run from the repo root (the `docs/specs/` glob + git are cwd-relative). Conventional commits, no AI attribution. Ships in the pending v0.7.0 cut; skills → 28.

Reference siblings: `scripts/ss-report` (git `merge-base`/diff, ps1 git handling), `scripts/ss-stats` + `.ps1` (ledger jq↔ConvertFrom-Json parity, ts re-normalization, Ordinal sort, `$Rest` arg rejection), `scripts/ss-replay` (time formatting). Spec: `docs/specs/2026-06-25-ss-trace-design.md`.

---

## File Structure

- `scripts/ss-trace` — bash (Task 1)
- `scripts/ss-trace.ps1` — PowerShell twin (Task 2)
- `tests/trace.test.sh` — behavior tests (Task 1) + parity test (Task 2)
- `tests/run.sh` — wire `[13/13]`, bump `[N/12]`→`[N/13]` (Task 1)
- `skills/trace/SKILL.md` — the skill (Task 3)
- `README.md`, `CHANGELOG.md` — surface it (Task 4)

---

## Task 1: `scripts/ss-trace` (bash) + tests + run.sh wiring

**Model:** sonnet.

**Files:**
- Create: `scripts/ss-trace`
- Create: `tests/trace.test.sh`
- Modify: `tests/run.sh`

**Interfaces:**
- Produces: `scripts/ss-trace [<change>] [base]` printing the provenance view + exit 0/1/2.
- Consumes: `jq`, `git`, the ledger at `${SUPERSTACK_DIR:-.superstack}/ledger.jsonl`, `docs/specs/`.

This script is **already verified end-to-end by the plan author** against a fixture (full trace, branch-not-found, no-trace). Transcribe it verbatim.

- [ ] **Step 1: Write the failing tests** — create `tests/trace.test.sh`

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavior + parity tests for scripts/ss-trace.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }

# Build a fixture repo: main + feat/demo with fixed-date commits + a seeded ledger + spec docs.
mkfix() {
  local d; d="$(mktemp -d)"
  ( cd "$d" && git init -q && git config user.email a@b.c && git config user.name t && git config core.autocrlf false
    mkdir -p docs/specs .superstack
    printf '# demo\n' > docs/specs/2026-06-25-demo-design.md
    printf '# demo\n' > docs/specs/2026-06-25-demo-plan.md
    printf 'x\n' > f0; git add -A
    GIT_AUTHOR_DATE='2026-06-25T09:00:00Z' GIT_COMMITTER_DATE='2026-06-25T09:00:00Z' git commit -qm 'chore: init'
    git checkout -q -b feat/demo
    printf 'a\n' > f1; git add -A
    GIT_AUTHOR_DATE='2026-06-25T11:00:00Z' GIT_COMMITTER_DATE='2026-06-25T11:00:00Z' git commit -qm 'feat: add f1'
    printf 'b\n' > f2; git add -A
    GIT_AUTHOR_DATE='2026-06-25T12:00:00Z' GIT_COMMITTER_DATE='2026-06-25T12:00:00Z' git commit -qm 'feat: add f2'
    L=.superstack/ledger.jsonl
    printf '{"ts":"2026-06-25T10:30:00Z","change":"feat/demo","phase":"plan","event":"gate","status":"pass","note":""}\n' >> "$L"
    printf '{"ts":"2026-06-25T11:40:00Z","change":"feat/demo","phase":"review","event":"gate","status":"pass","note":"no critical/high"}\n' >> "$L"
    printf '{"ts":"2026-06-25T11:50:00Z","change":"feat/demo","phase":"secure","event":"skip","status":"skip","note":"no IO"}\n' >> "$L"
    printf '{"ts":"2026-06-25T12:30:00Z","change":"feat/demo","phase":"ship","event":"gate","status":"pass","note":""}\n' >> "$L"
    printf '{"ts":"2026-06-24T08:00:00Z","change":"gone","phase":"frame","event":"gate","status":"pass","note":""}\n' >> "$L" )
  printf '%s' "$d"
}
run() { ( cd "$1" && SUPERSTACK_DIR="$1/.superstack" bash "$ROOT/scripts/ss-trace" "${@:2}" ); }

D="$(mkfix)"
out="$(run "$D" feat/demo)"; rc=$?
chk "header"        'printf "%s" "$out" | grep -qF "ss-trace: provenance for feat/demo"'
chk "intent design" 'printf "%s" "$out" | grep -qF "  docs/specs/2026-06-25-demo-design.md"'
chk "intent plan"   'printf "%s" "$out" | grep -qF "  docs/specs/2026-06-25-demo-plan.md"'
chk "gate plan"     'printf "%s" "$out" | grep -qE "^  06-25 10:30  plan +PASS"'
chk "skip rendered" 'printf "%s" "$out" | grep -qE "^  06-25 11:50  secure +SKIP +no IO"'
chk "commit f1 mark" 'printf "%s" "$out" | grep -qE "^  06-25 11:00  \* +[0-9a-f]+  feat: add f1"'
# interleave order: plan < f1 < review < secure < f2 < ship
chk "order"  'printf "%s" "$out" | awk "/ plan /{a=NR} / add f1\$/{b=NR} / review /{c=NR} / add f2\$/{d=NR} / ship /{e=NR} END{exit !(a<b && b<c && c<d && d<e)}"'
chk "footer" 'printf "%s" "$out" | grep -qE "^origin: feat/demo   gates: 4   commits: 2   files: 2   head: [0-9a-f]+$"'
chk "exit 0" '[ "$rc" -eq 0 ]'

# no matching docs -> placeholder (trace the 'gone' ledger-only change; slug 'gone' has no docs)
outg="$(run "$D" gone)"
chk "no docs"          'printf "%s" "$outg" | grep -qF "  (no spec/plan docs found)"'
chk "branch not found" 'printf "%s" "$outg" | grep -qF "  (branch '\''gone'\'' not found; git commits omitted)"'
chk "gone ledger row"  'printf "%s" "$outg" | grep -qE "^  06-24 08:00  frame +PASS"'
chk "gone footer"      'printf "%s" "$outg" | grep -qF "origin: gone   gates: 1   commits: 0   files: 0   head: n/a"'

# no trace + usage
outn="$(run "$D" nothing)"
chk "no trace" 'printf "%s" "$outn" | grep -qF "ss-trace: no trace for nothing"'
( run "$D" a b c ) >/dev/null 2>&1; chk "too many args exit 1" '[ "$?" -eq 1 ]'

echo
[ "$fail" -eq 0 ] && echo "TRACE TESTS PASS" || echo "TRACE TESTS FAILED"
exit "$fail"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/trace.test.sh`
Expected: FAIL — `scripts/ss-trace` does not exist yet.

- [ ] **Step 3: Write `scripts/ss-trace`** (verbatim — author-verified)

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Change provenance: spec docs + ledger gates interleaved with git commits (read-only).
# Usage: ss-trace [<change>] [base]   Exit: 0 ok, 1 usage, 2 missing jq.
set -uo pipefail
export LC_ALL=C
dir="${SUPERSTACK_DIR:-.superstack}"
ledger="$dir/ledger.jsonl"

[ "$#" -le 2 ] || { echo "ss-trace: too many args (usage: ss-trace [<change>] [base])" >&2; exit 1; }
change="${1:-}"; base="${2:-}"
[ -n "$change" ] || change="$(git branch --show-current 2>/dev/null || true)"
[ -n "$change" ] || change="default"
if [ -z "$base" ]; then
  if git rev-parse --verify -q main >/dev/null 2>&1; then base="main"
  elif git rev-parse --verify -q master >/dev/null 2>&1; then base="master"
  else base="main"; fi
fi
command -v jq >/dev/null 2>&1 || { echo "ss-trace: jq not found (required)" >&2; exit 2; }

SEP="$(printf -- '-%.0s' {1..54})"
slug="${change##*/}"
have_ref=0; git rev-parse --verify -q "$change" >/dev/null 2>&1 && have_ref=1

tmp="$(mktemp)"; tmps="$(mktemp)"; trap 'rm -f "$tmp" "$tmps"' EXIT
# ledger gate/skip rows: <ts> G <phase> <STATUS> <note>
if [ -s "$ledger" ]; then
  jq -rn --arg c "$change" '
    [inputs] | map(select(.change==$c and (.event=="gate" or .event=="skip")))
    | .[] | [.ts, "G", .phase, (.status|ascii_upcase), (.note // "")] | @tsv
  ' < "$ledger" 2>/dev/null >> "$tmp" || true
fi
# git commit rows: <ts> C <sha7> <subject>
if [ "$have_ref" = "1" ]; then
  TZ=UTC git log "$base..$change" --date=format-local:'%Y-%m-%dT%H:%M:%SZ' \
    --format='%cd%x09C%x09%h%x09%s' 2>/dev/null >> "$tmp" || true
fi
sort "$tmp" > "$tmps" 2>/dev/null || true

if [ ! -s "$tmps" ]; then
  printf 'ss-trace: provenance for %s\n%s\nss-trace: no trace for %s\n' "$change" "$SEP" "$change"
  exit 0
fi

printf 'ss-trace: provenance for %s\n%s\nintent:\n' "$change" "$SEP"
found=0
for f in docs/specs/*"$slug"*.md; do
  [ -e "$f" ] || continue; printf '  %s\n' "$f"; found=1
done
[ "$found" = "1" ] || printf '  (no spec/plan docs found)\n'
printf '%s\nlineage (gates + commits, chronological):\n' "$SEP"
gates=0; commits=0
while IFS=$'\t' read -r ts typ f3 f4 f5; do
  t="${ts:5:5} ${ts:11:5}"
  if [ "$typ" = "G" ]; then
    line="$(printf '  %s  %-8s %-5s %s' "$t" "$f3" "$f4" "$f5")"
    printf '%s\n' "${line%"${line##*[![:space:]]}"}"
    gates=$((gates+1))
  else
    printf '  %s  %-8s %s  %s\n' "$t" "*" "$f3" "$f4"
    commits=$((commits+1))
  fi
done < "$tmps"
[ "$have_ref" = "1" ] || printf "  (branch '%s' not found; git commits omitted)\n" "$change"
printf '%s\n' "$SEP"
files=0; head="n/a"
if [ "$have_ref" = "1" ]; then
  files="$(TZ=UTC git diff --name-only "$base..$change" 2>/dev/null | wc -l | tr -d ' ')"
  head="$(git rev-parse --short "$change" 2>/dev/null || echo n/a)"
fi
printf 'origin: %s   gates: %d   commits: %d   files: %s   head: %s\n' "$change" "$gates" "$commits" "$files" "$head"
```

- [ ] **Step 4: Make it executable and run the tests**

Run: `chmod +x scripts/ss-trace && bash tests/trace.test.sh`
Expected: `TRACE TESTS PASS`. (The `${line%...}` idiom right-trims trailing spaces on gate rows; the `*` marks commits; the sort interleaves by UTC-ISO ts with the `C`-before-`G` tie-break.)

- [ ] **Step 5: Wire the suite into `tests/run.sh`**

In `tests/run.sh`: change the twelve labels `[1/12]`…`[12/12]` to `[1/13]`…`[12/13]`. Then insert after the `[12/13] stats behavior` block (after its closing `fi`, before the final summary `echo`):

```bash
echo "[13/13] trace behavior"
if bash "$ROOT/tests/trace.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - trace suite"; fail=1
fi
```

- [ ] **Step 6: Run the full suite + lint**

Run: `bash tests/run.sh && bash scripts/lint-skills.sh .`
Expected: `[1/13]`…`[13/13]` PASS, `ALL TESTS PASS`; lint clean. (Full suite is slow — allow ~420000ms. A `[1/13]` JSON-lint false alarm in a restricted sandbox is known; the `trace.test.sh` suite passing is the real signal.)

- [ ] **Step 7: Commit**

```bash
git add scripts/ss-trace tests/trace.test.sh tests/run.sh
git commit -m "feat(trace): add ss-trace change provenance (bash)"
```

---

## Task 2: `scripts/ss-trace.ps1` (PowerShell twin) + parity test

**Model:** sonnet.

**Files:**
- Create: `scripts/ss-trace.ps1`
- Modify: `tests/trace.test.sh` (append a parity block before the summary)

**Interfaces:**
- Consumes: the bash `scripts/ss-trace` output (must match byte-for-byte).
- Produces: `scripts/ss-trace.ps1 [-Change <c>] [-Base <b>]` with byte-identical stdout + exit 0/1.

- [ ] **Step 1: Append the failing parity test** to `tests/trace.test.sh`, immediately before the final `echo`/summary:

```bash
# parity: read-only, compare bash vs ps1 on the full trace + the branch-not-found case
if command -v pwsh >/dev/null 2>&1; then
  if command -v cygpath >/dev/null 2>&1; then ps1arg="$(cygpath -w "$ROOT/scripts/ss-trace.ps1")"; else ps1arg="$ROOT/scripts/ss-trace.ps1"; fi
  P="$(mkfix)"
  for c in feat/demo gone; do
    pb="$(cd "$P" && SUPERSTACK_DIR="$P/.superstack" bash "$ROOT/scripts/ss-trace" "$c")"
    pp="$(cd "$P" && SUPERSTACK_DIR="$P/.superstack" pwsh -NoProfile -File "$ps1arg" -Change "$c" | tr -d '\r')"
    chk "ps1 parity [$c]" '[ "$pb" = "$pp" ]'
  done
else
  echo "  SKIP ps1 parity (pwsh not installed)"
fi
```

- [ ] **Step 2: Run the tests to confirm the parity check fails**

Run: `bash tests/trace.test.sh`
Expected: behavior checks PASS; `ps1 parity` FAIL (ps1 missing) — or SKIP if no `pwsh`.

- [ ] **Step 3: Write `scripts/ss-trace.ps1`**

```powershell
#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Change provenance: spec docs + ledger gates interleaved with git commits (read-only).
# Usage: ss-trace.ps1 [-Change <c>] [-Base <b>]   Exit: 0 ok, 1 usage.
param([string]$Change='', [string]$Base='', [Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if ($Rest -and $Rest.Count -gt 0) { [Console]::Error.WriteLine("ss-trace: too many args (usage: ss-trace [<change>] [base])"); exit 1 }

$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
if ($dir -match '^/[a-zA-Z]/') { try { $dir = (& cygpath -w $dir 2>$null).Trim() } catch {} }
$ledger = Join-Path $dir 'ledger.jsonl'

$change = $Change
if (-not $change) { $change = "$(git branch --show-current 2>$null)".Trim() }
if (-not $change) { $change = 'default' }
$base = $Base
if (-not $base) {
  if (git rev-parse --verify -q main 2>$null) { $base = 'main' }
  elseif (git rev-parse --verify -q master 2>$null) { $base = 'master' }
  else { $base = 'main' }
}

$SEP = '-' * 54
$slug = ($change -split '/')[-1]
$haveRef = [bool](git rev-parse --verify -q $change 2>$null)

$rows = New-Object System.Collections.Generic.List[string]
if ((Test-Path $ledger) -and (Get-Item $ledger).Length -gt 0) {
  foreach ($line in (Get-Content $ledger)) {
    if ($line.Trim() -eq '') { continue }
    $o = $line | ConvertFrom-Json
    if ([string]$o.change -ne $change) { continue }
    $ev = [string]$o.event
    if ($ev -ne 'gate' -and $ev -ne 'skip') { continue }
    $ts = if ($o.ts -is [datetime]) { $o.ts.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { [string]$o.ts }
    $rows.Add($ts + "`t" + 'G' + "`t" + [string]$o.phase + "`t" + ([string]$o.status).ToUpper() + "`t" + [string]$o.note)
  }
}
if ($haveRef) {
  $env:TZ = 'UTC'
  $log = git log "$base..$change" --date=format-local:'%Y-%m-%dT%H:%M:%SZ' --format='%cd%x09C%x09%h%x09%s' 2>$null
  foreach ($l in @($log)) { if ($l) { $rows.Add([string]$l) } }
}
$arr = $rows.ToArray()
[Array]::Sort($arr, [System.StringComparer]::Ordinal)

$out = New-Object System.Collections.Generic.List[string]
if ($arr.Count -eq 0) {
  Write-Output ("ss-trace: provenance for $change`n$SEP`nss-trace: no trace for $change")
  exit 0
}

$out.Add("ss-trace: provenance for $change")
$out.Add($SEP)
$out.Add('intent:')
$specs = @(Get-ChildItem -Path 'docs/specs' -Filter "*$slug*.md" -File -ErrorAction SilentlyContinue | ForEach-Object { 'docs/specs/' + $_.Name })
[Array]::Sort($specs, [System.StringComparer]::Ordinal)
if ($specs.Count -gt 0) { foreach ($s in $specs) { $out.Add('  ' + $s) } } else { $out.Add('  (no spec/plan docs found)') }
$out.Add($SEP)
$out.Add('lineage (gates + commits, chronological):')
$gates = 0; $commits = 0
foreach ($r in $arr) {
  $p = $r -split "`t"
  $t = $p[0].Substring(5,5) + ' ' + $p[0].Substring(11,5)
  if ($p[1] -eq 'G') {
    $out.Add( ('  {0}  {1,-8} {2,-5} {3}' -f $t, $p[2], $p[3], $p[4]).TrimEnd() )
    $gates++
  } else {
    $out.Add( '  {0}  {1,-8} {2}  {3}' -f $t, '*', $p[2], $p[3] )
    $commits++
  }
}
if (-not $haveRef) { $out.Add("  (branch '$change' not found; git commits omitted)") }
$out.Add($SEP)
$files = 0; $head = 'n/a'
if ($haveRef) {
  $files = @(git diff --name-only "$base..$change" 2>$null | Where-Object { $_ -ne '' }).Count
  $h = "$(git rev-parse --short $change 2>$null)".Trim()
  if ($h) { $head = $h }
}
$out.Add("origin: $change   gates: $gates   commits: $commits   files: $files   head: $head")
Write-Output ($out -join "`n")
exit 0
```

Parity notes for the implementer:
- **Sort the full tagged rows with `[System.StringComparer]::Ordinal`** (single-array overload — no parallel-array trap) to match bash `sort` under `LC_ALL=C`. The `ts` leads each row so this orders by time; the `G`/`C` tag breaks ties (`C` < `G`).
- **`ts` re-normalization** — `ConvertFrom-Json` coerces the ISO `ts` to `[datetime]`; convert back to `yyyy-MM-ddTHH:mm:ssZ` before building the row (matches `ss-stats.ps1`). The `git log` lines are raw text (already UTC-ISO), no coercion.
- **`$env:TZ='UTC'` before `git log`** so `--date=format-local` emits UTC, matching the bash `TZ=UTC` prefix.
- **Right-trim only the gate row** (`.TrimEnd()`), matching the bash `${line%...}`; the commit row is not trimmed.
- **`$PSNativeCommandUseErrorActionPreference=$false`** so git's non-zero exit on a missing ref returns empty instead of throwing.
- Format strings `'  {0}  {1,-8} {2,-5} {3}'` / `'  {0}  {1,-8} {2}  {3}'` mirror the bash `printf` widths exactly.

- [ ] **Step 4: Run the tests to verify parity passes**

Run: `bash tests/trace.test.sh`
Expected: all PASS including both `ps1 parity [feat/demo]` and `ps1 parity [gone]` (or SKIP if no `pwsh`) → `TRACE TESTS PASS`. If parity fails, diff `bash scripts/ss-trace feat/demo` vs `pwsh -NoProfile -File scripts/ss-trace.ps1 -Change feat/demo | tr -d '\r'` from the fixture root; likely culprits are ts coercion, the sort comparer (must be Ordinal), the `$env:TZ`/`git log` date, the intent path format (`docs/specs/<name>`), or a width/trim mismatch.

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh`
Expected: `[1/13]`…`[13/13]` PASS, `ALL TESTS PASS`.

- [ ] **Step 6: Commit**

```bash
git add scripts/ss-trace.ps1 tests/trace.test.sh
git commit -m "feat(trace): PowerShell parity for ss-trace"
```

---

## Task 3: `skills/trace/SKILL.md`

**Model:** haiku (pure markdown).

**Files:**
- Create: `skills/trace/SKILL.md`

**Interfaces:** documents Task 1–2 behavior; nothing depends on it.

- [ ] **Step 1: Write the skill**

```markdown
---
name: ss-trace
description: Use to see one change's provenance - a read-only 'birth certificate' that joins its spec/plan docs (intent), its ledger gate/skip events, and its actual git commits into one chronological lineage, plus an origin footer (gates, commits, files, head SHA). Distinct from /ss-replay (ledger-only timeline) and /ss-report (run stats).
---

# Trace - where did this change come from?

Read-only change provenance. For one change (branch), `/ss-trace` joins the three things the loop
already records - the spec/plan docs (intent), the ledger gate/skip events (the review trail), and the
git commits (the output) - into a single chronological lineage. It surfaces the trail the loop left;
it builds no new data and passes no judgement (after SLSA's "build provenance" idea: a birth
certificate answering *where did this come from*).

## Steps

1. Run `scripts/ss-trace` (PowerShell: `scripts/ss-trace.ps1`). Optional args:
   - `<change>` (`-Change`) - the branch / ledger change to trace. Default: the current branch.
   - `base` (`-Base`) - the commit-range base (default `main`, falling back to `master`).
2. Read the `intent:` block - the `docs/specs/` design/plan docs matched to the change.
3. Read the `lineage` - ledger gate/skip events (`PHASE STATUS note`) interleaved by time with the git
   commits (marked `*`, `sha subject`).
4. Read the `origin:` footer - gates, commits, files changed, and the head SHA.

## Note

`/ss-trace` is read-only and never a gate. It degrades gracefully: a merged/deleted branch shows
ledger-only lineage with a note; an unknown change prints `no trace`. It does NOT verify the loop ran
(that is [[ss-audit]]) or diff the plan's files (that is [[ss-drift]]).

## Lineage

Original to SuperStack - the provenance view that joins intent ([[ss-frame]] specs), the gate trail
([[ss-audit]]), and commits. Complements [[ss-replay]] (ledger-only timeline) and [[ss-report]]
(run stats) by being the one command that links the ledger to git and the specs.
```

- [ ] **Step 2: Verify it lints**

Run: `bash scripts/lint-skills.sh .`
Expected: PASS — reports 28 skills; `[[ss-audit]]`, `[[ss-drift]]`, `[[ss-frame]]`, `[[ss-replay]]`, `[[ss-report]]` all resolve (those skills exist). Name `ss-trace`, description 40–500 chars, exactly one H1.

- [ ] **Step 3: Commit**

```bash
git add skills/trace/SKILL.md
git commit -m "docs(trace): add /ss-trace skill"
```

---

## Task 4: README + CHANGELOG

**Model:** haiku (pure markdown).

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update the CHANGELOG**

Read `CHANGELOG.md`. Under the top `## [Unreleased]` heading there is already an `### Added` group (with the `/ss-stats` entry). Add this bullet to that SAME group (do not create a second `### Added`):

```markdown
- **`/ss-trace`:** read-only change provenance — joins a change's spec/plan docs, its ledger gate/skip
  events, and its git commits into one chronological lineage with an origin footer (gates, commits,
  files, head SHA). `[<change>] [base]`; degrades gracefully for merged/deleted branches. The view
  that links the ledger to git + specs, distinct from `/ss-replay` and `/ss-report`. bash +
  PowerShell. (28 skills.)
```

Do NOT rename `[Unreleased]`; don't disturb the dated version sections or the footer.

- [ ] **Step 2: Surface it in the README**

Read `README.md`. Two surgical edits:
1. Add `/ss-trace` to the **Supporting skills** inline list (the line with `/ss-init` … `/ss-stats`), right after `/ss-stats`. (Inline list only — NOT a standalone table.)
2. Bump the skills count: GREP for the current count (badge `skills-27` and `**27 skills, ...**` prose); change **27 → 28** in both. If you find a different number, bump that actual number by one and note it.

Match surrounding style; don't restructure.

- [ ] **Step 3: Verify nothing regressed**

Run: `bash scripts/lint-skills.sh .`
Expected: clean, 28 skills. (Authoritative quick check; `tests/run.sh` is slow.)

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: surface /ss-trace in README + CHANGELOG"
```

---

## Self-Review (completed by plan author)

- **Spec coverage:** CLI + defaults + exit 0/1/2 (T1) · slug derivation (T1+T2) · intent slug-glob incl. no-docs (T1+T2) · lineage interleave with G/C tie-break + STATUS upper-case + SKIP + note trim (T1+T2) · UTC-ISO commit join (`TZ=UTC git log`) (T1+T2) · graceful branch-not-found + no-trace (T1+T2) · footer gates/commits/files/head (T1+T2) · output format/widths/separators (T1, spec §6) · byte-identical twins incl. ts re-normalization + Ordinal sort + `$env:TZ` + `$Rest` (T2) · parity on full + branch-not-found (T2) · tests→`run.sh [13/13]` (T1–T2) · skill (T3) · README 28 + CHANGELOG (T4). All spec sections map to a task.
- **Placeholder scan:** none — the bash script is author-verified end-to-end (full trace, branch-not-found, no-trace); the test fixture + ps1 are complete.
- **Type/name consistency:** the tagged-row protocol (`<ts>\t{G|C}\t…`), the `G`/`C` tie-break, the `MM-DD HH:MM` slice, the `%-8s`/`%-5s` ≡ `{1,-8}`/`{2,-5}` widths, the gate-row right-trim, the `origin:`/`intent:`/`lineage` labels, and the `(no spec/plan docs found)` / `(branch '…' not found; git commits omitted)` / `no trace for` strings are identical across bash, PowerShell, and the tests.

---

## Execution Handoff

Recommended: **subagent-driven** — Task 1 (bash, author-verified) and Task 2 (PowerShell parity) on sonnet (the ledger↔git↔ps1 join is the parity-sensitive surface), Tasks 3–4 (markdown) on haiku; per-task spec+quality review, opus whole-branch review at the end (the merged-branch case + cross-twin sort/ts parity are the things to probe adversarially).
