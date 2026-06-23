# Shareable Run Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/ss-report` — a `scripts/ss-report` (+ `.ps1`) and skill that read the Loop Ledger + git and print a copy-pasteable Markdown summary of how a change was built.

**Architecture:** A read-only reporter. It derives facts from `.superstack/ledger.jsonl` (phases run/skipped, skip reasons, `note` events, first→last `ts` = elapsed) and from `git` (`merge-base..HEAD` commits/files/+−/test-files), reuses `ss-audit --attest` for the process line, and renders an ASCII Markdown block. A PowerShell twin mirrors it byte-for-byte (except the best-effort elapsed line).

**Tech Stack:** POSIX bash, PowerShell, `jq`, git. No new dependencies.

## Global Constraints

- Cross-platform: `scripts/ss-report` (bash) and `scripts/ss-report.ps1` produce **identical** ledger-derived output (heading, attestation, Phases/Skipped/Notes, git `Change:` bullet).
- **ASCII-only output.** No emoji, em-dash, middle-dot, or Unicode minus — use `-`, `,`, and a plain `:` heading. This guarantees byte-parity across the twins (same lesson as the ledger attestation). It refines the spec's *illustrative* example block while satisfying its binding parity requirement.
- Scripts begin with the shebang (`#!/usr/bin/env bash` / `#!/usr/bin/env pwsh`) then `# SPDX-License-Identifier: MIT`.
- Ledger dir overridable via `SUPERSTACK_DIR` (default `.superstack`).
- `ss-report` never gates: exit 0 except on an unknown-flag usage error (exit 1).
- The attestation line is accepted only if it begins with `SuperStack process:` (so `ss-audit`'s "no ledger" stdout message is never mistaken for an attestation).
- Skill names start `ss-` (or `superstack`); description starts `Use `, 40–500 chars; one H1. Conventional commits. Record the bash exec bit via `git update-index --chmod=+x`.
- `bash scripts/lint-skills.sh` (→ `OK: 21 skill(s)`) and `bash tests/run.sh` (→ `ALL TESTS PASS`) must stay green.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `scripts/ss-report` | bash: derive facts from ledger + git, render the ASCII block, `--save` to file |
| `scripts/ss-report.ps1` | PowerShell twin (identical block) |
| `skills/report/SKILL.md` | the `/ss-report` skill (21st) |
| `tests/report.test.sh` | behavior + parity suite (own temp git repo + seeded ledger) |
| `skills/ship/SKILL.md` | one added note: optionally run `/ss-report` |
| `tests/run.sh` | add `[5/5]` invoking `tests/report.test.sh`; renumber `[1/4]..[4/4]`→`[1/5]..[4/5]` |
| `docs/ledger.md`, `CHANGELOG.md` | document the report |

---

### Task 1: `scripts/ss-report` (bash) + behavior tests

**Files:**
- Create: `scripts/ss-report`, `tests/report.test.sh`

**Interfaces:**
- Produces: `ss-report [change] [--save]` → prints the Markdown block to stdout; `--save` also writes `${SUPERSTACK_DIR:-.superstack}/run-report-<change>.md` (`/`→`-`). Reads `${SUPERSTACK_DIR:-.superstack}/ledger.jsonl` and `git`. Exit 0 normally; 1 on unknown flag.

- [ ] **Step 1: Write the failing test**

Create `tests/report.test.sh`:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavior + parity tests for scripts/ss-report.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; export SUPERSTACK_DIR="$TMP/.superstack"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }

# temp git repo: commit 1 on main (app.sh), commit 2 on feat/x (app.test.sh)
cd "$TMP"
git init -q .
git config user.email t@t; git config user.name t
git checkout -q -b main 2>/dev/null || git branch -m main
printf 'hello\n' > app.sh; git add app.sh; git commit -q -m "init"
git checkout -q -b feat/x
printf 'x\n' > app.test.sh; git add app.test.sh; git commit -q -m "add test"

# seed the ledger for change feat/x (ledger resolves change from the branch)
bash "$ROOT/scripts/ledger" frame  gate pass >/dev/null
bash "$ROOT/scripts/ledger" plan   gate pass >/dev/null
bash "$ROOT/scripts/ledger" build  gate pass >/dev/null
bash "$ROOT/scripts/ledger" review gate pass >/dev/null
bash "$ROOT/scripts/ledger" secure skip skip "no IO" >/dev/null

