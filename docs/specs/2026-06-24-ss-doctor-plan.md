# /ss-doctor (project health check) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/ss-doctor` — a read-only project health check (bash `scripts/ss-doctor` + PowerShell twin, skill, tests, docs) that runs five checks, prints a `[OK]/[WARN]/[FAIL]` checklist with an actionable fix per problem, and exits 0/1/2.

**Architecture:** Five ordered checks (jq, git, config, gitignore, ledger), each emitting one formatted row and bumping ok/warn/fail counters; a fixed-label footer + verdict; exit 1 iff any FAIL. The ledger is validated jq-free (awk structural check) so doctor works even when jq is the missing dependency. The PowerShell twin mirrors logic and stdout byte-for-byte.

**Tech Stack:** Bash; PowerShell 7 (`pwsh`); `awk`/`grep`/`git`; the existing `scripts/ss-init` (seeds fixtures) and `scripts/ledger`.

## Global Constraints

(Verbatim from the spec; every task implicitly includes these.)

- **Byte-identical ASCII stdout** across `scripts/ss-doctor` (bash) and `scripts/ss-doctor.ps1`. No Unicode.
- **Read-only** — doctor never writes/mutates anything. No flags. Unknown argument → stderr usage, **exit 2**.
- **Exit codes:** `0` healthy or warnings-only; `1` if any `[FAIL]`; `2` usage error.
- **Runtime dir** = `${SUPERSTACK_DIR:-.superstack}`. User-facing text uses the literal `.superstack/`.
- **Five checks**, in this order, each one row:
  1. **jq** — `command -v jq`. OK → `<jq --version> on PATH` (fall back to `jq` if empty). FAIL → `not found -> install jq (needed by audit/report/replay/evolve)`.
  2. **git** — OK (inside repo) → `git repo (branch: <branch-or-detached>)`. WARN (git not on PATH) → `git not on PATH -> branch detection degrades (change=default)`. WARN (not a repo) → `not a git repo -> ledger change will be "default"; gitignore check skipped`.
  3. **config** — present+valid → `mandatory_phases=<v>  evolve_threshold=<v>`. present+invalid → WARN first problem: `unknown phase "<x>" in mandatory_phases -> edit .superstack/config` or `evolve_threshold "<x>" not a positive integer -> edit .superstack/config`. missing → WARN → `.superstack/config missing -> run /ss-init`. Valid phases: `frame plan build review qa secure ship learn`; `evolve_threshold` must be all-digits and `>= 1`.
  4. **gitignore** — not a repo → OK → `n/a (not a git repo)`. repo + ignored → OK → `.superstack/ is gitignored`. repo + not ignored → WARN → `.superstack/ not gitignored -> run /ss-init`. Match strips `\r`, whole-line equal to `.superstack/` or `.superstack`.
  5. **ledger** — absent → WARN → `no ledger yet -> run /ss-init or start the loop`. empty (0 non-empty lines) → WARN → `ledger is empty -> run /ss-init or start the loop`. all well-formed → OK → `<N> entries, all well-formed`. M malformed → FAIL → `<M> of <N> lines malformed -> inspect .superstack/ledger.jsonl`. Well-formed = non-empty line matching `^{.*}$`, counted with `awk` (no jq).
- **Output:** header `ss-doctor: SuperStack project health (.superstack/)`, a 54-dash separator, rows `printf '  %-6s %-10s %s\n' "[STATUS]" "label" "detail"` (PowerShell `'  {0,-6} {1,-10} {2}'`), separator, footer `ok: <n>   warnings: <n>   problems: <n>   verdict: <TOKEN>` (3 spaces between fields; no pluralization). `<TOKEN>` = `HEALTHY` / `WARNINGS` / `PROBLEMS`.
- Config value reads strip `\r` (configs written by the ps1 twin are CRLF). PowerShell sets `$PSNativeCommandUseErrorActionPreference = $false` so git's non-zero exits don't throw under `$ErrorActionPreference='Stop'`.
- Commits: conventional-commit, no AI attribution. Ships in the next release (`[Unreleased]`); skills → 25.

