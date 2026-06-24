# /ss-drift (plan-vs-build drift detection) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/ss-drift` — a read-only command (bash `scripts/ss-drift` + PowerShell twin, skill, tests, docs) that compares a plan's declared files against the branch's actual git changes and reports drift in both directions.

**Architecture:** Parse the plan's `**Files:**` blocks into a declared set; collect the changed set from git (`base...HEAD` ∪ working tree, minus `docs/specs/`); report `unplanned` (changed∖declared) and `untouched` (declared∖changed) with counts + a verdict. Exit 1 iff unplanned>0. The PowerShell twin mirrors logic and stdout byte-for-byte.

**Tech Stack:** Bash (`awk`, `comm`, `git`); PowerShell 7 (`pwsh`); the `chk`/`newrepo` test harness via `tests/run.sh`.

## Global Constraints

(Verbatim from the spec; every task implicitly includes these.)

- **Byte-identical ASCII stdout** across `scripts/ss-drift` (bash) and `scripts/ss-drift.ps1`. No Unicode.
- **PARITY-CRITICAL sort:** bash sorts/`comm`s under `export LC_ALL=C` (byte order); the ps1 twin sorts the file lists with `[System.StringComparer]::Ordinal`. These two MUST agree, or list order diverges (e.g. `README` (0x52 'R') sorts before `scripts` (0x73 's') in byte order, but not in culture order).
- **Read-only** — never writes/mutates anything (reads the plan + git only).
- **CLI:** `ss-drift <plan-file> [base]`. `<plan-file>` required; `[base]` default `main`. Any `-…` arg, missing plan, >2 args, nonexistent plan, unresolvable base, or not-a-git-repo → stderr message, **exit 2**.
- **Exit codes:** `0` clean (no unplanned), `1` drift (unplanned>0), `2` usage/precondition.
- **Declared set:** from each `**Files:**` block, the bullets `- Create:`/`- Modify:`/`- Test:` — take the **first backticked token**, strip a trailing `:<digits>[-<digits>]`. Scope strictly to the Files block (exit on blank line, `**`, `### `, or `- [ ]`). Other backticks (e.g. in `**Interfaces:**`) must NOT count.
- **Changed set:** `git diff --name-only <base>...HEAD` ∪ `git diff --name-only HEAD`, drop blanks, exclude paths under `docs/specs/`, de-dup.
- **Comparison:** `unplanned = changed ∖ declared`; `untouched = declared ∖ changed`. Paths sorted ascending (byte order).
- **Output:** header `ss-drift: plan vs build`, 54-dash separator, info block (`plan:`=basename, `base:`, counts line `declared: N   changed: N   unplanned: N   untouched: N`), separator, then (only if non-empty) the unplanned `  + path` section and the untouched `  - path` section, then `verdict: DRIFT|CLEAN` as the last line. Labels left-padded to 9 (`%-9s` / `{0,-9}`); 3 spaces between count fields; no pluralization.
- Commits: conventional-commit, no AI attribution. Ships next release (`[Unreleased]`); skills → 26.

Reference siblings: `scripts/ss-doctor` (style, 54-dash sep, exit codes, the `$PSNativeCommandUseErrorActionPreference=$false` git guard), `tests/doctor.test.sh` (harness). Spec: `docs/specs/2026-06-24-ss-drift-design.md`.

---

## File Structure

- `scripts/ss-drift` — bash (Task 1)
- `scripts/ss-drift.ps1` — PowerShell twin (Task 2)
- `tests/drift.test.sh` — behavior tests (Task 1) + parity test (Task 2)
- `tests/run.sh` — wire `[11/11]`, bump `[N/10]`→`[N/11]` (Task 1)
- `skills/drift/SKILL.md` — the skill (Task 3)
- `README.md`, `CHANGELOG.md` — surface it (Task 4)

---

## Task 1: `scripts/ss-drift` (bash) + tests + run.sh wiring

**Model:** sonnet.

