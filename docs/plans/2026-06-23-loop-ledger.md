# Loop Ledger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give SuperStack a structured record of its loop's execution (`.superstack/ledger.jsonl`) plus an `ss-audit` gate that verifies mandatory phases ran before shipping.

**Architecture:** Phases self-report gate outcomes through a small `ledger` helper that appends JSONL. `ss-audit` reads the ledger and checks the mandatory phases for the current change. `/ss-ship` runs the audit and emits an attestation; an opt-in `PreToolUse` hook hard-blocks pushes when the process is incomplete. Every script ships bash + PowerShell.

**Tech Stack:** POSIX bash, PowerShell, `jq`, git. No new runtime dependencies.

## Global Constraints

- Cross-platform: every executable ships a bash and a PowerShell variant.
- Skill names start with `ss-` (or `superstack`); descriptions start with `Use ` and are 40–500 chars (the linter enforces this).
- Scripts begin with `#!/usr/bin/env bash` (or `pwsh`) then `# SPDX-License-Identifier: MIT`.
- Ledger location is overridable via `SUPERSTACK_DIR` (default `.superstack`) — used for isolated testing.
- The ledger is runtime state: `.superstack/` is gitignored.
- Commits are conventional (`feat:`, `docs:`, `test:`, `chore:`).
- `bash scripts/lint-skills.sh` and `bash tests/run.sh` must stay green.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `scripts/ledger` / `.ps1` | Append one validated JSONL entry |
| `scripts/ss-audit` / `.ps1` | Read ledger → verdict (exit 0 complete / 1 incomplete); `--attest` line |
| `hooks/audit-check` | Opt-in PreToolUse gate on `git push`/`gh pr create` |
| `tests/ledger.test.sh` | Behavior tests for ledger + ss-audit |
| `skills/audit/SKILL.md` | The `ss-audit` skill |
| `skills/{frame,plan,build,review,qa,secure,ship,learn}/SKILL.md` | +1 Gate line to record outcome |
| `hooks/hooks.json`, `.gitignore`, `tests/run.sh`, `CLAUDE.md`, `README.md`, `CHANGELOG.md`, `docs/ledger.md` | Wiring + docs |

---

### Task 1: `ledger` helper (bash)

**Files:**
- Create: `scripts/ledger`
- Test: `tests/ledger.test.sh`

**Interfaces:**
- Produces: `ledger <phase> <event> [status] [note]` → appends `{ts,change,phase,event,status,note}` to `${SUPERSTACK_DIR:-.superstack}/ledger.jsonl`. `event∈{enter,gate,skip,note}`, `status∈{pass,fail,skip,na}`. Exit 1 on invalid enum.

- [ ] **Step 1: Write the failing test**

Create `tests/ledger.test.sh`:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavior tests for scripts/ledger and scripts/ss-audit.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; export SUPERSTACK_DIR="$TMP/.superstack"
cd "$TMP"   # no git here -> change resolves to "default" for both scripts
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }

# ledger appends a valid entry
bash "$ROOT/scripts/ledger" review gate pass "no critical" >/dev/null
chk "ledger append" 'tail -1 "$SUPERSTACK_DIR/ledger.jsonl" | jq -e ".phase==\"review\" and .event==\"gate\" and .status==\"pass\"" >/dev/null'

# ledger rejects an invalid event
chk "ledger enum guard" '! bash "$ROOT/scripts/ledger" review bogus pass 2>/dev/null'

echo
[ "$fail" -eq 0 ] && echo "LEDGER TESTS PASS" || echo "LEDGER TESTS FAILED"
exit "$fail"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/ledger.test.sh`
Expected: FAIL — `scripts/ledger` does not exist (`No such file`), `LEDGER TESTS FAILED`.

- [ ] **Step 3: Write minimal implementation**

Create `scripts/ledger`:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Append a validated entry to the SuperStack loop ledger.
# Usage: ledger <phase> <event> [status] [note]
set -uo pipefail
dir="${SUPERSTACK_DIR:-.superstack}"
phase="${1:-}"; event="${2:-}"; status="${3:-na}"; note="${4:-}"
[ -n "$phase" ] && [ -n "$event" ] || { echo "usage: ledger <phase> <event> [status] [note]" >&2; exit 1; }
case "$event"  in enter|gate|skip|note) ;; *) echo "ledger: invalid event '$event'" >&2;  exit 1;; esac
case "$status" in pass|fail|skip|na)    ;; *) echo "ledger: invalid status '$status'" >&2; exit 1;; esac
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
change="$(git branch --show-current 2>/dev/null || true)"; [ -n "$change" ] || change="default"
esc() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\t'/ }"; s="${s//$'\n'/ }"; printf '%s' "$s"; }
mkdir -p "$dir"
printf '{"ts":"%s","change":"%s","phase":"%s","event":"%s","status":"%s","note":"%s"}\n' \
  "$ts" "$(esc "$change")" "$(esc "$phase")" "$event" "$status" "$(esc "$note")" >> "$dir/ledger.jsonl"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x scripts/ledger && bash tests/ledger.test.sh`