Reference siblings: `scripts/ss-init` (style, gitignore dup-guard, cygpath), `scripts/ledger`, `tests/init.test.sh` (harness). Spec: `docs/specs/2026-06-24-ss-doctor-design.md`.

---

## File Structure

- `scripts/ss-doctor` — bash (Task 1)
- `scripts/ss-doctor.ps1` — PowerShell twin (Task 2)
- `tests/doctor.test.sh` — behavior tests (Task 1) + parity test (Task 2)
- `tests/run.sh` — wire `[10/10]`, bump `[N/9]`→`[N/10]` (Task 1)
- `skills/doctor/SKILL.md` — the skill (Task 3); also re-link `skills/init/SKILL.md` (Task 3)
- `README.md`, `CHANGELOG.md` — surface it (Task 4)

---

## Task 1: `scripts/ss-doctor` (bash) + tests + run.sh wiring

**Model:** sonnet.

**Files:**
- Create: `scripts/ss-doctor`
- Create: `tests/doctor.test.sh`
- Modify: `tests/run.sh`

**Interfaces:**
- Consumes: `scripts/ss-init` (to seed healthy fixtures in tests), `scripts/ledger` format.
- Produces: `scripts/ss-doctor` (no args) printing the five-check report + exit 0/1/2.

- [ ] **Step 1: Write the failing tests** — create `tests/doctor.test.sh`

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavior + parity tests for scripts/ss-doctor.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }
newrepo() { local t; t="$(mktemp -d)"; ( cd "$t" && git init -q . && git config user.email t@t && git config user.name t ); printf '%s' "$t"; }

# --- healthy: ss-init then ss-doctor ---
T="$(newrepo)"; export SUPERSTACK_DIR="$T/.superstack"
( cd "$T" && bash "$ROOT/scripts/ss-init" >/dev/null )
out="$(cd "$T" && bash "$ROOT/scripts/ss-doctor")"; rc=$?
chk "healthy config OK"   'printf "%s" "$out" | grep -qE "\[OK\] +config"'
chk "healthy ledger OK"   'printf "%s" "$out" | grep -qE "\[OK\] +ledger +1 entries"'
chk "healthy gitignore OK" 'printf "%s" "$out" | grep -qE "\[OK\] +gitignore"'
chk "healthy verdict"     'printf "%s" "$out" | grep -qF "verdict: HEALTHY"'
chk "healthy exit 0"      '[ "$rc" -eq 0 ]'
chk "healthy no warn/fail" '! printf "%s" "$out" | grep -qE "\[WARN\]|\[FAIL\]"'

# --- not initialized ---
T2="$(newrepo)"; export SUPERSTACK_DIR="$T2/.superstack"
out2="$(cd "$T2" && bash "$ROOT/scripts/ss-doctor")"; rc2=$?
chk "uninit config WARN"   'printf "%s" "$out2" | grep -qE "\[WARN\] +config +\.superstack/config missing"'
chk "uninit ledger WARN"   'printf "%s" "$out2" | grep -qE "\[WARN\] +ledger +no ledger yet"'
chk "uninit gitignore WARN" 'printf "%s" "$out2" | grep -qE "\[WARN\] +gitignore +\.superstack/ not gitignored"'
chk "uninit verdict"       'printf "%s" "$out2" | grep -qF "verdict: WARNINGS"'
chk "uninit exit 0"        '[ "$rc2" -eq 0 ]'

# --- corrupt ledger -> FAIL, exit 1 ---
T3="$(newrepo)"; export SUPERSTACK_DIR="$T3/.superstack"
mkdir -p "$SUPERSTACK_DIR"
printf '%s\n' '{"ts":"2026-06-24T00:00:00Z","change":"main","phase":"frame","event":"enter","status":"na","note":""}' > "$SUPERSTACK_DIR/ledger.jsonl"
printf '%s\n' '{"ts":"2026-06-24T00:01:00Z" TRUNCATED' >> "$SUPERSTACK_DIR/ledger.jsonl"
out3="$(cd "$T3" && bash "$ROOT/scripts/ss-doctor")"; rc3=$?
chk "corrupt ledger FAIL" 'printf "%s" "$out3" | grep -qE "\[FAIL\] +ledger +1 of 2 lines malformed"'
chk "corrupt verdict"     'printf "%s" "$out3" | grep -qF "verdict: PROBLEMS"'
chk "corrupt exit 1"      '[ "$rc3" -eq 1 ]'