**Files:**
- Create: `scripts/ss-drift`
- Create: `tests/drift.test.sh`
- Modify: `tests/run.sh`

**Interfaces:**
- Produces: `scripts/ss-drift <plan-file> [base]` printing the drift report + exit 0/1/2.
- Consumes: `git`, `awk`, `comm`.

- [ ] **Step 1: Write the failing tests** — create `tests/drift.test.sh`

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavior + parity tests for scripts/ss-drift.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }

# mkbase: a git repo with a plan (declaring scripts/a, scripts/b, tests/c) committed. Echoes the dir.
mkbase() {
  local t; t="$(mktemp -d)"
  ( cd "$t" && git init -q . && git config user.email t@t && git config user.name t
    mkdir -p docs/specs
    cat > docs/specs/p-plan.md <<'PLAN'
# P Plan
### Task 1: X
**Files:**
- Create: `scripts/a`
- Create: `scripts/b`
- Modify: `tests/c:10-20` (with annotation)

**Interfaces:**
- Consumes: `scripts/ignore-me`
PLAN
    git add -A && git commit -qm base )
  printf '%s' "$t"
}

# --- drift detected ---
T="$(mkbase)"; base="$(cd "$T" && git rev-parse HEAD)"
( cd "$T" && mkdir -p scripts tests && printf 'a\n'>scripts/a; printf 'b\n'>scripts/b; printf 'd\n'>scripts/d && git add -A && git commit -qm work )
out="$(cd "$T" && bash "$ROOT/scripts/ss-drift" docs/specs/p-plan.md "$base")"; rc=$?
chk "drift counts"        'printf "%s" "$out" | grep -qE "declared: 3   changed: 3   unplanned: 1   untouched: 1"'
chk "drift unplanned d"   'printf "%s" "$out" | grep -qF "  + scripts/d"'
chk "drift untouched c"   'printf "%s" "$out" | grep -qF "  - tests/c"'    # also proves :10-20 + annotation stripped
chk "interfaces ignored"  '! printf "%s" "$out" | grep -qF "scripts/ignore-me"'
chk "drift verdict"       'printf "%s" "$out" | grep -qF "verdict: DRIFT"'
chk "drift exit 1"        '[ "$rc" -eq 1 ]'

# --- clean: HEAD changes exactly the declared set ---
T2="$(mkbase)"; base2="$(cd "$T2" && git rev-parse HEAD)"
( cd "$T2" && mkdir -p scripts tests && printf 'a\n'>scripts/a; printf 'b\n'>scripts/b; printf 'c\n'>tests/c && git add -A && git commit -qm work )
out2="$(cd "$T2" && bash "$ROOT/scripts/ss-drift" docs/specs/p-plan.md "$base2")"; rc2=$?
chk "clean counts"   'printf "%s" "$out2" | grep -qE "declared: 3   changed: 3   unplanned: 0   untouched: 0"'
chk "clean verdict"  'printf "%s" "$out2" | grep -qF "verdict: CLEAN"'
chk "clean exit 0"   '[ "$rc2" -eq 0 ]'
chk "clean no lists" '! printf "%s" "$out2" | grep -qF "unplanned changes"'

# --- docs/specs excluded + uncommitted unplanned counted ---
T3="$(mkbase)"; base3="$(cd "$T3" && git rev-parse HEAD)"
( cd "$T3" && mkdir -p scripts && printf 'a\n'>scripts/a && git add -A && git commit -qm work
  printf '\n<!-- edit -->\n' >> docs/specs/p-plan.md
  printf 'x\n' > scripts/uncommitted-extra )
out3="$(cd "$T3" && bash "$ROOT/scripts/ss-drift" docs/specs/p-plan.md "$base3")"
chk "docs/specs excluded"      '! printf "%s" "$out3" | grep -qF "docs/specs/p-plan.md"'
chk "uncommitted unplanned"    'printf "%s" "$out3" | grep -qF "  + scripts/uncommitted-extra"'