Expected: `PASS ledger append`, `PASS ledger enum guard`, `LEDGER TESTS PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/ledger tests/ledger.test.sh
git update-index --chmod=+x scripts/ledger tests/ledger.test.sh
git commit -m "feat(ledger): add ledger helper that appends validated JSONL"
```

---

### Task 2: `ss-audit` (bash)

**Files:**
- Create: `scripts/ss-audit`
- Modify: `tests/ledger.test.sh` (append audit assertions)

**Interfaces:**
- Consumes: ledger written by `ledger` (Task 1).
- Produces: `ss-audit [change]` → prints a report; exit `0` complete, `1` incomplete. `ss-audit --attest` → prints `SuperStack process: ...` line, exit 0. Reads `${SUPERSTACK_DIR:-.superstack}/config` key `mandatory_phases` (default `review,secure`).

- [ ] **Step 1: Write the failing test**

Append to `tests/ledger.test.sh` *before* the final `echo`:

```bash
# ss-audit: incomplete (only review recorded so far) -> exit 1
chk "audit incomplete" '! bash "$ROOT/scripts/ss-audit" >/dev/null 2>&1'
# add secure pass -> complete -> exit 0
bash "$ROOT/scripts/ledger" secure gate pass "clean" >/dev/null
chk "audit complete via pass" 'bash "$ROOT/scripts/ss-audit" >/dev/null 2>&1'
# fresh change where secure is explicitly skipped -> still complete
printf '{"ts":"t","change":"br2","phase":"review","event":"gate","status":"pass","note":""}\n'  >> "$SUPERSTACK_DIR/ledger.jsonl"
printf '{"ts":"t","change":"br2","phase":"secure","event":"skip","status":"skip","note":"no IO"}\n' >> "$SUPERSTACK_DIR/ledger.jsonl"
chk "audit complete via skip" 'bash "$ROOT/scripts/ss-audit" br2 >/dev/null 2>&1'
# attestation line contains a tick
chk "audit attest" 'bash "$ROOT/scripts/ss-audit" --attest | grep -q "SuperStack process:"'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/ledger.test.sh`
Expected: the new lines FAIL (`scripts/ss-audit` missing), `LEDGER TESTS FAILED`.

- [ ] **Step 3: Write minimal implementation**

Create `scripts/ss-audit`:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Verify the loop ran: every mandatory phase has a passing gate or an explicit skip-with-reason.
# Usage: ss-audit [change] | ss-audit --attest
set -uo pipefail
dir="${SUPERSTACK_DIR:-.superstack}"
ledger="$dir/ledger.jsonl"; config="$dir/config"
mandatory="review,secure"
[ -f "$config" ] && { v="$(grep -E '^mandatory_phases=' "$config" | tail -1 | cut -d= -f2-)"; [ -n "$v" ] && mandatory="$v"; }
attest=0; change=""
case "${1:-}" in --attest) attest=1;; "") ;; *) change="$1";; esac
[ -n "$change" ] || change="$(git branch --show-current 2>/dev/null || echo default)"
[ -n "$change" ] || change="default"
command -v jq >/dev/null 2>&1 || { echo "ss-audit: jq required" >&2; exit 2; }
[ -f "$ledger" ] || { echo "ss-audit: no ledger at $ledger"; exit 1; }