# --- invalid config ---
T4="$(newrepo)"; export SUPERSTACK_DIR="$T4/.superstack"
mkdir -p "$SUPERSTACK_DIR"
printf 'mandatory_phases=review,bogus\nevolve_threshold=3\n' > "$SUPERSTACK_DIR/config"
out4="$(cd "$T4" && bash "$ROOT/scripts/ss-doctor")"
chk "invalid phase WARN" 'printf "%s" "$out4" | grep -qE "\[WARN\] +config +unknown phase .bogus. in mandatory_phases"'
printf 'mandatory_phases=review,secure\nevolve_threshold=x\n' > "$SUPERSTACK_DIR/config"
out4b="$(cd "$T4" && bash "$ROOT/scripts/ss-doctor")"
chk "invalid threshold WARN" 'printf "%s" "$out4b" | grep -qE "evolve_threshold .x. not a positive integer"'

# --- jq-free resilience: curated PATH without jq (guarded by symlink capability) ---
probe="$(mktemp -d)"
if ln -s "$(command -v awk)" "$probe/awk" 2>/dev/null; then
  bindir="$(mktemp -d)"
  for b in bash git grep awk tr cut tail sed cat env; do
    src="$(command -v "$b" 2>/dev/null)"; [ -n "$src" ] && ln -s "$src" "$bindir/$b" 2>/dev/null
  done
  bashbin="$(command -v bash)"
  T5="$(newrepo)"; export SUPERSTACK_DIR="$T5/.superstack"
  ( cd "$T5" && bash "$ROOT/scripts/ss-init" >/dev/null )   # seed with full PATH (jq present)
  out5="$(cd "$T5" && PATH="$bindir" "$bashbin" "$ROOT/scripts/ss-doctor")"; rc5=$?
  chk "jq-missing FAIL"        'printf "%s" "$out5" | grep -qE "\[FAIL\] +jq +not found"'
  chk "jq-missing ledger OK"   'printf "%s" "$out5" | grep -qE "\[OK\] +ledger"'
  chk "jq-missing exit 1"      '[ "$rc5" -eq 1 ]'
else
  echo "  SKIP jq-free resilience (symlinks unavailable)"
fi

# --- non-git dir ---
T6="$(mktemp -d)"; export SUPERSTACK_DIR="$T6/.superstack"
out6="$(cd "$T6" && bash "$ROOT/scripts/ss-doctor")"
chk "non-git git WARN"      'printf "%s" "$out6" | grep -qE "\[WARN\] +git +not a git repo"'
chk "non-git gitignore na"  'printf "%s" "$out6" | grep -qE "\[OK\] +gitignore +n/a"'