# --- bad inputs -> exit 2 ---
T4="$(mkbase)"
( cd "$T4" && bash "$ROOT/scripts/ss-drift" docs/specs/NOPE.md ) >/dev/null 2>&1; rc4=$?
chk "missing plan exit 2" '[ "$rc4" -eq 2 ]'
( cd "$T4" && bash "$ROOT/scripts/ss-drift" docs/specs/p-plan.md no-such-ref ) >/dev/null 2>&1; rc4b=$?
chk "bad base exit 2" '[ "$rc4b" -eq 2 ]'
T4c="$(mktemp -d)"; printf '**Files:**\n- Create: `x`\n' > "$T4c/p.md"
( cd "$T4c" && bash "$ROOT/scripts/ss-drift" p.md ) >/dev/null 2>&1; rc4c=$?
chk "not-a-git exit 2" '[ "$rc4c" -eq 2 ]'

echo
[ "$fail" -eq 0 ] && echo "DRIFT TESTS PASS" || echo "DRIFT TESTS FAILED"
exit "$fail"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/drift.test.sh`
Expected: FAIL — `scripts/ss-drift` does not exist yet.

- [ ] **Step 3: Write `scripts/ss-drift`**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Detect drift between a plan's declared files and the branch's actual changes (read-only).
# Usage: ss-drift <plan-file> [base]    Exit: 0 clean, 1 drift, 2 usage/precondition.
set -uo pipefail
export LC_ALL=C   # byte-order sort; the ps1 twin uses [StringComparer]::Ordinal to match

plan=""; base="main"; argn=0
for a in "$@"; do
  case "$a" in
    -*) echo "ss-drift: unknown flag '$a' (usage: ss-drift <plan-file> [base])" >&2; exit 2;;
    *) argn=$((argn+1))
       case "$argn" in
         1) plan="$a";;
         2) base="$a";;
         *) echo "ss-drift: too many arguments (usage: ss-drift <plan-file> [base])" >&2; exit 2;;
       esac;;
  esac
done
[ -n "$plan" ] || { echo "ss-drift: missing plan file (usage: ss-drift <plan-file> [base])" >&2; exit 2; }
[ -f "$plan" ] || { echo "ss-drift: plan file not found: $plan" >&2; exit 2; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ss-drift: not a git repository" >&2; exit 2; }
git rev-parse --verify --quiet "$base" >/dev/null 2>&1 || { echo "ss-drift: base ref not found: $base" >&2; exit 2; }

tmpd="$(mktemp -d)"; trap 'rm -rf "$tmpd"' EXIT

# declared set: first backtick token from Create/Modify/Test bullets inside **Files:** blocks
awk '
  /^\*\*Files:\*\*/ { infiles=1; next }
  infiles && /^[[:space:]]*$/ { infiles=0; next }
  infiles && /^(\*\*|### |- \[ \])/ { infiles=0 }
  infiles && /^- (Create|Modify|Test):/ {
    if (match($0, /`[^`]+`/)) {
      p = substr($0, RSTART+1, RLENGTH-2)
      sub(/:[0-9]+(-[0-9]+)?$/, "", p)
      print p
    }
  }
' "$plan" | grep . | sort -u > "$tmpd/declared"

# changed set: committed (base...HEAD) + uncommitted, drop blanks, exclude docs/specs/
{ git diff --name-only "$base"...HEAD; git diff --name-only HEAD; } 2>/dev/null \
  | grep . | grep -v '^docs/specs/' | sort -u > "$tmpd/changed"

unplanned="$(comm -13 "$tmpd/declared" "$tmpd/changed")"
untouched="$(comm -23 "$tmpd/declared" "$tmpd/changed")"
dcount="$(wc -l < "$tmpd/declared" | tr -d ' ')"
ccount="$(wc -l < "$tmpd/changed" | tr -d ' ')"
ucount=0; [ -n "$unplanned" ] && ucount="$(printf '%s\n' "$unplanned" | wc -l | tr -d ' ')"
tcount=0; [ -n "$untouched" ] && tcount="$(printf '%s\n' "$untouched" | wc -l | tr -d ' ')"