rep="$(bash "$ROOT/scripts/ss-report")"
chk "heading"  'printf "%s" "$rep" | grep -q "### SuperStack run: feat/x"'
chk "attest"   'printf "%s" "$rep" | grep -q "SuperStack process:"'
chk "phases"   'printf "%s" "$rep" | grep -q "Phases: 4 run, 1 skipped"'
chk "skipped"  'printf "%s" "$rep" | grep -q "Skipped: secure (no IO)"'
chk "change"   'printf "%s" "$rep" | grep -qE "Change: 1 commits, 1 files"'
chk "tests"    'printf "%s" "$rep" | grep -q "1 test files touched"'
chk "save"     'bash "$ROOT/scripts/ss-report" --save >/dev/null 2>&1; [ -f "$SUPERSTACK_DIR/run-report-feat-x.md" ]'
chk "badflag"  '! bash "$ROOT/scripts/ss-report" --nope >/dev/null 2>&1'
chk "empty"    'rm -f "$SUPERSTACK_DIR/ledger.jsonl"; bash "$ROOT/scripts/ss-report" | grep -q "Phases: 0 run, 0 skipped"'

echo
[ "$fail" -eq 0 ] && echo "REPORT TESTS PASS" || echo "REPORT TESTS FAILED"
exit "$fail"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/report.test.sh`
Expected: FAIL — `scripts/ss-report` does not exist; `REPORT TESTS FAILED`.

- [ ] **Step 3: Write minimal implementation**

Create `scripts/ss-report`:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Shareable Markdown summary of how a change was built (Loop Ledger + git).
# Usage: ss-report [change] [--save]
set -uo pipefail
dir="${SUPERSTACK_DIR:-.superstack}"
ledger="$dir/ledger.jsonl"
save=0; change=""
for a in "$@"; do
  case "$a" in
    --save) save=1;;
    -*) echo "ss-report: unknown flag '$a' (usage: ss-report [change] [--save])" >&2; exit 1;;
    *) change="$a";;
  esac
done
[ -n "$change" ] || change="$(git branch --show-current 2>/dev/null || echo default)"
[ -n "$change" ] || change="default"

run=0; skipped=0; skips=""; notes=""; first_ts=""; last_ts=""
if command -v jq >/dev/null 2>&1 && [ -f "$ledger" ]; then
  facts="$(jq -rn --arg c "$change" '
    [inputs|select(.change==$c)] as $e
    | ([$e[]|select(.event=="gate")|.phase]|unique|length),
      ([$e[]|select(.event=="skip")|.phase]|unique|length),
      ([$e[]|select(.event=="skip")|"\(.phase) (\(.note))"]|join(", ")),
      ([$e[]|select(.event=="note")|"\(.phase): \(.note)"]|join(", ")),
      ([$e[]|.ts]|sort|first // ""),
      ([$e[]|.ts]|sort|last // "")
  ' "$ledger")"
  { read -r run; read -r skipped; read -r skips; read -r notes; read -r first_ts; read -r last_ts; } <<EOF
$facts
EOF
fi

elapsed=""
if [ -n "$first_ts" ] && [ -n "$last_ts" ] && [ "$first_ts" != "$last_ts" ]; then
  fs="$(date -u -d "$first_ts" +%s 2>/dev/null || echo "")"
  le="$(date -u -d "$last_ts" +%s 2>/dev/null || echo "")"
  if [ -n "$fs" ] && [ -n "$le" ] && [ "$le" -ge "$fs" ]; then
    secs=$((le - fs)); h=$((secs / 3600)); m=$(((secs % 3600) / 60))
    if [ "$h" -gt 0 ]; then elapsed="${h}h ${m}m"; else elapsed="${m}m"; fi
  fi
fi

att=""
audit="$(cd "$(dirname "$0")" && pwd)/ss-audit"
if [ -f "$audit" ]; then
  raw="$(bash "$audit" --attest 2>/dev/null || true)"
  case "$raw" in "SuperStack process:"*) att="$raw";; esac
fi

git_line=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  mb="$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null || true)"
  if [ -n "$mb" ]; then
    commits="$(git rev-list --count "$mb"..HEAD 2>/dev/null || echo 0)"
    ss="$(git diff --shortstat "$mb"..HEAD 2>/dev/null || true)"
    files="$(printf '%s' "$ss" | grep -oE '[0-9]+ files? changed' | grep -oE '[0-9]+' || true)"
    ins="$(printf '%s' "$ss" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || true)"
    del="$(printf '%s' "$ss" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || true)"
    tests="$(git diff --name-only "$mb"..HEAD 2>/dev/null | grep -Ec '(^|/)(tests?|spec|__tests__)/|\.(test|spec)\.' || true)"
    : "${files:=0}"; : "${ins:=0}"; : "${del:=0}"; : "${tests:=0}"
    git_line="- Change: ${commits} commits, ${files} files, +${ins} / -${del}, ${tests} test files touched"
  fi
fi

render() {
  printf '### SuperStack run: %s\n' "$change"
  if [ -n "$elapsed" ]; then printf 'Built through the loop in %s.\n' "$elapsed"; else printf 'Built through the loop.\n'; fi
  printf '\n'
  [ -n "$att" ] && printf '`%s`\n\n' "$att"
  printf -- '- Phases: %s run, %s skipped\n' "$run" "$skipped"
  [ -n "$git_line" ] && printf '%s\n' "$git_line"
  [ -n "$skips" ] && printf -- '- Skipped: %s\n' "$skips"
  [ -n "$notes" ] && printf -- '- Notes: %s\n' "$notes"
}
output="$(render)"
printf '%s\n' "$output"
if [ "$save" -eq 1 ]; then
  mkdir -p "$dir"
  printf '%s\n' "$output" > "$dir/run-report-${change//\//-}.md"
  echo "saved: $dir/run-report-${change//\//-}.md" >&2
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x scripts/ss-report && bash tests/report.test.sh`
Expected: all `PASS`, `REPORT TESTS PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/ss-report tests/report.test.sh
git update-index --chmod=+x scripts/ss-report tests/report.test.sh
git commit -m "feat(report): add ss-report — shareable run summary from the ledger + git"
```