echo
[ "$fail" -eq 0 ] && echo "DOCTOR TESTS PASS" || echo "DOCTOR TESTS FAILED"
exit "$fail"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/doctor.test.sh`
Expected: FAIL — `scripts/ss-doctor` does not exist yet.

- [ ] **Step 3: Write `scripts/ss-doctor`**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Read-only health check of a project's SuperStack runtime.
# Exit 0 = healthy/warnings, 1 = problems, 2 = usage error.
# Usage: ss-doctor
set -uo pipefail
[ "$#" -eq 0 ] || { echo "ss-doctor: unexpected argument '$1' (usage: ss-doctor)" >&2; exit 2; }

dir="${SUPERSTACK_DIR:-.superstack}"
config="$dir/config"; ledger="$dir/ledger.jsonl"
ok=0; warn=0; fail=0

emit() { # emit STATUS LABEL DETAIL
  case "$1" in OK) ok=$((ok+1));; WARN) warn=$((warn+1));; FAIL) fail=$((fail+1));; esac
  printf '  %-6s %-10s %s\n' "[$1]" "$2" "$3"
}

SEP="$(printf -- '-%.0s' {1..54})"
printf 'ss-doctor: SuperStack project health (.superstack/)\n'
printf '%s\n' "$SEP"

# 1. jq -------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  ver="$(jq --version 2>/dev/null)"
  emit OK jq "${ver:-jq} on PATH"
else
  emit FAIL jq "not found -> install jq (needed by audit/report/replay/evolve)"
fi

# 2. git ------------------------------------------------------------
in_repo=0; root=""
if command -v git >/dev/null 2>&1; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    br="$(git branch --show-current 2>/dev/null)"; [ -n "$br" ] || br="detached"
    emit OK git "git repo (branch: $br)"
    in_repo=1; root="$(git rev-parse --show-toplevel 2>/dev/null)"
  else
    emit WARN git "not a git repo -> ledger change will be \"default\"; gitignore check skipped"
  fi
else
  emit WARN git "git not on PATH -> branch detection degrades (change=default)"
fi

# 3. config ---------------------------------------------------------
if [ -f "$config" ]; then
  mp="$(grep '^mandatory_phases=' "$config" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\r')"
  et="$(grep '^evolve_threshold=' "$config" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\r')"
  problem=""
  valid_phases=" frame plan build review qa secure ship learn "
  if [ -n "$mp" ]; then
    for p in $(printf '%s' "$mp" | tr ',' ' '); do
      case "$valid_phases" in *" $p "*) ;; *) problem="unknown phase \"$p\" in mandatory_phases"; break;; esac
    done
  fi
  if [ -z "$problem" ] && [ -n "$et" ]; then
    case "$et" in
      *[!0-9]*) problem="evolve_threshold \"$et\" not a positive integer";;
      *) [ "$et" -ge 1 ] 2>/dev/null || problem="evolve_threshold \"$et\" not a positive integer";;
    esac
  fi
  if [ -n "$problem" ]; then emit WARN config "$problem -> edit .superstack/config"
  else emit OK config "mandatory_phases=${mp:-review,secure}  evolve_threshold=${et:-3}"
  fi
else
  emit WARN config ".superstack/config missing -> run /ss-init"
fi

# 4. gitignore ------------------------------------------------------
if [ "$in_repo" -eq 1 ]; then
  gif="$root/.gitignore"
  if [ -f "$gif" ] && tr -d '\r' < "$gif" | grep -qxF -e '.superstack/' -e '.superstack'; then
    emit OK gitignore ".superstack/ is gitignored"
  else
    emit WARN gitignore ".superstack/ not gitignored -> run /ss-init"
  fi
else
  emit OK gitignore "n/a (not a git repo)"
fi

# 5. ledger ---------------------------------------------------------
if [ -f "$ledger" ]; then
  total="$(awk 'NF{n++} END{print n+0}' "$ledger")"
  bad="$(awk 'NF && $0 !~ /^\{.*\}$/{c++} END{print c+0}' "$ledger")"
  if [ "$total" -eq 0 ]; then emit WARN ledger "ledger is empty -> run /ss-init or start the loop"
  elif [ "$bad" -gt 0 ]; then emit FAIL ledger "$bad of $total lines malformed -> inspect .superstack/ledger.jsonl"
  else emit OK ledger "$total entries, all well-formed"
  fi
else
  emit WARN ledger "no ledger yet -> run /ss-init or start the loop"
fi

# footer ------------------------------------------------------------
printf '%s\n' "$SEP"
verdict=HEALTHY
[ "$warn" -gt 0 ] && verdict=WARNINGS
[ "$fail" -gt 0 ] && verdict=PROBLEMS
printf 'ok: %d   warnings: %d   problems: %d   verdict: %s\n' "$ok" "$warn" "$fail" "$verdict"
[ "$fail" -gt 0 ] && exit 1
exit 0
```

- [ ] **Step 4: Make it executable and run the tests**