SEP="$(printf -- '-%.0s' {1..54})"
printf 'ss-drift: plan vs build\n'
printf '%s\n' "$SEP"
printf '%-9s %s\n' 'plan:' "$(basename "$plan")"
printf '%-9s %s\n' 'base:' "$base"
printf 'declared: %d   changed: %d   unplanned: %d   untouched: %d\n' "$dcount" "$ccount" "$ucount" "$tcount"
printf '%s\n' "$SEP"
if [ "$ucount" -gt 0 ]; then
  printf 'unplanned changes (not in the plan):\n'
  printf '%s\n' "$unplanned" | sed 's/^/  + /'
fi
if [ "$tcount" -gt 0 ]; then
  printf 'planned but untouched (not yet built / over-declared):\n'
  printf '%s\n' "$untouched" | sed 's/^/  - /'
fi
verdict=CLEAN; [ "$ucount" -gt 0 ] && verdict=DRIFT
printf 'verdict: %s\n' "$verdict"
[ "$ucount" -gt 0 ] && exit 1
exit 0
```

- [ ] **Step 4: Make it executable and run the tests**

Run: `chmod +x scripts/ss-drift && bash tests/drift.test.sh`
Expected: `DRIFT TESTS PASS`. If `drift counts` fails, check the awk Files-block scoping (the `**Interfaces:**` path must not leak); if `docs/specs excluded` fails, check the `grep -v '^docs/specs/'`.

- [ ] **Step 5: Wire the suite into `tests/run.sh`**

In `tests/run.sh`: change the ten labels `[1/10]`…`[10/10]` to `[1/11]`…`[10/11]`. Then insert after the `[10/11] doctor behavior` block (after its closing `fi`, before the final summary `echo`):

```bash
echo "[11/11] drift behavior"
if bash "$ROOT/tests/drift.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - drift suite"; fail=1
fi
```

- [ ] **Step 6: Run the full suite + lint**

Run: `bash tests/run.sh && bash scripts/lint-skills.sh .`
Expected: `[1/11]`…`[11/11]` PASS, `ALL TESTS PASS`; lint clean. (Full suite is slow — pwsh parity across suites; allow a longer timeout. A `[1/11]` JSON-lint failure in a sandbox is a known jq false alarm — `bash tests/drift.test.sh` + `lint-skills.sh .` are the real checks.)

- [ ] **Step 7: Commit**

```bash
git add scripts/ss-drift tests/drift.test.sh tests/run.sh
git commit -m "feat(drift): add ss-drift plan-vs-build drift detection (bash)"
```

---

## Task 2: `scripts/ss-drift.ps1` (PowerShell twin) + parity test

**Model:** sonnet.

**Files:**
- Create: `scripts/ss-drift.ps1`
- Modify: `tests/drift.test.sh` (append a parity block before the summary)

**Interfaces:**
- Consumes: the bash `scripts/ss-drift` behavior + output from Task 1 (must match byte-for-byte).
- Produces: `scripts/ss-drift.ps1 <plan-file> [base]` with byte-identical stdout + exit 0/1/2.

- [ ] **Step 1: Append the failing parity test** to `tests/drift.test.sh`, immediately before the final `echo`/summary. The fixture puts TWO unplanned files (`README-extra`, `scripts/d`) so the parity test exercises multi-item byte-order sorting:

```bash
# parity: read-only, so compare a real run on a drift fixture with multi-item lists
if command -v pwsh >/dev/null 2>&1; then
  if command -v cygpath >/dev/null 2>&1; then ps1arg="$(cygpath -w "$ROOT/scripts/ss-drift.ps1")"; else ps1arg="$ROOT/scripts/ss-drift.ps1"; fi
  T5="$(mkbase)"; base5="$(cd "$T5" && git rev-parse HEAD)"
  ( cd "$T5" && mkdir -p scripts tests && printf 'a\n'>scripts/a; printf 'b\n'>scripts/b; printf 'd\n'>scripts/d; printf 'r\n'>README-extra && git add -A && git commit -qm work )
  pb="$(cd "$T5" && bash "$ROOT/scripts/ss-drift" docs/specs/p-plan.md "$base5")"
  pp="$(cd "$T5" && pwsh -NoProfile -File "$ps1arg" docs/specs/p-plan.md "$base5" | tr -d '\r')"
  chk "ps1 parity (drift)" '[ "$pb" = "$pp" ]'