---

### Task 2: `/ss-report` skill

**Files:**
- Create: `skills/report/SKILL.md`

- [ ] **Step 1: Verify current skill count (the "red")**

Run: `bash scripts/lint-skills.sh`
Expected: `OK: 20 skill(s), agents, and manifests valid` (the new skill not yet present).

- [ ] **Step 2: Write the skill**

Create `skills/report/SKILL.md`:

```markdown
---
name: ss-report
description: Use after shipping (or any time) to generate a shareable Markdown summary of how a change was built — phases run, skip reasons, timing, and change size — from the loop ledger and git.
---

# Report — shareable proof of work

Turns the loop ledger into a copy-pasteable summary you can drop in a PR, a changelog, or a post.

## Steps

1. Run `scripts/ss-report` (optionally pass a branch name, or `--save` to also write
   `.superstack/run-report-<change>.md`). It reads the ledger for the current change plus git
   diff stats and prints a Markdown block.
2. Paste the block where it's useful — the PR description, release notes, or a status update.
   It pairs naturally with the `/ss-ship` attestation.

## Note

The report never gates anything; it's read-only. With no ledger yet, it still reports the git
change size and an empty phase line — it degrades gracefully.

## Lineage

Original to SuperStack — powered by the Loop Ledger ([[ss-audit]]).
```

- [ ] **Step 3: Run the linter to verify it passes**

Run: `bash scripts/lint-skills.sh`
Expected: `OK: 21 skill(s), agents, and manifests valid`.

- [ ] **Step 4: Commit**

```bash
git add skills/report/SKILL.md
git commit -m "feat(report): add /ss-report skill"
```

---

### Task 3: `scripts/ss-report.ps1` (PowerShell twin) + parity test

**Files:**
- Create: `scripts/ss-report.ps1`
- Modify: `tests/report.test.sh` (append a parity assertion)

**Interfaces:**
- Produces: `ss-report.ps1 [change] [-Save]` — same behavior and identical ledger-derived block as the bash twin.

- [ ] **Step 1: Write the failing test**

Append to `tests/report.test.sh`, immediately BEFORE the final `echo`:

```bash
# re-seed the ledger (the "empty" test above removed it), then check bash<->ps1 parity
bash "$ROOT/scripts/ledger" frame  gate pass >/dev/null
bash "$ROOT/scripts/ledger" plan   gate pass >/dev/null
bash "$ROOT/scripts/ledger" build  gate pass >/dev/null
bash "$ROOT/scripts/ledger" review gate pass >/dev/null
bash "$ROOT/scripts/ledger" secure skip skip "no IO" >/dev/null
pb="$(bash "$ROOT/scripts/ss-report" | grep -vE '^Built through the loop')"
pp="$(pwsh -NoProfile -File "$ROOT/scripts/ss-report.ps1" | tr -d '\r' | grep -vE '^Built through the loop')"
chk "ps1 parity" '[ "$pb" = "$pp" ]'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/report.test.sh`
Expected: `FAIL ps1 parity` — `scripts/ss-report.ps1` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `scripts/ss-report.ps1`:

```powershell
#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Shareable Markdown summary of how a change was built. Usage: ss-report.ps1 [change] [-Save]
param([string]$Change = "", [switch]$Save)
$ErrorActionPreference = 'Stop'
$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
$ledger = Join-Path $dir 'ledger.jsonl'
if (-not $Change) { $Change = "$(git branch --show-current 2>$null)".Trim() }
if (-not $Change) { $Change = 'default' }

$run = 0; $skipped = 0; $skips = ''; $notes = ''; $first = $null; $last = $null
if (Test-Path $ledger) {
  $e = @(Get-Content $ledger | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.change -eq $Change })
  $run = @($e | Where-Object { $_.event -eq 'gate' } | Select-Object -ExpandProperty phase -Unique).Count
  $skipE = @($e | Where-Object { $_.event -eq 'skip' })
  $skipped = @($skipE | Select-Object -ExpandProperty phase -Unique).Count
  $skips = (($skipE | ForEach-Object { "$($_.phase) ($($_.note))" }) -join ', ')
  $notes = ((@($e | Where-Object { $_.event -eq 'note' }) | ForEach-Object { "$($_.phase): $($_.note)" }) -join ', ')
  $ts = @($e | Select-Object -ExpandProperty ts | Sort-Object)
  if ($ts.Count) { $first = $ts[0]; $last = $ts[-1] }
}

$elapsed = ''
if ($first -and $last -and $first -ne $last) {
  try {
    $styles = [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal
    $span = [datetime]::Parse($last, [Globalization.CultureInfo]::InvariantCulture, $styles) -
            [datetime]::Parse($first, [Globalization.CultureInfo]::InvariantCulture, $styles)
    if ($span.TotalSeconds -ge 0) {
      $h = [int][math]::Floor($span.TotalHours); $m = $span.Minutes
      $elapsed = if ($h -gt 0) { "${h}h ${m}m" } else { "${m}m" }
    }
  } catch {}
}

$att = ''
$audit = Join-Path $PSScriptRoot 'ss-audit.ps1'
if (Test-Path $audit) {
  try {
    $raw = (& $audit -Attest) 2>$null
    if ($raw -is [array]) { $raw = $raw -join "`n" }
    if ("$raw".StartsWith('SuperStack process:')) { $att = "$raw".Trim() }
  } catch {}
}

$gitLine = ''
if ((git rev-parse --is-inside-work-tree 2>$null) -eq 'true') {
  $mb = (git merge-base HEAD main 2>$null); if (-not $mb) { $mb = (git merge-base HEAD master 2>$null) }
  if ($mb) {
    $commits = (git rev-list --count "$mb..HEAD" 2>$null)
    $short = (git diff --shortstat "$mb..HEAD" 2>$null)
    $files = if ($short -match '(\d+) files? changed') { $Matches[1] } else { '0' }
    $ins   = if ($short -match '(\d+) insertion')      { $Matches[1] } else { '0' }
    $del   = if ($short -match '(\d+) deletion')       { $Matches[1] } else { '0' }
    $names = @(git diff --name-only "$mb..HEAD" 2>$null)
    $tests = @($names | Where-Object { $_ -match '(^|/)(tests?|spec|__tests__)/|\.(test|spec)\.' }).Count
    $gitLine = "- Change: $commits commits, $files files, +$ins / -$del, $tests test files touched"
  }
}