Run: `chmod +x scripts/ss-doctor && bash tests/doctor.test.sh`
Expected: `DOCTOR TESTS PASS`. If `healthy ledger OK` fails, confirm `ss-init` seeded one genesis entry; if the jq-free block errors, check the curated-PATH symlinks.

- [ ] **Step 5: Wire the suite into `tests/run.sh`**

In `tests/run.sh`: change the nine labels `[1/9]`…`[9/9]` to `[1/10]`…`[9/10]`. Then insert after the `[9/10] init behavior` block (after its closing `fi`, before the final summary `echo`):

```bash
echo "[10/10] doctor behavior"
if bash "$ROOT/tests/doctor.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - doctor suite"; fail=1
fi
```

- [ ] **Step 6: Run the full suite + lint**

Run: `bash tests/run.sh && bash scripts/lint-skills.sh .`
Expected: `[1/10]`…`[10/10]` PASS, `ALL TESTS PASS`; lint clean.

- [ ] **Step 7: Commit**

```bash
git add scripts/ss-doctor tests/doctor.test.sh tests/run.sh
git commit -m "feat(doctor): add ss-doctor project health check (bash)"
```

---

## Task 2: `scripts/ss-doctor.ps1` (PowerShell twin) + parity test

**Model:** sonnet.

**Files:**
- Create: `scripts/ss-doctor.ps1`
- Modify: `tests/doctor.test.sh` (append a parity block before the summary)

**Interfaces:**
- Consumes: the bash `scripts/ss-doctor` behavior + output from Task 1 (must match byte-for-byte).
- Produces: `scripts/ss-doctor.ps1` (no params) with byte-identical stdout + exit 0/1/2.

- [ ] **Step 1: Append the failing parity test** to `tests/doctor.test.sh`, immediately before the final `echo`/summary:

```bash
# parity: ss-doctor is read-only, so compare a real run on the same healthy fixture
if command -v pwsh >/dev/null 2>&1; then
  if command -v cygpath >/dev/null 2>&1; then ps1arg="$(cygpath -w "$ROOT/scripts/ss-doctor.ps1")"; else ps1arg="$ROOT/scripts/ss-doctor.ps1"; fi
  T7="$(newrepo)"; export SUPERSTACK_DIR="$T7/.superstack"
  ( cd "$T7" && bash "$ROOT/scripts/ss-init" >/dev/null )
  pb="$(cd "$T7" && bash "$ROOT/scripts/ss-doctor")"
  pp="$(cd "$T7" && pwsh -NoProfile -File "$ps1arg" | tr -d '\r')"
  chk "ps1 parity (healthy)" '[ "$pb" = "$pp" ]'
else
  echo "  SKIP ps1 parity (pwsh not installed)"
fi
```

- [ ] **Step 2: Run the tests to confirm the parity check fails**

Run: `bash tests/doctor.test.sh`
Expected: behavior checks PASS; `ps1 parity (healthy)` FAIL (ps1 missing) — or SKIP if no `pwsh`.

- [ ] **Step 3: Write `scripts/ss-doctor.ps1`**