else
  echo "  SKIP ps1 parity (pwsh not installed)"
fi
```

- [ ] **Step 2: Run the tests to confirm the parity check fails**

Run: `bash tests/drift.test.sh`
Expected: behavior checks PASS; `ps1 parity (drift)` FAIL (ps1 missing) — or SKIP if no `pwsh`.

- [ ] **Step 3: Write `scripts/ss-drift.ps1`**

```powershell
#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Detect drift between a plan's declared files and the branch's actual changes (read-only).
# Usage: ss-drift.ps1 <plan-file> [base]    Exit: 0 clean, 1 drift, 2 usage/precondition.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false  # git non-zero exits must not throw

$pos = @()
foreach ($a in $args) {
  if ($a -like '-*') { [Console]::Error.WriteLine("ss-drift: unknown flag '$a' (usage: ss-drift <plan-file> [base])"); exit 2 }
  $pos += $a
}
if ($pos.Count -lt 1) { [Console]::Error.WriteLine("ss-drift: missing plan file (usage: ss-drift <plan-file> [base])"); exit 2 }
if ($pos.Count -gt 2) { [Console]::Error.WriteLine("ss-drift: too many arguments (usage: ss-drift <plan-file> [base])"); exit 2 }
$plan = $pos[0]
$base = if ($pos.Count -ge 2) { $pos[1] } else { 'main' }
if (-not (Test-Path -LiteralPath $plan -PathType Leaf)) { [Console]::Error.WriteLine("ss-drift: plan file not found: $plan"); exit 2 }
$null = (git rev-parse --is-inside-work-tree 2>$null); if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine("ss-drift: not a git repository"); exit 2 }
$null = (git rev-parse --verify --quiet $base 2>$null); if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine("ss-drift: base ref not found: $base"); exit 2 }

# declared set
$declared = [System.Collections.Generic.HashSet[string]]::new()
$inFiles = $false
foreach ($line in (Get-Content -LiteralPath $plan)) {
  $line = $line.TrimEnd("`r")
  if ($line -match '^\*\*Files:\*\*') { $inFiles = $true; continue }
  if ($inFiles -and $line -match '^\s*$') { $inFiles = $false; continue }
  if ($inFiles -and ($line -match '^(\*\*|### |- \[ \])')) { $inFiles = $false }
  if ($inFiles -and ($line -match '^- (Create|Modify|Test):')) {
    if ($line -match '`([^`]+)`') {
      $p = $Matches[1] -replace ':[0-9]+(-[0-9]+)?$', ''
      [void]$declared.Add($p)
    }
  }
}

# changed set
$changed = [System.Collections.Generic.HashSet[string]]::new()
$raw = @()
$raw += (git diff --name-only "$base...HEAD" 2>$null)
$raw += (git diff --name-only HEAD 2>$null)
foreach ($f in $raw) {
  if ([string]::IsNullOrWhiteSpace($f)) { continue }
  $f = $f.Trim()
  if ($f -like 'docs/specs/*') { continue }
  [void]$changed.Add($f)
}

# set differences, byte-order (Ordinal) sorted to match bash LC_ALL=C
$unplanned = [string[]]@($changed | Where-Object { -not $declared.Contains($_) })
$untouched = [string[]]@($declared | Where-Object { -not $changed.Contains($_) })
[Array]::Sort($unplanned, [System.StringComparer]::Ordinal)
[Array]::Sort($untouched, [System.StringComparer]::Ordinal)
$dcount = $declared.Count; $ccount = $changed.Count; $ucount = $unplanned.Count; $tcount = $untouched.Count