state() { # echo pass | skip:<reason> | (empty)
  jq -rn --arg c "$change" --arg p "$1" '
    [ inputs | select(.change==$c and .phase==$p) ] as $e
    | if ([$e[] | select(.event=="gate" and .status=="pass")] | length) > 0 then "pass"
      elif ([$e[] | select(.event=="skip")] | length) > 0 then "skip:" + (([$e[] | select(.event=="skip")] | last).note // "")
      else "" end' "$ledger"
}

if [ "$attest" -eq 1 ]; then
  line="SuperStack process:"
  for p in frame plan build review qa secure ship learn; do
    case "$(state "$p")" in pass) line="$line ${p}✓";; skip:*) line="$line ${p}⊘";; esac
  done
  printf '%b\n' "$line"; exit 0
fi

echo "Process audit for '$change' (mandatory: $mandatory):"
missing=""
IFS=','; for p in $mandatory; do
  case "$(state "$p")" in
    pass)   echo "  $p: pass";;
    skip:*) echo "  $p: skip";;
    *)      echo "  $p: MISSING"; missing="$missing $p";;
  esac
done; unset IFS
[ -z "$missing" ] && { echo "VERDICT: COMPLETE"; exit 0; }
echo "VERDICT: INCOMPLETE — missing:$missing"; exit 1
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x scripts/ss-audit && bash tests/ledger.test.sh`
Expected: all `PASS`, `LEDGER TESTS PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/ss-audit tests/ledger.test.sh
git update-index --chmod=+x scripts/ss-audit
git commit -m "feat(audit): add ss-audit proof-of-process verdict + attestation"
```

---

### Task 3: `ss-audit` skill

**Files:**
- Create: `skills/audit/SKILL.md`

- [ ] **Step 1: Write the failing test**

Run: `bash scripts/lint-skills.sh`
Expected before creating: `OK: 19 skill(s)` — i.e. the new skill is not yet present (this is the "red": 19, not 20).

- [ ] **Step 2: Write the skill**

Create `skills/audit/SKILL.md`:

```markdown
---
name: ss-audit
description: Use before shipping, or any time you want to confirm the loop actually ran, to verify every mandatory phase cleared its gate. Reads the loop ledger and reports a COMPLETE/INCOMPLETE verdict.
---

# Audit — proof of process

Verifies the loop was actually followed for this change, using the ledger the phases recorded.

## Steps

1. Run `scripts/ss-audit` (it reads `.superstack/ledger.jsonl` for the current branch and the
   mandatory phases from `.superstack/config`, default `review,secure`).
2. If the verdict is INCOMPLETE, do not paper over it — either run the missing phase now, or
   record an explicit skip with a reason: `ledger <phase> skip skip "<why>"`.
3. Re-run until COMPLETE. `scripts/ss-audit --attest` prints the one-line attestation for the PR.

## Gate

`ss-audit` reports COMPLETE for this change. Record the outcome: `ledger audit gate pass`.

## Lineage

Original to SuperStack — enabled by the explicit gated loop and the Loop Ledger.
```

- [ ] **Step 3: Run the linter to verify it passes**

Run: `bash scripts/lint-skills.sh`
Expected: `OK: 20 skill(s), agents, and manifests valid`.

- [ ] **Step 4: Commit**

```bash
git add skills/audit/SKILL.md
git commit -m "feat(audit): add ss-audit skill"
```

---

### Task 4: Record outcomes from the eight phase skills + CLAUDE.md

**Files:**
- Modify: `skills/{frame,plan,build,review,qa,secure,ship,learn}/SKILL.md` (one line in each `## Gate`)
- Modify: `CLAUDE.md` (document the ledger convention)

- [ ] **Step 1: Write the failing test**

Run: `for p in frame plan build review qa secure ship learn; do grep -q "ledger $p gate" "skills/$p/SKILL.md" || echo "MISSING: $p"; done`
Expected before edits: prints `MISSING:` for all eight.

- [ ] **Step 2: Add the record line to each phase skill**

In each `skills/<phase>/SKILL.md`, at the END of the `## Gate` section, append (substitute the real phase name for `<phase>`):

```markdown

Record the outcome: `ledger <phase> gate pass` — or `ledger <phase> skip skip "<reason>"` if you deliberately skipped this phase.
```

So `skills/review/SKILL.md` gets `ledger review gate pass`, `skills/secure/SKILL.md` gets `ledger secure gate pass`, etc.

- [ ] **Step 3: Document the convention in CLAUDE.md**

In `CLAUDE.md`, in the `## Context Engineering` section, append this bullet:

```markdown
- **Leave a trail.** Each phase records its gate outcome to `.superstack/ledger.jsonl` via the
  `ledger` helper, so `/ss-audit` can verify the loop actually ran before you ship.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `for p in frame plan build review qa secure ship learn; do grep -q "ledger $p gate" "skills/$p/SKILL.md" || echo "MISSING: $p"; done; bash scripts/lint-skills.sh`
Expected: no `MISSING:` lines; `OK: 20 skill(s)`.

- [ ] **Step 5: Commit**

```bash
git add skills CLAUDE.md
git commit -m "feat(ledger): record gate outcomes from each phase skill"
```

---

### Task 5: `/ss-ship` audit-first-gate + attestation

**Files:**
- Modify: `skills/ship/SKILL.md`

- [ ] **Step 1: Write the failing test**

Run: `grep -q "ss-audit" skills/ship/SKILL.md && echo present || echo MISSING`
Expected before edit: `MISSING`.

- [ ] **Step 2: Edit the ship skill**

In `skills/ship/SKILL.md`, insert a new first step in `## Steps` (renumbering the rest):

```markdown
1. **Audit the process first.** Run `/ss-audit` (or `scripts/ss-audit`). If INCOMPLETE, stop and
   close the gap (run the missing phase or record an explicit skip) before continuing. When
   COMPLETE, capture the attestation with `scripts/ss-audit --attest` and include it in the PR body.
```

- [ ] **Step 3: Run test to verify it passes**

Run: `grep -q "ss-audit" skills/ship/SKILL.md && echo present; bash scripts/lint-skills.sh`
Expected: `present`; `OK: 20 skill(s)`.

- [ ] **Step 4: Commit**

```bash
git add skills/ship/SKILL.md
git commit -m "feat(ship): gate ship on ss-audit and attach the attestation"
```

---

### Task 6: Opt-in enforcement hook

**Files:**
- Create: `hooks/audit-check`
- Modify: `hooks/hooks.json`

**Interfaces:**
- Consumes: `scripts/ss-audit` (Task 2). Inert unless `SUPERSTACK_AUDIT=1`.

- [ ] **Step 1: Write the failing test**

Append to `tests/ledger.test.sh` before the final `echo`:

```bash
# audit-check inert when SUPERSTACK_AUDIT unset
chk "hook inert" 'printf "%s" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push\"}}" | bash "$ROOT/hooks/audit-check"'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/ledger.test.sh`
Expected: `FAIL hook inert` (`hooks/audit-check` missing).

- [ ] **Step 3: Create the hook**