```powershell
#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Read-only health check of a project's SuperStack runtime.
# Exit 0 = healthy/warnings, 1 = problems, 2 = usage error.
# Usage: ss-doctor.ps1
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false  # git non-zero exits must not throw
if ($args.Count -gt 0) { [Console]::Error.WriteLine("ss-doctor: unexpected argument '$($args[0])' (usage: ss-doctor)"); exit 2 }

$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
if ($dir -match '^/[a-zA-Z]/') { try { $dir = (& cygpath -w $dir 2>$null).Trim() } catch {} }
$config = Join-Path $dir 'config'
$ledger = Join-Path $dir 'ledger.jsonl'

$script:ok = 0; $script:warn = 0; $script:fail = 0
$lines = @('ss-doctor: SuperStack project health (.superstack/)', ('-' * 54))
function Emit($status, $label, $detail) {
  switch ($status) { 'OK' { $script:ok++ } 'WARN' { $script:warn++ } 'FAIL' { $script:fail++ } }
  $script:lines += ('  {0,-6} {1,-10} {2}' -f "[$status]", $label, $detail)
}
# allow Emit to see $lines as script scope
$script:lines = $lines

# 1. jq
if (Get-Command jq -ErrorAction SilentlyContinue) {
  $ver = (jq --version 2>$null); if (-not $ver) { $ver = 'jq' }
  Emit OK jq "$ver on PATH"
} else {
  Emit FAIL jq 'not found -> install jq (needed by audit/report/replay/evolve)'
}

# 2. git
$inRepo = $false; $root = ''
if (Get-Command git -ErrorAction SilentlyContinue) {
  $null = (git rev-parse --is-inside-work-tree 2>$null)
  if ($LASTEXITCODE -eq 0) {
    $br = (git branch --show-current 2>$null); if (-not $br) { $br = 'detached' }
    Emit OK git "git repo (branch: $br)"
    $inRepo = $true; $root = (git rev-parse --show-toplevel 2>$null)
  } else {
    Emit WARN git 'not a git repo -> ledger change will be "default"; gitignore check skipped'
  }
} else {
  Emit WARN git 'git not on PATH -> branch detection degrades (change=default)'
}

# 3. config
if (Test-Path $config) {
  $mp = ((Get-Content $config | Where-Object { $_ -match '^mandatory_phases=' } | Select-Object -Last 1) -replace '^mandatory_phases=', '')
  $et = ((Get-Content $config | Where-Object { $_ -match '^evolve_threshold=' } | Select-Object -Last 1) -replace '^evolve_threshold=', '')
  $mp = if ($mp) { $mp.Trim() } else { '' }
  $et = if ($et) { $et.Trim() } else { '' }
  $problem = ''
  $valid = @('frame','plan','build','review','qa','secure','ship','learn')
  if ($mp) { foreach ($p in ($mp -split ',')) { if ($p -and ($valid -notcontains $p)) { $problem = "unknown phase ""$p"" in mandatory_phases"; break } } }
  if (-not $problem -and $et) { if ($et -notmatch '^[0-9]+$' -or [int]$et -lt 1) { $problem = "evolve_threshold ""$et"" not a positive integer" } }
  if ($problem) { Emit WARN config "$problem -> edit .superstack/config" }
  else {
    $mpShow = if ($mp) { $mp } else { 'review,secure' }
    $etShow = if ($et) { $et } else { '3' }
    Emit OK config "mandatory_phases=$mpShow  evolve_threshold=$etShow"
  }
} else {
  Emit WARN config '.superstack/config missing -> run /ss-init'
}

# 4. gitignore
if ($inRepo) {
  $gif = Join-Path $root '.gitignore'
  $ignored = $false
  if (Test-Path $gif) {
    $ignored = @(Get-Content $gif | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -eq '.superstack/' -or $_ -eq '.superstack' }).Count -gt 0
  }
  if ($ignored) { Emit OK gitignore '.superstack/ is gitignored' }
  else { Emit WARN gitignore '.superstack/ not gitignored -> run /ss-init' }
} else {
  Emit OK gitignore 'n/a (not a git repo)'
}

# 5. ledger
if (Test-Path $ledger) {
  $nonEmpty = @(Get-Content $ledger | Where-Object { $_.Trim() -ne '' })
  $total = $nonEmpty.Count
  $bad = @($nonEmpty | Where-Object { $_.Trim() -notmatch '^\{.*\}$' }).Count
  if ($total -eq 0) { Emit WARN ledger 'ledger is empty -> run /ss-init or start the loop' }
  elseif ($bad -gt 0) { Emit FAIL ledger "$bad of $total lines malformed -> inspect .superstack/ledger.jsonl" }
  else { Emit OK ledger "$total entries, all well-formed" }
} else {
  Emit WARN ledger 'no ledger yet -> run /ss-init or start the loop'
}

# footer
$script:lines += ('-' * 54)
$verdict = if ($script:fail -gt 0) { 'PROBLEMS' } elseif ($script:warn -gt 0) { 'WARNINGS' } else { 'HEALTHY' }
$script:lines += ('ok: {0}   warnings: {1}   problems: {2}   verdict: {3}' -f $script:ok, $script:warn, $script:fail, $verdict)
Write-Output ($script:lines -join "`n")
if ($script:fail -gt 0) { exit 1 }
exit 0
```

Parity notes for the implementer:
- `'  {0,-6} {1,-10} {2}'` mirrors bash `printf '  %-6s %-10s %s'`; `[OK]` (4) pads to 6, `[WARN]`/`[FAIL]` (6) don't; the 54-dash separator (`'-' * 54`) matches bash `printf -- '-%.0s' {1..54}`.
- The detail strings (with `->`, `"`, `n/a`) must match the bash twin byte-for-byte. `git`'s `not a git repo -> ... "default"; gitignore check skipped` uses literal double-quotes.
- `$PSNativeCommandUseErrorActionPreference = $false` is required: without it, `git rev-parse --is-inside-work-tree` exiting 128 outside a repo throws under `Stop`, breaking the non-git path.
- The `jq --version` and `git branch --show-current` substrings are identical across twins on the same machine; the parity test runs both on one machine so they match.
- If the `function Emit` / `$script:lines` scoping misbehaves, ensure `$script:lines` is the single accumulator both `Emit` and the footer append to.