$lines = @('ss-drift: plan vs build', ('-' * 54))
$lines += ('{0,-9} {1}' -f 'plan:', (Split-Path -Leaf $plan))
$lines += ('{0,-9} {1}' -f 'base:', $base)
$lines += ('declared: {0}   changed: {1}   unplanned: {2}   untouched: {3}' -f $dcount, $ccount, $ucount, $tcount)
$lines += ('-' * 54)
if ($ucount -gt 0) {
  $lines += 'unplanned changes (not in the plan):'
  foreach ($p in $unplanned) { $lines += "  + $p" }
}
if ($tcount -gt 0) {
  $lines += 'planned but untouched (not yet built / over-declared):'
  foreach ($p in $untouched) { $lines += "  - $p" }
}
$verdict = if ($ucount -gt 0) { 'DRIFT' } else { 'CLEAN' }
$lines += "verdict: $verdict"
Write-Output ($lines -join "`n")
if ($ucount -gt 0) { exit 1 }
exit 0
```

Parity notes for the implementer:
- `'{0,-9} {1}'` mirrors bash `printf '%-9s %s'`; `('-' * 54)` mirrors `printf -- '-%.0s' {1..54}`; counts line and section headers/prefixes (`  + `, `  - `) match the bash strings exactly.
- **Sort order is the #1 parity risk.** bash uses `LC_ALL=C` (byte order); the ps1 MUST use `[System.StringComparer]::Ordinal` (NOT default `Sort-Object`, which is culture-aware). The parity fixture has `README-extra` + `scripts/d` precisely to catch this — byte order puts `README-extra` first (`R`=0x52 < `s`=0x73); culture order may not.
- `$PSNativeCommandUseErrorActionPreference = $false` is required so the `git rev-parse` precondition checks (which exit non-zero on a bad ref / non-repo) return an exit code instead of throwing.
- `git diff --name-only "$base...HEAD"` passes the range as one arg (e.g. `main...HEAD`).

- [ ] **Step 4: Run the tests to verify parity passes**

Run: `bash tests/drift.test.sh`
Expected: all PASS including `ps1 parity (drift)` (or SKIP if no `pwsh`) → `DRIFT TESTS PASS`. If parity fails, run both twins on the same fixture and `diff` them; the most likely cause is sort order (verify Ordinal vs LC_ALL=C).

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh`
Expected: `[1/11]`…`[11/11]` PASS, `ALL TESTS PASS`.

- [ ] **Step 6: Commit**

```bash
git add scripts/ss-drift.ps1 tests/drift.test.sh
git commit -m "feat(drift): PowerShell parity for ss-drift"
```

---

## Task 3: `skills/drift/SKILL.md`

**Model:** haiku (pure markdown).

**Files:**
- Create: `skills/drift/SKILL.md`

**Interfaces:** documents Task 1–2 behavior; nothing depends on it.

- [ ] **Step 1: Write the skill**

```markdown
---
name: ss-drift
description: Use during Review or Ship to confirm the build stayed within its approved plan - it compares the plan's declared files against what the branch actually changed and reports unplanned changes (scope creep) and planned-but-untouched files. Read-only; exits non-zero on drift for CI.
---

# Drift - did the build match the plan?

Read-only check. Point it at the plan you executed; it compares the files the plan declared against
what the branch actually changed (vs a base, default `main`) and reports the divergence both ways.

## Steps

1. Run `scripts/ss-drift <plan-file> [base]` (PowerShell: `scripts/ss-drift.ps1 <plan-file> [base]`).
   `base` defaults to `main`; pass it explicitly if the branch forked from elsewhere.
2. Read the report:
   - **unplanned changes** (`+`) - files the branch changed that the plan never named. This is the
     scope-creep signal; either fold them into the plan or revert them.
   - **planned but untouched** (`-`) - declared files the branch hasn't changed yet (incomplete, or
     the plan over-declared). Advisory - a mid-build branch legitimately has these.
3. Act on the verdict: `CLEAN` (exit 0) or `DRIFT` (exit 1 - safe to use as a Review/Ship/CI gate).

## Note

`/ss-drift` is read-only and file-scoped: it reasons about the plan's `**Files:**` blocks vs `git diff`,
ignores `docs/specs/` (the plan/spec docs themselves), and does not check phase order (the loop allows
legitimate re-entry). It is the build-vs-plan companion to [[ss-audit]]'s phase-gate proof.

## Lineage

Original to SuperStack - drift detection (desired-vs-actual, after Terraform's model) applied to
"did the implementation stay within the approved plan."
```