Create `hooks/audit-check`:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Opt-in proof-of-process gate. Inert unless SUPERSTACK_AUDIT=1.
# Blocks `git push` / `gh pr create` when the loop ledger is incomplete.
set -uo pipefail
[ "${SUPERSTACK_AUDIT:-0}" = "1" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
input="$(cat)"
[ "$(printf '%s' "$input" | jq -r '.tool_name // empty')" = "Bash" ] || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push|gh[[:space:]]+pr[[:space:]]+create' || exit 0
dir="$(cd "$(dirname "$0")" && pwd)"
if ! bash "$dir/../scripts/ss-audit" >/dev/null 2>&1; then
  reason="$(bash "$dir/../scripts/ss-audit" 2>&1 | grep -i missing || echo 'process incomplete')"
  echo "/ss-audit blocked the push: $reason. Complete the loop or record a skip, or unset SUPERSTACK_AUDIT." >&2
  exit 2
fi
exit 0
```

- [ ] **Step 4: Add the PreToolUse entry to hooks.json**

In `hooks/hooks.json`, add this object to the `PreToolUse` array (alongside the existing guard entry):

```json
{
  "matcher": "Bash",
  "hooks": [
    { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" audit-check", "async": false }
  ]
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `chmod +x hooks/audit-check && bash tests/ledger.test.sh && jq empty hooks/hooks.json && echo "json ok"`
Expected: `PASS hook inert`, `LEDGER TESTS PASS`, `json ok`.

- [ ] **Step 6: Commit**

```bash
git add hooks/audit-check hooks/hooks.json
git update-index --chmod=+x hooks/audit-check
git commit -m "feat(audit): opt-in PreToolUse hook to block pushes on incomplete process"
```

---

### Task 7: PowerShell parity

**Files:**
- Create: `scripts/ledger.ps1`, `scripts/ss-audit.ps1`

- [ ] **Step 1: Write the failing test**

Run: `pwsh -NoProfile -Command "Test-Path scripts/ledger.ps1, scripts/ss-audit.ps1"`
Expected before creating: `False`, `False`.

- [ ] **Step 2: Create `scripts/ledger.ps1`**

```powershell
#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Append a validated entry to .superstack/ledger.jsonl. Usage: ledger.ps1 <phase> <event> [status] [note]
param([string]$Phase, [string]$Event, [string]$Status = "na", [string]$Note = "")
$ErrorActionPreference = 'Stop'
if (-not $Phase -or -not $Event) { Write-Error "usage: ledger.ps1 <phase> <event> [status] [note]"; exit 1 }
if ($Event  -notin 'enter','gate','skip','note') { Write-Error "invalid event '$Event'";  exit 1 }
if ($Status -notin 'pass','fail','skip','na')     { Write-Error "invalid status '$Status'"; exit 1 }
$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
$ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$change = "$(git branch --show-current 2>$null)".Trim(); if (-not $change) { $change = 'default' }
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$obj = [ordered]@{ ts = $ts; change = $change; phase = $Phase; event = $Event; status = $Status; note = $Note }
($obj | ConvertTo-Json -Compress) | Add-Content -Path (Join-Path $dir 'ledger.jsonl')
```

- [ ] **Step 3: Create `scripts/ss-audit.ps1`**

```powershell
#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Verify mandatory phases ran. Usage: ss-audit.ps1 [change] | ss-audit.ps1 -Attest
param([string]$Change = "", [switch]$Attest)
$ErrorActionPreference = 'Stop'
$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
$ledger = Join-Path $dir 'ledger.jsonl'; $config = Join-Path $dir 'config'
$mandatory = @('review','secure')
if (Test-Path $config) {
  $m = Select-String -Path $config -Pattern '^mandatory_phases=(.*)$' | Select-Object -Last 1
  if ($m) { $mandatory = $m.Matches.Groups[1].Value -split ',' }
}
if (-not $Change) { $Change = "$(git branch --show-current 2>$null)".Trim() }
if (-not $Change) { $Change = 'default' }
if (-not (Test-Path $ledger)) { Write-Host "ss-audit: no ledger at $ledger"; exit 1 }
$entries = Get-Content $ledger | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.change -eq $Change }
function Get-State([string]$p) {
  $e = $entries | Where-Object { $_.phase -eq $p }
  if ($e | Where-Object { $_.event -eq 'gate' -and $_.status -eq 'pass' }) { return 'pass' }
  $s = $e | Where-Object { $_.event -eq 'skip' } | Select-Object -Last 1
  if ($s) { return "skip:$($s.note)" }
  return ''
}
if ($Attest) {
  $line = 'SuperStack process:'
  foreach ($p in 'frame','plan','build','review','qa','secure','ship','learn') {
    $s = Get-State $p
    if ($s -eq 'pass') { $line += " $p" + [char]0x2713 } elseif ($s -like 'skip:*') { $line += " $p" + [char]0x2298 }
  }
  Write-Host $line; exit 0
}
Write-Host "Process audit for '$Change' (mandatory: $($mandatory -join ',')):"
$missing = @()
foreach ($p in $mandatory) {
  $s = Get-State $p
  if ($s -eq 'pass') { Write-Host "  $p: pass" }
  elseif ($s -like 'skip:*') { Write-Host "  $p: skip" }
  else { Write-Host "  $p: MISSING"; $missing += $p }
}
if ($missing.Count) { Write-Host "VERDICT: INCOMPLETE - missing: $($missing -join ' ')"; exit 1 }
Write-Host "VERDICT: COMPLETE"; exit 0
```

- [ ] **Step 4: Verify behavior parity**

Run:
```bash
pwsh -NoProfile -Command '$env:SUPERSTACK_DIR=(Join-Path $env:TEMP ".ss-ps"); Remove-Item -Recurse -Force $env:SUPERSTACK_DIR -EA 0; & ./scripts/ledger.ps1 review gate pass "x"; & ./scripts/ledger.ps1 secure gate pass "y"; if ((& ./scripts/ss-audit.ps1; $LASTEXITCODE) -eq 0) { "COMPLETE ok" } else { "FAIL" }; Remove-Item -Recurse -Force $env:SUPERSTACK_DIR -EA 0'
```
Expected: `VERDICT: COMPLETE` then `COMPLETE ok`.

- [ ] **Step 5: Commit**

```bash
git add scripts/ledger.ps1 scripts/ss-audit.ps1
git commit -m "feat(ledger): PowerShell parity for ledger and ss-audit"
```

---

### Task 8: Wire into CI + docs + gitignore

**Files:**
- Modify: `tests/run.sh` (add `[4/4]`), `.gitignore`, `README.md`, `CHANGELOG.md`
- Create: `docs/ledger.md`

- [ ] **Step 1: Add the ledger suite to the self-test**

In `tests/run.sh`, change the three `[1/3]…[3/3]` labels to `[1/4]…[3/4]`, and before the final `echo` add:

```bash
echo "[4/4] ledger + audit behavior"
if bash "$ROOT/tests/ledger.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - ledger/audit suite"; fail=1
fi
```

- [ ] **Step 2: Ignore the runtime ledger**

In `.gitignore`, under the Ralph runtime section, add:

```
.superstack/
```

- [ ] **Step 3: Write `docs/ledger.md`**

```markdown
# The Loop Ledger

SuperStack records its loop's execution to `.superstack/ledger.jsonl` (runtime, gitignored). Each
phase appends its gate outcome via the `ledger` helper:

    ledger <phase> <event> [status] [note]    # e.g. ledger review gate pass "no critical"

`ss-audit` reads the ledger and verifies the mandatory phases (`.superstack/config` →
`mandatory_phases`, default `review,secure`) each have a passing gate or an explicit
skip-with-reason. `/ss-ship` runs it as its first gate and attaches the attestation
(`ss-audit --attest`) to the PR — the durable, shareable proof of how the change was built.

**Hard enforcement (opt-in):** set `SUPERSTACK_AUDIT=1` and the audit hook blocks
`git push` / `gh pr create` until the process is complete.
```

- [ ] **Step 4: Note it in README and CHANGELOG**

In `README.md` `## Hooks` (or a new `## Loop Ledger` note), add one line:

```markdown
SuperStack records each phase's gate outcome to `.superstack/ledger.jsonl`; `/ss-audit` verifies the loop ran before you ship, and `/ss-ship` attaches a proof-of-process attestation to the PR. See [`docs/ledger.md`](docs/ledger.md).
```

In `CHANGELOG.md` under `## [Unreleased]` → `### Added`, add:

```markdown
- **Loop Ledger:** `.superstack/ledger.jsonl` + `ledger` helper, `ss-audit` proof-of-process gate
  with PR attestation, and an opt-in enforcement hook (`SUPERSTACK_AUDIT=1`).
```

- [ ] **Step 5: Run the full gate**

Run: `bash scripts/lint-skills.sh && bash tests/run.sh`
Expected: `OK: 20 skill(s)…`; `[4/4] ledger + audit behavior PASS`; `ALL TESTS PASS`.

- [ ] **Step 6: Commit**

```bash
git add tests/run.sh .gitignore docs/ledger.md README.md CHANGELOG.md
git commit -m "feat(ledger): wire audit into CI, ignore runtime state, document"
```

---

## Self-Review

**Spec coverage:** ledger format + helper (Task 1) ✓; ss-audit verdict + config + attestation (Task 2) ✓; ss-audit skill (Task 3) ✓; phase-skill recording + CLAUDE.md convention (Task 4) ✓; ss-ship audit gate + attestation (Task 5) ✓; opt-in enforcement hook (Task 6) ✓; PowerShell parity (Task 7) ✓; testing + CI + gitignore + docs (Task 8) ✓. No spec requirement left unimplemented.

**Placeholder scan:** every code/step is complete; no TBD/TODO/"handle edge cases".

**Type/name consistency:** `ledger <phase> <event> [status] [note]` and the `{ts,change,phase,event,status,note}` schema, `SUPERSTACK_DIR`, `mandatory_phases`, `SUPERSTACK_AUDIT`, and `scripts/ss-audit` exit codes (0 complete / 1 incomplete / 2 usage) are used identically across bash, PowerShell, the hook, the tests, and the skills.

**Note:** Tasks 1, 2, 6 grow `tests/ledger.test.sh` incrementally; it isn't wired into `tests/run.sh`/CI until Task 8 — intentional, so per-task runs stay fast and the CI surface flips on once.