- [ ] **Step 4: Run the tests to verify parity passes**

Run: `bash tests/doctor.test.sh`
Expected: all PASS including `ps1 parity (healthy)` (or SKIP if no `pwsh`) → `DOCTOR TESTS PASS`. If parity fails, diff `bash scripts/ss-doctor` vs `pwsh -NoProfile -File scripts/ss-doctor.ps1 | tr -d '\r'` (both run from the same `ss-init`-seeded git tmp dir) and reconcile.

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh`
Expected: `[1/10]`…`[10/10]` PASS, `ALL TESTS PASS`.

- [ ] **Step 6: Commit**

```bash
git add scripts/ss-doctor.ps1 tests/doctor.test.sh
git commit -m "feat(doctor): PowerShell parity for ss-doctor"
```

---

## Task 3: `skills/doctor/SKILL.md` + re-link `skills/init/SKILL.md`

**Model:** haiku (pure markdown).

**Files:**
- Create: `skills/doctor/SKILL.md`
- Modify: `skills/init/SKILL.md`

**Interfaces:** documents Task 1–2 behavior; the re-link restores the `[[ss-doctor]]` wikilink now that the target skill exists.

- [ ] **Step 1: Write the doctor skill** — create `skills/doctor/SKILL.md`

```markdown
---
name: ss-doctor
description: Use to verify a project's SuperStack setup is healthy - it checks jq, git, the .superstack/config, gitignore, and the ledger, printing a pass/warn/fail checklist with an actionable fix for each problem. Read-only; the verify counterpart to /ss-init.
---

# Doctor - verify a project's loop setup

Read-only health check. Run it to confirm this project's `.superstack/` runtime is sound, or to
diagnose why a loop command is misbehaving. It never changes anything - it tells you what to fix.

## Steps

1. Run `scripts/ss-doctor` (PowerShell: `scripts/ss-doctor.ps1`). No arguments.
2. Read the checklist - each line is `[OK]`, `[WARN]`, or `[FAIL]` with a one-line detail and, for
   anything not OK, the exact fix (usually `run /ss-init`):
   - **jq** - required by audit/report/replay/evolve (`[FAIL]` if missing).
   - **git** - repo + branch detection (`[WARN]` outside a repo; the loop still runs).
   - **config** - `.superstack/config` present with valid `mandatory_phases` / `evolve_threshold`.
   - **gitignore** - `.superstack/` is ignored so the runtime dir is not committed.
   - **ledger** - `.superstack/ledger.jsonl` is present and every line is well-formed.
3. Act on the footer verdict: `HEALTHY` (exit 0), `WARNINGS` (exit 0, advisory), or `PROBLEMS`
   (exit 1 - safe to use as a CI preflight gate).

## Note