$bt = [char]96
$lines = @("### SuperStack run: $Change")
$lines += $(if ($elapsed) { "Built through the loop in $elapsed." } else { "Built through the loop." })
$lines += ''
if ($att) { $lines += "$bt$att$bt"; $lines += '' }
$lines += "- Phases: $run run, $skipped skipped"
if ($gitLine) { $lines += $gitLine }
if ($skips)   { $lines += "- Skipped: $skips" }
if ($notes)   { $lines += "- Notes: $notes" }
$block = ($lines -join "`n")
Write-Output $block
if ($Save) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  Set-Content -Path (Join-Path $dir ("run-report-" + ($Change -replace '/', '-') + ".md")) -Value $block -Encoding utf8
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/report.test.sh`
Expected: all `PASS` including `ps1 parity`; `REPORT TESTS PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/ss-report.ps1 tests/report.test.sh
git commit -m "feat(report): PowerShell parity for ss-report"
```

---

### Task 4: Wire into CI + ship mention + docs

**Files:**
- Modify: `tests/run.sh`, `skills/ship/SKILL.md`, `docs/ledger.md`, `CHANGELOG.md`

- [ ] **Step 1: Add the report suite to the self-test**

In `tests/run.sh`: change the existing `[1/4]`..`[4/4]` labels to `[1/5]`..`[4/5]`, and before the final summary `echo` add a `[5/5]` block mirroring the `[4/4]` ledger block:

```bash
echo "[5/5] run-report behavior + parity"
if bash "$ROOT/tests/report.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - run-report suite"; fail=1
fi
```

- [ ] **Step 2: Mention `/ss-report` in the ship skill**

In `skills/ship/SKILL.md`, add this blockquote line immediately AFTER the `## Steps` list (before `## Gate`):

```markdown
> Optional: run `/ss-report` for a shareable summary of how this change was built (phases, timing, size) — paste it into the PR or share it.
```

- [ ] **Step 3: Document it in `docs/ledger.md`**

Append to `docs/ledger.md`:

```markdown

## Run report

`/ss-report` (`scripts/ss-report`, + PowerShell twin) turns the ledger into a copy-pasteable
Markdown summary — phases run, skip reasons, elapsed time, and change size (commits/files/±/test
files) — for a PR, release notes, or a status update. It's read-only and never gates; with no
ledger it still reports the git change size. `--save` writes `.superstack/run-report-<change>.md`.
```

- [ ] **Step 4: Add the CHANGELOG entry**

In `CHANGELOG.md`, under `## [Unreleased]` → add an `### Added` section (create it if absent) with:

```markdown
- **`/ss-report`:** a shareable Markdown run summary (phases, timing, change size) generated from
  the loop ledger + git; bash + PowerShell. (21 skills total.)
```

- [ ] **Step 5: Run the full gate**

Run: `bash scripts/lint-skills.sh && bash tests/run.sh`
Expected: `OK: 21 skill(s)…`; `[5/5] run-report behavior + parity PASS`; `ALL TESTS PASS`.

- [ ] **Step 6: Commit**

```bash
git add tests/run.sh skills/ship/SKILL.md docs/ledger.md CHANGELOG.md
git commit -m "feat(report): wire run-report into CI, ship, and docs"
```

---

## Self-Review

**Spec coverage:** ss-report bash (Task 1) ✓; `/ss-report` skill, count→21 (Task 2) ✓; PowerShell parity (Task 3) ✓; CI `[5/5]` + ship mention + docs + CHANGELOG (Task 4) ✓. Data sources (ledger phases/skips/notes/ts, git merge-base stats, `ss-audit --attest`) all covered in Task 1's code. Empty-ledger and unknown-flag behavior covered by tests. Non-goals (rich counts, badge, gating) respected.

**Placeholder scan:** every step has complete code/commands; no TBD/"handle edge cases".

**Type/name consistency:** `ss-report [change] [--save]` / `-Save`, the `### SuperStack run: <change>` heading, `- Phases: N run, M skipped`, `- Change: C commits, F files, +A / -D, T test files touched`, `- Skipped:`, `- Notes:`, the `(^|/)(tests?|spec|__tests__)/|\.(test|spec)\.` test-file regex, `SUPERSTACK_DIR`, and the `SuperStack process:`-prefix attestation guard are used identically across bash, PowerShell, and the tests.

**Refinement noted:** output is ASCII (no emoji/`·`/`−`) — a deliberate, transparent change from the spec's illustrative block, made to satisfy the spec's binding byte-parity requirement (same reason the ledger attestation is ASCII).
