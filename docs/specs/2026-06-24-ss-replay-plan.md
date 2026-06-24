# /ss-replay (loop replay) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/ss-replay` — a bash script + PowerShell twin (and skill) that reconstruct one loop run from `.superstack/ledger.jsonl` as a chronological ASCII timeline (elapsed, phase, event, marker, `(retry)`) with a one-line footer of story stats.

**Architecture:** A single jq pass over the ledger (filtered to the selected `change`) emits tab-separated `R` (row) lines then one `F` (footer) line; the bash layer formats elapsed seconds → `+Nm` and renders aligned columns. The PowerShell twin replicates the same logic with native objects and identical formatting. Both produce byte-identical ASCII output.

**Tech Stack:** Bash + jq; PowerShell 7 (`pwsh`); bash test harness (`tests/*.test.sh`) wired through `tests/run.sh`.

## Global Constraints

(Verbatim from the spec; every task implicitly includes these.)

- **Byte-identical ASCII stdout** across `scripts/ss-replay` (bash) and `scripts/ss-replay.ps1` (PowerShell). No Unicode glyphs (no box-drawing, no middle-dot).
- **Portable patterns:** read the ledger via `jq … < "$ledger"`, strip `\r` with `tr -d '\r'`. Compute elapsed via **`jq fromdateiso8601`** (NOT GNU-only `date -d`, which `ss-report` uses and which silently fails on macOS).
- **CLI:** `ss-replay [change] [--save]` — **positional `[change]`** to match the sibling `ss-report` (a deliberate refinement from the spec's `--change`, for a consistent CLI family). PowerShell: `[string]$Change`, `[switch]$Save`. Unknown flag (`-*`) → stderr usage, exit 1.
- **Default = latest run** = `change` of the last ledger entry. Explicit `change` arg overrides.
- **Elapsed formatter = minutes-only `+Nm`** (resolves the spec's prose-vs-example inconsistency in favor of the example; simpler, less parity surface). Footer `total` strips the leading `+` → `~70m`.
- **`(retry)`** prefixes the note on a gate-pass whose phase had an earlier gate-fail in the same run. Computed in **jq** for bash (no associative arrays → macOS bash-3.2 safe); a hashtable in PowerShell.
- **Footer (fixed labels, no pluralization):** `phases: N   gate-retries: N   skips: N   open-fails: N   total: ~Nm`.
- **`--save`** writes a fenced `.md` to `<dir>/replays/<change-with-/→->.md>`, prints `saved -> .superstack/replays/<name>.md` on **stderr** (stdout stays clean, mirroring `ss-report`).
- **No run** → `ss-replay: no run to replay` (default) / `ss-replay: no run found for <change>` (explicit), exit 0.
- **Reporter exit codes:** 0 normally; 1 on usage error; 2 if `jq` missing.
- Commits: conventional-commit, no AI attribution. Ships as **v0.5.0** (23 skills).

Reference siblings to match for style: `scripts/ss-report` (+`.ps1`), `scripts/ledger`. Spec: `docs/specs/2026-06-24-ss-replay-design.md`.

---

## File Structure

- `scripts/ss-replay` — bash (Task 1)
- `scripts/ss-replay.ps1` — PowerShell twin (Task 2)
- `tests/replay.test.sh` — behavior tests (Task 1) + parity test (Task 2)
- `tests/run.sh` — wire as `[8/8]`, bump `[N/7]`→`[N/8]` (Task 1)
- `skills/replay/SKILL.md` — the skill (Task 3)
- `README.md`, `CHANGELOG.md` — surface it (Task 4)

---

## Task 1: `scripts/ss-replay` (bash) + tests + run.sh wiring

**Model:** sonnet.

**Files:**
- Create: `scripts/ss-replay`
- Create: `tests/replay.test.sh`
- Modify: `tests/run.sh`

**Interfaces:**
- Produces: `scripts/ss-replay [change] [--save]` printing the timeline described above. Default = latest run; `--save` → `<dir>/replays/<safe>.md`.
- Consumes: the ledger schema `{ts,change,phase,event,status,note}`; `ts` is zero-padded UTC ISO-8601 (jq `fromdateiso8601`).

- [ ] **Step 1: Write the failing tests** — create `tests/replay.test.sh`

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavior + parity tests for scripts/ss-replay (loop replay).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; export SUPERSTACK_DIR="$TMP/.superstack"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }
mkdir -p "$SUPERSTACK_DIR"

# Two runs. feat/a = older; feat/b = latest. Fixed timestamps -> deterministic elapsed.
cat > "$SUPERSTACK_DIR/ledger.jsonl" <<'JSONL'
{"ts":"2026-06-20T10:00:00Z","change":"feat/a","phase":"frame","event":"enter","status":"na","note":""}
{"ts":"2026-06-20T10:03:00Z","change":"feat/a","phase":"plan","event":"gate","status":"pass","note":"spec ok"}
{"ts":"2026-06-21T09:00:00Z","change":"feat/b","phase":"frame","event":"enter","status":"na","note":""}
{"ts":"2026-06-21T09:29:00Z","change":"feat/b","phase":"build","event":"enter","status":"na","note":""}
{"ts":"2026-06-21T09:56:00Z","change":"feat/b","phase":"review","event":"gate","status":"fail","note":"2 findings"}
{"ts":"2026-06-21T10:08:00Z","change":"feat/b","phase":"review","event":"gate","status":"pass","note":"fixed"}
{"ts":"2026-06-21T10:10:00Z","change":"feat/b","phase":"ship","event":"gate","status":"pass","note":"CI green"}
{"ts":"2026-06-21T10:10:00Z","change":"feat/b","phase":"secure","event":"skip","status":"skip","note":"no IO"}
JSONL

out="$(bash "$ROOT/scripts/ss-replay")"
# default = latest run (feat/b), not feat/a
chk "default picks latest run" 'printf "%s" "$out" | grep -qF "loop replay: feat/b"'
chk "default excludes older run" '! (printf "%s" "$out" | grep -qF "spec ok")'
# elapsed column (minutes-only)
chk "elapsed +0m" 'printf "%s" "$out" | grep -qE "\\+0m +frame +enter"'
chk "elapsed +29m" 'printf "%s" "$out" | grep -qE "\\+29m +build +enter"'
chk "elapsed +68m" 'printf "%s" "$out" | grep -qE "\\+68m +review +gate +PASS"'
# markers
chk "marker FAIL" 'printf "%s" "$out" | grep -qE "review +gate +FAIL +2 findings"'
chk "marker SKIP" 'printf "%s" "$out" | grep -qE "secure +skip +SKIP +no IO"'
# retry tag on the recovered pass
chk "retry tag" 'printf "%s" "$out" | grep -qF "(retry) fixed"'
chk "no spurious retry" '[ "$(printf "%s" "$out" | grep -c "(retry)")" -eq 1 ]'
# footer stats
chk "footer" 'printf "%s" "$out" | grep -qF "phases: 5   gate-retries: 1   skips: 1   open-fails: 0   total: ~70m"'

# explicit change selects the older run
oa="$(bash "$ROOT/scripts/ss-replay" feat/a)"
chk "explicit change" 'printf "%s" "$oa" | grep -qF "loop replay: feat/a" && printf "%s" "$oa" | grep -qF "spec ok"'

# open-fails: a run whose last gate for a phase is a fail
cat > "$SUPERSTACK_DIR/ledger.jsonl" <<'JSONL'
{"ts":"2026-06-22T08:00:00Z","change":"feat/c","phase":"build","event":"enter","status":"na","note":""}
{"ts":"2026-06-22T08:05:00Z","change":"feat/c","phase":"review","event":"gate","status":"fail","note":"bug"}
JSONL
oc="$(bash "$ROOT/scripts/ss-replay" feat/c)"
chk "open-fails counts unrecovered fail" 'printf "%s" "$oc" | grep -qE "open-fails: 1"'

# no run
rm -f "$SUPERSTACK_DIR/ledger.jsonl"
chk "no run default" 'bash "$ROOT/scripts/ss-replay" | grep -qF "no run to replay"'
chk "no run explicit" 'bash "$ROOT/scripts/ss-replay" feat/x | grep -qF "no run found for feat/x"'

# --save writes a fenced markdown file under replays/ and reports the path on stderr
cp /dev/null "$SUPERSTACK_DIR/ledger.jsonl"
cat > "$SUPERSTACK_DIR/ledger.jsonl" <<'JSONL'
{"ts":"2026-06-23T07:00:00Z","change":"feat/d","phase":"frame","event":"enter","status":"na","note":""}
{"ts":"2026-06-23T07:05:00Z","change":"feat/d","phase":"ship","event":"gate","status":"pass","note":"done"}
JSONL
serr="$(bash "$ROOT/scripts/ss-replay" feat/d --save 2>&1 >/dev/null)"
chk "save writes file" '[ -f "$SUPERSTACK_DIR/replays/feat-d.md" ]'
chk "save is fenced" 'head -1 "$SUPERSTACK_DIR/replays/feat-d.md" | grep -qF "\`\`\`"'
chk "save reports path" 'printf "%s" "$serr" | grep -qF "saved -> .superstack/replays/feat-d.md"'

echo
[ "$fail" -eq 0 ] && echo "REPLAY TESTS PASS" || echo "REPLAY TESTS FAILED"
exit "$fail"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/replay.test.sh`
Expected: FAIL — `scripts/ss-replay` does not exist yet (every `chk` fails / script-not-found).

- [ ] **Step 3: Write `scripts/ss-replay`**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Replay one loop run from the ledger as a chronological timeline (the "story" leg).
# Usage: ss-replay [change] [--save]
set -uo pipefail
dir="${SUPERSTACK_DIR:-.superstack}"
ledger="$dir/ledger.jsonl"
save=0; change=""; explicit=0
for a in "$@"; do
  case "$a" in
    --save) save=1;;
    -*) echo "ss-replay: unknown flag '$a' (usage: ss-replay [change] [--save])" >&2; exit 1;;
    *) change="$a"; explicit=1;;
  esac
done
command -v jq >/dev/null 2>&1 || { echo "ss-replay: jq required" >&2; exit 2; }

if [ "$explicit" -eq 0 ] && [ -f "$ledger" ]; then
  change="$(jq -rn '[inputs][-1].change // empty' < "$ledger" | tr -d '\r')"
fi

SEP="------------------------------------------------------"   # 54 dashes
fmt() { printf '+%dm' "$(( $1 / 60 ))"; }   # whole seconds -> +Nm

data=""
if [ -n "$change" ] && [ -f "$ledger" ]; then
  data="$(jq -rn --arg ch "$change" '
    [inputs | select(.change==$ch)] as $rows
    | ($rows|length) as $n
    | if $n==0 then empty else
      ($rows[0].ts|fromdateiso8601) as $t0
      | ( range(0;$n) as $i
          | $rows[$i] as $r
          | (($r.ts|fromdateiso8601)-$t0|floor) as $el
          | (if ($r.status=="na" or $r.status==null) then "" else ($r.status|ascii_upcase) end) as $mk
          | ( ($r.event=="gate" and $r.status=="pass")
              and ([$rows[0:$i][]|select(.phase==$r.phase and .event=="gate" and .status=="fail")]|length>0) ) as $rt
          | ["R",($el|tostring),$r.phase,$r.event,$mk,(if $rt then "1" else "0" end),($r.note//"")]|@tsv ),
        ( ($rows|map(.phase)|unique|length) as $phases
          | ([range(0;$n) as $j | $rows[$j] as $g
              | select($g.event=="gate" and $g.status=="pass")
              | select([$rows[0:$j][]|select(.phase==$g.phase and .event=="gate" and .status=="fail")]|length>0)]|length) as $retries
          | ([$rows[]|select(.event=="skip")]|length) as $skips
          | ([$rows|group_by(.phase)[]|map(select(.event=="gate"))|select(length>0)|last|select(.status=="fail")]|length) as $openfails
          | (($rows[-1].ts|fromdateiso8601)-$t0|floor) as $span
          | ["F",($phases|tostring),($retries|tostring),($skips|tostring),($openfails|tostring),($span|tostring)]|@tsv )
      end
  ' < "$ledger" | tr -d '\r')"
fi

if [ -z "$change" ] || [ -z "$data" ]; then
  if [ "$explicit" -eq 1 ]; then echo "ss-replay: no run found for $change"; else echo "ss-replay: no run to replay"; fi
  exit 0
fi

body=""; fphases=0; fretries=0; fskips=0; fopen=0; fspan=0
while IFS=$'\t' read -r tag a b c d e f; do
  case "$tag" in
    R) note="$f"; [ "$e" = "1" ] && note="(retry) $f"
       line="$(printf '%6s  %-7s %-5s %-4s %s' "$(fmt "$a")" "$b" "$c" "$d" "$note" | sed 's/[[:space:]]*$//')"
       body="${body}${line}"$'\n' ;;
    F) fphases="$a"; fretries="$b"; fskips="$c"; fopen="$d"; fspan="$e" ;;
  esac
done <<EOF
$data
EOF

total="$(fmt "$fspan")"; total="${total#+}"
render() {
  printf '%s\n%s\n' "loop replay: $change" "$SEP"
  printf '%s' "$body"
  printf '%s\n' "$SEP"
  printf 'phases: %s   gate-retries: %s   skips: %s   open-fails: %s   total: ~%s\n' "$fphases" "$fretries" "$fskips" "$fopen" "$total"
}
output="$(render)"
printf '%s\n' "$output"
if [ "$save" -eq 1 ]; then
  mkdir -p "$dir/replays"
  { printf '```\n'; printf '%s\n' "$output"; printf '```\n'; } > "$dir/replays/${change//\//-}.md"
  echo "saved -> .superstack/replays/${change//\//-}.md" >&2
fi
```

- [ ] **Step 4: Make the script executable and run the tests**

Run: `chmod +x scripts/ss-replay && bash tests/replay.test.sh`
Expected: `REPLAY TESTS PASS` (all `chk` lines PASS). If an elapsed/footer assertion fails, check the jq `floor` and the `fmt` integer division; if the retry assertion fails, check the `$rows[0:$i]` prior-fail slice.

- [ ] **Step 5: Wire the suite into `tests/run.sh`**

In `tests/run.sh`: change the seven labels `[1/7]`…`[7/7]` to `[1/8]`…`[7/8]`. Then insert after the `[7/8] evolve follow-ups` block (after its closing `fi`, before the final `echo`):

```bash
echo "[8/8] loop replay behavior"
if bash "$ROOT/tests/replay.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - loop replay suite"; fail=1
fi
```

- [ ] **Step 6: Run the full suite + lint**

Run: `bash tests/run.sh && bash scripts/lint-skills.sh .`
Expected: `[1/8]`…`[8/8]` PASS, `ALL TESTS PASS`; lint clean.

- [ ] **Step 7: Commit**

```bash
git add scripts/ss-replay tests/replay.test.sh tests/run.sh
git commit -m "feat(replay): add ss-replay loop timeline (bash)"
```

---

## Task 2: `scripts/ss-replay.ps1` (PowerShell twin) + parity test

**Model:** sonnet.

**Files:**
- Create: `scripts/ss-replay.ps1`
- Modify: `tests/replay.test.sh` (append a parity block before the summary)

**Interfaces:**
- Consumes: the bash `scripts/ss-replay` behavior + output format from Task 1 (must match byte-for-byte).
- Produces: `scripts/ss-replay.ps1 [change] [-Save]` with byte-identical stdout.

- [ ] **Step 1: Append the failing parity test** to `tests/replay.test.sh`, immediately before the final `echo` / summary lines:

```bash
# parity: ps1 emits byte-identical output to bash (guarded for CI without pwsh)
if command -v pwsh >/dev/null 2>&1; then
  if command -v cygpath >/dev/null 2>&1; then ps1arg="$(cygpath -w "$ROOT/scripts/ss-replay.ps1")"; else ps1arg="$ROOT/scripts/ss-replay.ps1"; fi
  cat > "$SUPERSTACK_DIR/ledger.jsonl" <<'JSONL'
{"ts":"2026-06-21T09:00:00Z","change":"feat/b","phase":"frame","event":"enter","status":"na","note":""}
{"ts":"2026-06-21T09:29:00Z","change":"feat/b","phase":"build","event":"enter","status":"na","note":""}
{"ts":"2026-06-21T09:56:00Z","change":"feat/b","phase":"review","event":"gate","status":"fail","note":"2 findings"}
{"ts":"2026-06-21T10:08:00Z","change":"feat/b","phase":"review","event":"gate","status":"pass","note":"fixed"}
{"ts":"2026-06-21T10:10:00Z","change":"feat/b","phase":"ship","event":"gate","status":"pass","note":"CI green"}
{"ts":"2026-06-21T10:10:00Z","change":"feat/b","phase":"secure","event":"skip","status":"skip","note":"no IO"}
JSONL
  rb="$(bash "$ROOT/scripts/ss-replay" feat/b)"
  rp="$(pwsh -NoProfile -File "$ps1arg" feat/b | tr -d '\r')"
  chk "ps1 parity (explicit)" '[ "$rb" = "$rp" ]'
  db="$(bash "$ROOT/scripts/ss-replay")"
  dp="$(pwsh -NoProfile -File "$ps1arg" | tr -d '\r')"
  chk "ps1 parity (default latest)" '[ "$db" = "$dp" ]'
else
  echo "  SKIP ps1 parity (pwsh not installed)"
fi
```

- [ ] **Step 2: Run the tests to confirm the parity checks fail**

Run: `bash tests/replay.test.sh`
Expected: bash behavior checks still PASS; `ps1 parity *` FAIL (ps1 missing) — or SKIP if `pwsh` absent.

- [ ] **Step 3: Write `scripts/ss-replay.ps1`**

```powershell
#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Replay one loop run from the ledger as a chronological timeline. Usage: ss-replay.ps1 [change] [-Save]
param([string]$Change = "", [switch]$Save)
$ErrorActionPreference = 'Stop'
$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
if ($dir -match '^/[a-zA-Z]/') { try { $dir = (& cygpath -w $dir 2>$null).Trim() } catch {} }
$ledger = Join-Path $dir 'ledger.jsonl'
$explicit = [bool]$Change
$SEP = '------------------------------------------------------'
function Fmt([int]$s) { "+$([math]::Floor($s / 60))m" }

$rows = @()
if (Test-Path $ledger) {
  $all = @(Get-Content $ledger | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
  if (-not $explicit -and $all.Count) { $Change = "$($all[-1].change)" }
  $rows = @($all | Where-Object { "$($_.change)" -eq $Change })
}

if (-not $Change -or $rows.Count -eq 0) {
  if ($explicit) { Write-Output "ss-replay: no run found for $Change" } else { Write-Output "ss-replay: no run to replay" }
  return
}

$t0 = [datetime]$rows[0].ts
$failed = @{}
$retries = 0; $skips = 0
$lines = @("loop replay: $Change", $SEP)
foreach ($r in $rows) {
  $el = [int][math]::Floor((([datetime]$r.ts) - $t0).TotalSeconds)
  $mk = if ($r.status -eq 'na' -or $null -eq $r.status) { '' } else { "$($r.status)".ToUpper() }
  $rt = $false
  if ($r.event -eq 'gate' -and $r.status -eq 'pass' -and $failed.ContainsKey("$($r.phase)")) { $rt = $true; $retries++ }
  if ($r.event -eq 'gate' -and $r.status -eq 'fail') { $failed["$($r.phase)"] = $true }
  if ($r.event -eq 'skip') { $skips++ }
  $note = "$($r.note)"; if ($rt) { $note = "(retry) $note" }
  $lines += ('{0,6}  {1,-7} {2,-5} {3,-4} {4}' -f (Fmt $el), "$($r.phase)", "$($r.event)", $mk, $note).TrimEnd()
}
$phases = @($rows | Select-Object -ExpandProperty phase -Unique).Count
$openfails = 0
foreach ($g in ($rows | Group-Object phase)) {
  $gates = @($g.Group | Where-Object { $_.event -eq 'gate' })
  if ($gates.Count -and $gates[-1].status -eq 'fail') { $openfails++ }
}
$span = [int][math]::Floor((([datetime]$rows[-1].ts) - $t0).TotalSeconds)
$total = (Fmt $span).TrimStart('+')
$lines += $SEP
$lines += "phases: $phases   gate-retries: $retries   skips: $skips   open-fails: $openfails   total: ~$total"
$block = ($lines -join "`n")
Write-Output $block
if ($Save) {
  $rdir = Join-Path $dir 'replays'
  New-Item -ItemType Directory -Force -Path $rdir | Out-Null
  $bt = [char]96
  $fenced = ($bt.ToString() * 3) + "`n" + $block + "`n" + ($bt.ToString() * 3)
  Set-Content -Path (Join-Path $rdir (($Change -replace '/', '-') + '.md')) -Value $fenced -Encoding utf8
}
```

Parity notes for the implementer:
- `[datetime]$r.ts` casts whether `ConvertFrom-Json` left `ts` a string or coerced it to `[datetime]` (it coerces in this environment) — do NOT `[datetime]::Parse` a value that may already be a `[datetime]`.
- Column format `'{0,6}  {1,-7} {2,-5} {3,-4} {4}'` mirrors bash `printf '%6s  %-7s %-5s %-4s %s'`; `.TrimEnd()` mirrors the bash `sed 's/[[:space:]]*$//'` so trailing padding matches.
- `Group-Object phase` preserves input order within groups, so `$gates[-1]` is the chronologically-last gate event (same as jq `group_by | last`).

- [ ] **Step 4: Run the tests to verify parity passes**

Run: `bash tests/replay.test.sh`
Expected: all checks PASS including `ps1 parity (explicit)` and `ps1 parity (default latest)` (or SKIP if `pwsh` absent) → `REPLAY TESTS PASS`. If parity fails, diff `bash scripts/ss-replay feat/b` vs `pwsh -NoProfile -File scripts/ss-replay.ps1 feat/b | tr -d '\r'` and reconcile column widths / footer text.

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh`
Expected: `[1/8]`…`[8/8]` PASS, `ALL TESTS PASS`.

- [ ] **Step 6: Commit**

```bash
git add scripts/ss-replay.ps1 tests/replay.test.sh
git commit -m "feat(replay): PowerShell parity for ss-replay"
```

---

## Task 3: `skills/replay/SKILL.md`

**Model:** haiku (pure markdown).

**Files:**
- Create: `skills/replay/SKILL.md`

**Interfaces:** documents the Task 1–2 behavior; nothing depends on it.

- [ ] **Step 1: Write the skill**

```markdown
---
name: ss-replay
description: Use to see the story of a loop run — replays the ledger as a chronological timeline (each phase entered, every gate pass/fail, retries, skips, with elapsed time) so you can review or share what actually happened, end to end.
---

# Replay - the story of a run

The third leg of the proof trio: `/ss-audit` is the gate, `/ss-report` is the stats,
`/ss-replay` is the **story** — what happened, in order.

## Steps

1. Run `scripts/ss-replay` to replay the latest run (the most recent `change` in the ledger),
   or `scripts/ss-replay <branch>` to replay a specific one.
2. Read the timeline top to bottom: elapsed time (`+Nm` from the start), the phase, the event,
   a `PASS`/`FAIL`/`SKIP` marker, and the note. A `(retry)` tag marks a gate that passed only
   after an earlier failure — the friction worth noticing.
3. Check the footer stats: `phases`, `gate-retries`, `skips`, `open-fails` (a phase whose last
   gate still failed), and total elapsed.
4. To share it, run `scripts/ss-replay <branch> --save` — it writes a fenced Markdown file to
   `.superstack/replays/<branch>.md` you can drop into a PR or postmortem.

## Note

Read-only: replay never changes code or the ledger. It complements `/ss-report` (which
aggregates) by showing the actual sequence. PowerShell users: `scripts/ss-replay.ps1`.

## Lineage

Original to SuperStack - powered by the Loop Ledger that `/ss-audit` and `/ss-report` also read.
```

- [ ] **Step 2: Verify it lints**

Run: `bash scripts/lint-skills.sh .`
Expected: PASS (name `ss-replay`, description 40–500 chars, exactly one H1).

- [ ] **Step 3: Commit**

```bash
git add skills/replay/SKILL.md
git commit -m "docs(replay): add /ss-replay skill"
```

---

## Task 4: README + CHANGELOG

**Model:** haiku (pure markdown).

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update the CHANGELOG**

Read `CHANGELOG.md`. Under the top `## [Unreleased]` heading, add (creating an `### Added` group):

```markdown
### Added
- **`/ss-replay`:** replays a loop run from the ledger as a chronological ASCII timeline
  (elapsed time, phase, event, `PASS`/`FAIL`/`SKIP`, `(retry)` tags) with a footer of story
  stats; `--save` writes a shareable fenced Markdown file to `.superstack/replays/`. The "story"
  leg of the proof trio (audit=gate, report=stats, replay=story). bash + PowerShell. (23 skills.)
```

(At release time `[Unreleased]` becomes `## [0.5.0] - <date>` with the `[0.5.0]` compare link mirroring `[0.4.0]`; not part of this task.)

- [ ] **Step 2: Surface it in the README**

Read `README.md`. In the proof/commands area (near the `/ss-audit` · `/ss-report` listing) add `/ss-replay` with a one-line description: *"replay a run as a chronological timeline (the story leg); `--save` for a shareable Markdown file."* If the README shows a skills count badge or "22 skills" text, bump it to **23**. Match the surrounding table/prose style; do not restructure.

- [ ] **Step 3: Verify nothing regressed**

Run: `bash tests/run.sh`
Expected: `ALL TESTS PASS`.

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: surface /ss-replay in README + CHANGELOG"
```

---

## Self-Review (completed by plan author)

- **Spec coverage:** separate `/ss-replay` script+skill (T1–T3) · default-latest + positional change + `--save` (T1) · elapsed column + duration formatter (T1, minutes-only per Global Constraints) · marker mapping + `(retry)` (T1 jq) · footer stats incl. open-fails (T1) · ASCII byte-identical twins (T2 parity) · fenced `--save` + stderr path (T1) · no-run handling (T1) · tests `tests/replay.test.sh`→`run.sh [8/8]` (T1–T2) · docs/version (T3–T4). All spec sections map to a task.
- **Placeholder scan:** none — every code/test/doc block is complete.
- **Type/name consistency:** `change`/`$Change`, `--save`/`-Save`, `fmt`/`Fmt`, the `R`/`F` TSV tags, column format `%6s  %-7s %-5s %-4s %s` ≡ `{0,6}  {1,-7} {2,-5} {3,-4} {4}`, footer label string, and the `.superstack/replays/<change-with-/→->.md>` path are identical across bash, PowerShell, and the tests.
- **Deviations from spec (flagged):** positional `[change]` instead of `--change` (CLI-family consistency with `ss-report`); minutes-only `+Nm` (matches the spec's own example, simpler).

---

## Execution Handoff

Recommended: **subagent-driven** — Task 1 (bash) and Task 2 (PowerShell parity) on sonnet, Tasks 3–4 (markdown) on haiku; per-task spec+quality review, opus whole-branch review at the end.