`/ss-doctor` only diagnoses; it does not repair. The fix for a missing config/gitignore/ledger is
[[ss-init]] (idempotent). Doctor validates the ledger without `jq`, so it still works while telling
you `jq` is missing.

## Lineage

Original to SuperStack - the verify leg of the adoption track ([[ss-init]] sets up, ss-doctor verifies).
```

- [ ] **Step 2: Re-link the init skill** — in `skills/init/SKILL.md`, the `## Note` section currently reads `... never verifies your setup (that is the planned /ss-doctor).` Now that the skill exists, change `the planned /ss-doctor` to the wikilink `[[ss-doctor]]`, so the sentence reads: `... and never verifies your setup (that is [[ss-doctor]]). It only prepares this project's .superstack/ runtime.`

- [ ] **Step 3: Verify lint** — both skills present, wikilinks resolve

Run: `bash scripts/lint-skills.sh .`
Expected: PASS — reports 25 skills; `[[ss-doctor]]` and `[[ss-init]]` both resolve (no broken-link error).

- [ ] **Step 4: Commit**

```bash
git add skills/doctor/SKILL.md skills/init/SKILL.md
git commit -m "docs(doctor): add /ss-doctor skill; re-link init's [[ss-doctor]]"
```

---

## Task 4: README + CHANGELOG

**Model:** haiku (pure markdown).

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update the CHANGELOG**

Read `CHANGELOG.md`. Under the top `## [Unreleased]` heading, add a `### Added` group (create it if absent) with:

```markdown
- **`/ss-doctor`:** read-only project health check — verifies `jq`, `git`, `.superstack/config`,
  gitignore, and the ledger, printing a `[OK]`/`[WARN]`/`[FAIL]` checklist with an actionable fix per
  problem; exits 0 (healthy/warnings) or 1 (problems) for CI. The verify leg paired with `/ss-init`.
  bash + PowerShell. (25 skills.)
```

Do NOT rename `[Unreleased]` to a version. Don't disturb existing entries.

- [ ] **Step 2: Surface it in the README**

Read `README.md`. Two surgical edits:
1. Add `/ss-doctor` to the **Supporting skills** inline list (the line containing `/ss-init` … `run /ss-help for the full index`), right after `/ss-init`.
2. Bump the skills count: first GREP the README for the current count (badge `skills-24` and the `**24 skills, ...**` prose); change **24 → 25** in both. If you find a different number, bump that actual number by one and note it in your report.

Match surrounding style; don't restructure.

- [ ] **Step 3: Verify nothing regressed**

Run: `bash tests/run.sh`
Expected: `ALL TESTS PASS`.

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: surface /ss-doctor in README + CHANGELOG"
```

---

## Self-Review (completed by plan author)

- **Spec coverage:** no-args/usage exit 2 (T1) · five checks with exact OK/WARN/FAIL + details (T1) · jq-free awk ledger validation (T1) · exit 0/1/2 semantics (T1) · output format + 54-dash sep + fixed-label footer/verdict (T1, spec §6) · byte-identical twins + `$PSNativeCommandUseErrorActionPreference` (T2) · read-only non-dry parity (T2) · 7-case tests → `run.sh [10/10]` (T1–T2) · doctor skill (T3) · init re-link `[[ss-doctor]]` (T3) · README 25 + CHANGELOG (T4). All spec sections map to a task.
- **Placeholder scan:** none — every code/test/doc block is complete.
- **Type/name consistency:** the status tokens `OK`/`WARN`/`FAIL`, the `[$status]`/`[$1]` bracketing, the `%-6s %-10s %s` ≡ `{0,-6} {1,-10} {2}` format, the 54-dash separator, the verdict tokens `HEALTHY`/`WARNINGS`/`PROBLEMS`, the valid-phase list, and every detail string are identical across bash, PowerShell, and the test assertions.

---

## Execution Handoff

Recommended: **subagent-driven** — Task 1 (bash) and Task 2 (PowerShell parity) on sonnet, Tasks 3–4 (markdown) on haiku; per-task spec+quality review, opus whole-branch review at the end.