- [ ] **Step 2: Verify it lints**

Run: `bash scripts/lint-skills.sh .`
Expected: PASS — reports 26 skills; `[[ss-audit]]` resolves (the `ss-audit` skill exists). Name `ss-drift`, description 40–500 chars, exactly one H1.

- [ ] **Step 3: Commit**

```bash
git add skills/drift/SKILL.md
git commit -m "docs(drift): add /ss-drift skill"
```

---

## Task 4: README + CHANGELOG

**Model:** haiku (pure markdown).

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update the CHANGELOG**

Read `CHANGELOG.md`. Under the top `## [Unreleased]` heading's `### Added` group (create it if absent), add:

```markdown
- **`/ss-drift`:** read-only plan-vs-build drift detection — compares a plan's declared `**Files:**`
  against what the branch actually changed (`base...HEAD` + working tree), reporting unplanned changes
  (scope creep) and planned-but-untouched files; exits 1 on drift for CI. bash + PowerShell. (26 skills.)
```

Do NOT rename `[Unreleased]`. Don't disturb existing entries.

- [ ] **Step 2: Surface it in the README**

Read `README.md`. Two surgical edits:
1. Add `/ss-drift` to the **Supporting skills** inline list (the line with `/ss-init` `/ss-doctor` … `run /ss-help`), right after `/ss-doctor`. (Inline list only — do NOT add a standalone table.)
2. Bump the skills count: first GREP for the current count (badge `skills-25` and `**25 skills, ...**` prose); change **25 → 26** in both. If you find a different number, bump that actual number by one and note the discrepancy in your report.

Match surrounding style; don't restructure.

- [ ] **Step 3: Verify nothing regressed**

Run: `bash scripts/lint-skills.sh .`
Expected: clean, 26 skills. (Authoritative quick check for a docs-only change; `tests/run.sh` is slow.)

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: surface /ss-drift in README + CHANGELOG"
```

---

## Self-Review (completed by plan author)

- **Spec coverage:** CLI + exit 2 preconditions (T1) · declared-set parse incl. Files-block scoping, first-backtick, `:line-range` strip (T1 + test) · changed-set incl. docs/specs exclusion + uncommitted (T1 + tests) · bidirectional compare + counts + verdict (T1) · exit 0/1 (T1) · output format/sep/footer (T1, spec §6) · byte-identical twins + LC_ALL=C↔Ordinal + `$PSNativeCommandUseErrorActionPreference` (T2) · read-only multi-item parity (T2) · tests→`run.sh [11/11]` (T1–T2) · skill (T3) · README 26 + CHANGELOG (T4). All spec sections map to a task.
- **Placeholder scan:** none — every code/test/doc block is complete.
- **Type/name consistency:** the verdict tokens `DRIFT`/`CLEAN`, the `unplanned`/`untouched` naming, the `%-9s`≡`{0,-9}` and 54-dash formats, the `  + `/`  - ` prefixes, the `docs/specs/` exclusion, the awk Files-block regexes ≡ the ps1 `-match` regexes, and the LC_ALL=C↔Ordinal sort pairing are identical across bash, PowerShell, and the tests.

---

## Execution Handoff

Recommended: **subagent-driven** — Task 1 (bash) and Task 2 (PowerShell parity) on sonnet, Tasks 3–4 (markdown) on haiku; per-task spec+quality review, opus whole-branch review at the end.
