# /ss-context (standing-context cockpit, Front 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/ss-context` — a read-only standing-context budget cockpit (bash `scripts/ss-context` + PowerShell twin), wired into the SessionStart hook for an automatic over-budget advisory, plus a skill and docs.

**Architecture:** Sum the est. tokens (`bytes/4`) of the project's always-loaded files (CLAUDE.md/AGENTS.md/STATE.md/CONTEXT.md + local skill descriptions) vs a `--budget` (default 8000), as a % with OK/WARN/OVER. Detect the other context fronts (native `ss-ctx`/`ss-munch` or external context-mode/jcodemunch in MCP config). Emit advisory flags for bloat. A `--check` quiet mode (one line iff over the warn threshold, always exit 0) is called by the SessionStart hook so the nudge is automatic.

**Tech Stack:** Bash (`wc`/`awk`/`grep`, no jq); PowerShell 7; the `chk` harness with `mktemp` fixtures + pinned `HOME`.

## Global Constraints

(Verbatim from the spec; every task implicitly includes these.)

- **Byte-identical ASCII stdout** across `scripts/ss-context` (bash) and `scripts/ss-context.ps1`. No Unicode. **No `jq` dependency.**
- CLI `ss-context [--budget N] [--check]` (PowerShell `-Budget`/`-Check`). `--budget` default **8000**, must be a positive integer (else exit 1). Unknown flag → exit 1.
- **Exit (full report):** `0` when verdict OK/WARN, **`1` when OVER**, `2`/`1` usage. **`--check` ALWAYS exits 0** and prints nothing unless `pct >= 60`.
- Est. tokens = `floor(bytes/4)`. `total` = sum over present always-loaded artifacts. `pct = floor((100*total + floor(budget/2)) / budget)` (integer-only, both twins). Verdict: **OK** `pct<60`, **WARN** `60<=pct<=100`, **OVER** `pct>100`.
- **Standing footprint** (each counted only if present, in cwd): `CLAUDE.md`, `AGENTS.md`, `STATE.md`, `CONTEXT.md`; plus, if `skills/` exists, the summed length of the `description:` frontmatter VALUE across `skills/*/SKILL.md` (+ a count) as row `skill descs (<n>)`.
- **Context-stack detection** (each → `detected`/`not detected` + hint): runtime sandbox = `scripts/ss-ctx` exists (→ `ss-ctx (native)`) OR `context-mode` in `.mcp.json`/`$HOME/.claude.json` (→ `context-mode (mcp)`), else hint `front 2 (ss-ctx) or install context-mode`; code exploration = `scripts/ss-munch` exists (→ `ss-munch (native)`) OR `jcodemunch` in those configs (→ `jcodemunch (mcp)`), else hint `front 3 (ss-munch) or install jcodemunch`. **bash reads `$HOME`; ps1 reads `$env:HOME` then `$env:USERPROFILE`.**
- **Flags** (advisory only — do NOT affect verdict/exit; emitted only when tripped): `CLAUDE.md` > 16384 bytes → `trim to stable instructions (it is never evicted)`; `STATE.md`/`CONTEXT.md` > 8192 bytes → `compact via /ss-learn`; `${SUPERSTACK_DIR}/ledger.jsonl` > 1000 lines → `archive old entries`; `${SUPERSTACK_DIR}/replays/`+`proposals/` combined > 50 files → `archive`. (Spec said ">5MB"; refined to a **file count** because byte-size of a dir diverges across twins — `du` blocks vs logical bytes — whereas a file count is parity-clean.)
- **Output blocks** (54-dash separators): header `ss-context: standing context budget`; footprint table (`%-18s%-8s%s` header `artifact`/`bytes`/`~tokens` + one row per present artifact); `session-start: ~<T> tokens / <B> budget (<pct>%)   <verdict>`; `context stack:` + two `  %-18s %-13s %s` rows; `flags:` + `  ! <artifact> <metric> - <rec>` lines or `  (none)`; `verdict: <v>   (warn >=60%, over >100%)`.
- **`--check` line** (when `pct>=60`): `[ss-context] standing context ~<T> tok = <pct>% of <B> budget - <rec> (run /ss-context)` where `<rec>` = the first tripped flag's recommendation (text after ` - `) or `review /ss-context`.
- `${SUPERSTACK_DIR:-.superstack}`; `export LC_ALL=C`; runs from repo/project root. ps1: `[Parameter(ValueFromRemainingArguments)]$Rest` → exit 1; `[System.StringComparer]::Ordinal` for any sort. Conventional commits, no AI attribution. Ships v0.7.0 cut; skills → 29.

Reference siblings: `scripts/ss-doctor` (read-only multi-check report shape), `scripts/ss-stats`/`ss-trace` + `.ps1` (parity idioms, `$Rest` rejection), `hooks/session-start` (the hook to extend). Spec: `docs/specs/2026-06-25-ss-context-design.md`.

---

## File Structure

- `scripts/ss-context` — bash (Task 1)
- `scripts/ss-context.ps1` — PowerShell twin (Task 2)
- `tests/context.test.sh` — behavior (Task 1) + parity (Task 2)
- `tests/run.sh` — wire `[14/14]`, bump `[N/13]`→`[N/14]` (Task 1)
- `hooks/session-start` — append the `--check` advisory (Task 3)
- `skills/context/SKILL.md` — the skill + playbook (Task 4)
- `README.md`, `CHANGELOG.md` — surface it (Task 5)

---

## Task 1: `scripts/ss-context` (bash) + tests + run.sh wiring

**Model:** sonnet.

**Files:** Create `scripts/ss-context`, `tests/context.test.sh`; Modify `tests/run.sh`.

**Interfaces:** Produces `scripts/ss-context [--budget N] [--check]` (exit 0/1). Consumes cwd files, `${SUPERSTACK_DIR}`, `$HOME/.claude.json`.

This script is **author-verified end-to-end** against fixtures (OK/WARN/OVER, `--check` silent vs advisory, detection both ways, flags, usage). Transcribe verbatim.

- [ ] **Step 1: Write the failing tests** — create `tests/context.test.sh`

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavior + parity tests for scripts/ss-context.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }

# A fixture project dir with exact-byte standing files + 2 skills. HOMEDIR pins detection.
HOMEDIR="$(mktemp -d)"   # empty -> no ~/.claude.json -> deterministic "not detected"
mkfix() {
  local d; d="$(mktemp -d)"
  ( cd "$d"
    head -c 7560 /dev/zero | tr '\0' x > CLAUDE.md
    head -c 612  /dev/zero | tr '\0' x > STATE.md
    head -c 980  /dev/zero | tr '\0' x > CONTEXT.md
    mkdir -p skills/a skills/b .superstack
    printf -- '---\nname: ss-a\ndescription: %s\n---\n# A\n' "$(head -c 400 /dev/zero | tr '\0' d)" > skills/a/SKILL.md
    printf -- '---\nname: ss-b\ndescription: %s\n---\n# B\n' "$(head -c 300 /dev/zero | tr '\0' d)" > skills/b/SKILL.md
    printf '{"ts":"t"}\n' > .superstack/ledger.jsonl )
  printf '%s' "$d"
}
run() { ( cd "$1" && HOME="$HOMEDIR" SUPERSTACK_DIR="$1/.superstack" bash "$ROOT/scripts/ss-context" "${@:2}" ); }

D="$(mkfix)"
out="$(run "$D")"; rc=$?
# tokens: 7560/4=1890, 612/4=153, 980/4=245, descs 700/4=175 => total 2463; pct round(100*2463/8000)=31
chk "row CLAUDE"   'printf "%s" "$out" | grep -qE "^CLAUDE.md +7560 +1890$"'
chk "row descs"    'printf "%s" "$out" | grep -qE "^skill descs \(2\) +700 +175$"'
chk "budget OK"    'printf "%s" "$out" | grep -qF "session-start: ~2463 tokens / 8000 budget (31%)   OK"'
chk "stack none"   'printf "%s" "$out" | grep -qE "^  runtime sandbox +not detected"'
chk "flags none"   'printf "%s" "$out" | grep -qF "  (none)"'
chk "verdict OK"   'printf "%s" "$out" | grep -qF "verdict: OK"'
chk "exit 0"       '[ "$rc" -eq 0 ]'

# OVER: tiny budget -> exit 1
( run "$D" --budget 1000 ) >/dev/null 2>&1; chk "over exit 1" '[ "$?" -eq 1 ]'
chk "over verdict" 'run "$D" --budget 1000 | grep -qF "verdict: OVER"'

# --check: silent when OK, one line when over
chk "check silent" '[ -z "$(run "$D" --check)" ]'
chk "check advisory" 'run "$D" --check --budget 1000 | grep -qE "^\[ss-context\] standing context ~2463 tok = 246% of 1000 budget - review /ss-context \(run /ss-context\)$"'

# detection: cwd .mcp.json (mcp) and native stubs
Dm="$(mkfix)"; printf '{"mcpServers":{"context-mode":{}}}\n' > "$Dm/.mcp.json"
chk "detect mcp"   'run "$Dm" | grep -qE "^  runtime sandbox +detected +context-mode \(mcp\)$"'
Dn="$(mkfix)"; mkdir -p "$Dn/scripts"; : > "$Dn/scripts/ss-munch"
chk "detect native" 'run "$Dn" | grep -qE "^  code exploration +detected +ss-munch \(native\)$"'

# flags: oversized CLAUDE.md + >1000-line ledger
Df="$(mkfix)"; head -c 20000 /dev/zero | tr '\0' x > "$Df/CLAUDE.md"; yes '{"ts":"t"}' 2>/dev/null | head -1001 > "$Df/.superstack/ledger.jsonl"
chk "flag claude"  'run "$Df" --budget 100000 | grep -qF "  ! CLAUDE.md 20000 bytes - trim to stable instructions (it is never evicted)"'
chk "flag ledger"  'run "$Df" --budget 100000 | grep -qF "  ! ledger.jsonl 1001 lines - archive old entries"'

# usage
( run "$D" --budget 0 ) >/dev/null 2>&1; chk "budget 0 exit 1" '[ "$?" -eq 1 ]'
( run "$D" --bogus )    >/dev/null 2>&1; chk "bogus exit 1"   '[ "$?" -eq 1 ]'

echo
[ "$fail" -eq 0 ] && echo "CONTEXT TESTS PASS" || echo "CONTEXT TESTS FAILED"
exit "$fail"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/context.test.sh`
Expected: FAIL — `scripts/ss-context` does not exist yet.

- [ ] **Step 3: Write `scripts/ss-context`** (verbatim — author-verified)

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Standing-context budget cockpit (read-only). Front 1 of the context all-rounder.
# Usage: ss-context [--budget N] [--check]  Exit: 0 ok/warn, 1 over (report), 2 usage. --check always 0.
set -uo pipefail
export LC_ALL=C
dir="${SUPERSTACK_DIR:-.superstack}"
budget=8000; check=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --budget) budget="${2:-}"; shift 2;;
    --budget=*) budget="${1#*=}"; shift;;
    --check) check=1; shift;;
    *) echo "ss-context: unknown flag '$1' (usage: ss-context [--budget N] [--check])" >&2; exit 1;;
  esac
done
case "$budget" in ''|*[!0-9]*) echo "ss-context: --budget must be a positive integer" >&2; exit 1;; esac
[ "$budget" -ge 1 ] 2>/dev/null || { echo "ss-context: --budget must be a positive integer" >&2; exit 1; }

fbytes() { if [ -f "$1" ]; then wc -c < "$1" | tr -d ' '; else echo 0; fi; }
rows=""; total=0
add_row() { local b; b="$(fbytes "$2")"; [ "$b" -gt 0 ] || return 0; local t=$((b/4)); rows="${rows}${1}|${b}|${t}"$'\n'; total=$((total+t)); }
add_row "CLAUDE.md" "CLAUDE.md"
add_row "AGENTS.md" "AGENTS.md"
add_row "STATE.md" "STATE.md"
add_row "CONTEXT.md" "CONTEXT.md"
sk_bytes=0; sk_count=0
if [ -d skills ]; then
  for f in skills/*/SKILL.md; do
    [ -e "$f" ] || continue
    d="$(awk '/^description:/{sub(/^description:[ ]*/,""); print; exit}' "$f")"
    sk_count=$((sk_count+1)); sk_bytes=$((sk_bytes + ${#d}))
  done
fi
if [ "$sk_count" -gt 0 ]; then sk_t=$((sk_bytes/4)); rows="${rows}skill descs (${sk_count})|${sk_bytes}|${sk_t}"$'\n'; total=$((total+sk_t)); fi

pct=$(( (100*total + budget/2) / budget ))
if [ "$pct" -lt 60 ]; then verdict="OK"; elif [ "$pct" -le 100 ]; then verdict="WARN"; else verdict="OVER"; fi

flags=""
cb="$(fbytes CLAUDE.md)"; [ "$cb" -gt 16384 ] && flags="${flags}  ! CLAUDE.md ${cb} bytes - trim to stable instructions (it is never evicted)"$'\n'
for sf in STATE.md CONTEXT.md; do sb="$(fbytes "$sf")"; [ "$sb" -gt 8192 ] && flags="${flags}  ! ${sf} ${sb} bytes - compact via /ss-learn"$'\n'; done
ledger="$dir/ledger.jsonl"
if [ -f "$ledger" ]; then ll="$(wc -l < "$ledger" | tr -d ' ')"; [ "$ll" -gt 1000 ] && flags="${flags}  ! ledger.jsonl ${ll} lines - archive old entries"$'\n'; fi
rpf=0; for d2 in "$dir/replays" "$dir/proposals"; do [ -d "$d2" ] && rpf=$((rpf + $(find "$d2" -type f 2>/dev/null | wc -l))); done
[ "$rpf" -gt 50 ] && flags="${flags}  ! replays/+proposals/ ${rpf} files - archive"$'\n'

rt_det="not detected"; rt_hint="front 2 (ss-ctx) or install context-mode"
if [ -f scripts/ss-ctx ]; then rt_det="detected"; rt_hint="ss-ctx (native)"; elif grep -qs 'context-mode' .mcp.json "$HOME/.claude.json" 2>/dev/null; then rt_det="detected"; rt_hint="context-mode (mcp)"; fi
cx_det="not detected"; cx_hint="front 3 (ss-munch) or install jcodemunch"
if [ -f scripts/ss-munch ]; then cx_det="detected"; cx_hint="ss-munch (native)"; elif grep -qs 'jcodemunch' .mcp.json "$HOME/.claude.json" 2>/dev/null; then cx_det="detected"; cx_hint="jcodemunch (mcp)"; fi

if [ "$check" = "1" ]; then
  if [ "$pct" -ge 60 ]; then
    rec="$(printf '%s' "$flags" | sed -n '1s/.* - //p')"; [ -n "$rec" ] || rec="review /ss-context"
    printf '[ss-context] standing context ~%d tok = %d%% of %d budget - %s (run /ss-context)\n' "$total" "$pct" "$budget" "$rec"
  fi
  exit 0
fi

SEP="$(printf -- '-%.0s' {1..54})"
printf 'ss-context: standing context budget\n%s\n' "$SEP"
printf '%-18s%-8s%s\n' 'artifact' 'bytes' '~tokens'
printf '%s' "$rows" | while IFS='|' read -r n b t; do [ -n "$n" ] || continue; printf '%-18s%-8s%s\n' "$n" "$b" "$t"; done
printf '%s\n' "$SEP"
printf 'session-start: ~%d tokens / %d budget (%d%%)   %s\n' "$total" "$budget" "$pct" "$verdict"
printf '%s\n' "$SEP"
printf 'context stack:\n'
printf '  %-18s %-13s %s\n' 'runtime sandbox' "$rt_det" "$rt_hint"
printf '  %-18s %-13s %s\n' 'code exploration' "$cx_det" "$cx_hint"
printf '%s\n' "$SEP"
printf 'flags:\n'
if [ -n "$flags" ]; then printf '%s' "$flags"; else printf '  (none)\n'; fi
printf 'verdict: %s   (warn >=60%%, over >100%%)\n' "$verdict"
[ "$verdict" = "OVER" ] && exit 1 || exit 0
```

- [ ] **Step 4: Make it executable and run the tests**

Run: `chmod +x scripts/ss-context && bash tests/context.test.sh`
Expected: `CONTEXT TESTS PASS`. (Detection reads `$HOME/.claude.json`; the tests pin `HOME` to an empty dir for determinism — do not drop that.)

- [ ] **Step 5: Wire the suite into `tests/run.sh`**

In `tests/run.sh`: change the thirteen labels `[1/13]`…`[13/13]` to `[1/14]`…`[13/14]`. Then insert after the `[13/14] trace behavior` block (after its closing `fi`, before the final summary `echo`):

```bash
echo "[14/14] context behavior"
if bash "$ROOT/tests/context.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - context suite"; fail=1
fi
```

- [ ] **Step 6: Run the full suite + lint**

Run: `bash tests/run.sh && bash scripts/lint-skills.sh .`
Expected: `[1/14]`…`[14/14]` PASS, `ALL TESTS PASS`; lint clean. (Allow ~420000ms. A `[1/14]` JSON-lint false alarm in a restricted sandbox is known; the `context.test.sh` suite passing is the real signal.)

- [ ] **Step 7: Commit**

```bash
git add scripts/ss-context tests/context.test.sh tests/run.sh
git commit -m "feat(context): add ss-context standing-context cockpit (bash)"
```

---

## Task 2: `scripts/ss-context.ps1` (PowerShell twin) + parity test

**Model:** sonnet.

**Files:** Create `scripts/ss-context.ps1`; Modify `tests/context.test.sh` (append a parity block).

**Interfaces:** Consumes the bash `scripts/ss-context` output (byte-identical). Produces `scripts/ss-context.ps1 [-Budget N] [-Check]` + exit 0/1.

- [ ] **Step 1: Append the failing parity test** to `tests/context.test.sh`, before the final `echo`/summary:

```bash
if command -v pwsh >/dev/null 2>&1; then
  if command -v cygpath >/dev/null 2>&1; then ps1arg="$(cygpath -w "$ROOT/scripts/ss-context.ps1")"; else ps1arg="$ROOT/scripts/ss-context.ps1"; fi
  Dp="$(mkfix)"; Dp2="$(mkfix)"; printf '{"mcpServers":{"context-mode":{}}}\n' > "$Dp2/.mcp.json"
  # full report parity (default budget; detection none) and (with mcp detection)
  for fx in "$Dp" "$Dp2"; do
    pb="$(cd "$fx" && HOME="$HOMEDIR" SUPERSTACK_DIR="$fx/.superstack" bash "$ROOT/scripts/ss-context")"
    pp="$(cd "$fx" && HOME="$HOMEDIR" SUPERSTACK_DIR="$fx/.superstack" pwsh -NoProfile -File "$ps1arg" | tr -d '\r')"
    chk "ps1 parity report [$fx]" '[ "$pb" = "$pp" ]'
  done
  # --check advisory parity (over budget)
  cb="$(cd "$Dp" && HOME="$HOMEDIR" SUPERSTACK_DIR="$Dp/.superstack" bash "$ROOT/scripts/ss-context" --check --budget 1000)"
  cp="$(cd "$Dp" && HOME="$HOMEDIR" SUPERSTACK_DIR="$Dp/.superstack" pwsh -NoProfile -File "$ps1arg" -Check -Budget 1000 | tr -d '\r')"
  chk "ps1 parity --check" '[ "$cb" = "$cp" ]'
else
  echo "  SKIP ps1 parity (pwsh not installed)"
fi
```

- [ ] **Step 2: Run the tests to confirm the parity check fails**

Run: `bash tests/context.test.sh` → behavior PASS; `ps1 parity` FAIL (no ps1) or SKIP.

- [ ] **Step 3: Write `scripts/ss-context.ps1`**

```powershell
#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Standing-context budget cockpit (read-only). Front 1 of the context all-rounder.
param([string]$Budget='8000', [switch]$Check, [Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)
$ErrorActionPreference = 'Stop'
if ($Rest -and $Rest.Count -gt 0) { [Console]::Error.WriteLine("ss-context: unknown flag '$($Rest -join ' ')' (usage: ss-context [--budget N] [--check])"); exit 1 }
if ($Budget -notmatch '^[0-9]+$' -or [int]$Budget -lt 1) { [Console]::Error.WriteLine("ss-context: --budget must be a positive integer"); exit 1 }
$budget = [int]$Budget

$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
if ($dir -match '^/[a-zA-Z]/') { try { $dir = (& cygpath -w $dir 2>$null).Trim() } catch {} }
$homeDir = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }

function FBytes($p) { if (Test-Path -LiteralPath $p -PathType Leaf) { (Get-Item -LiteralPath $p).Length } else { 0 } }
$rows = New-Object System.Collections.Generic.List[object]
$total = 0
function AddRow($name, $file) {
  $b = [int](FBytes $file); if ($b -le 0) { return }
  $t = [math]::Floor($b / 4); $script:total += $t
  $script:rows.Add([pscustomobject]@{ n=$name; b=$b; t=$t })
}
AddRow 'CLAUDE.md' 'CLAUDE.md'; AddRow 'AGENTS.md' 'AGENTS.md'; AddRow 'STATE.md' 'STATE.md'; AddRow 'CONTEXT.md' 'CONTEXT.md'
$skBytes = 0; $skCount = 0
if (Test-Path 'skills' -PathType Container) {
  foreach ($f in (Get-ChildItem -Path 'skills' -Filter 'SKILL.md' -Recurse -File -ErrorAction SilentlyContinue)) {
    $line = (Get-Content -LiteralPath $f.FullName | Where-Object { $_ -match '^description:' } | Select-Object -First 1)
    if ($null -ne $line) { $d = ($line -replace '^description:[ ]*',''); $skCount++; $skBytes += $d.Length }
  }
}
if ($skCount -gt 0) { $skT = [math]::Floor($skBytes / 4); $total += $skT; $rows.Add([pscustomobject]@{ n="skill descs ($skCount)"; b=$skBytes; t=$skT }) }

$pct = [int][math]::Floor((100*$total + [math]::Floor($budget/2)) / $budget)
$verdict = if ($pct -lt 60) { 'OK' } elseif ($pct -le 100) { 'WARN' } else { 'OVER' }

$flags = New-Object System.Collections.Generic.List[string]
$cb = [int](FBytes 'CLAUDE.md'); if ($cb -gt 16384) { $flags.Add("  ! CLAUDE.md $cb bytes - trim to stable instructions (it is never evicted)") }
foreach ($sf in @('STATE.md','CONTEXT.md')) { $sb=[int](FBytes $sf); if ($sb -gt 8192) { $flags.Add("  ! $sf $sb bytes - compact via /ss-learn") } }
$ledger = Join-Path $dir 'ledger.jsonl'
if (Test-Path -LiteralPath $ledger -PathType Leaf) { $ll = @(Get-Content -LiteralPath $ledger).Count; if ($ll -gt 1000) { $flags.Add("  ! ledger.jsonl $ll lines - archive old entries") } }
$rpf = 0; foreach ($d2 in @((Join-Path $dir 'replays'), (Join-Path $dir 'proposals'))) { if (Test-Path $d2 -PathType Container) { $rpf += @(Get-ChildItem -Path $d2 -Recurse -File -ErrorAction SilentlyContinue).Count } }
if ($rpf -gt 50) { $flags.Add("  ! replays/+proposals/ $rpf files - archive") }

function Detect($nativeScript, $cfgName) {
  if (Test-Path -LiteralPath $nativeScript -PathType Leaf) { return @('detected', "$([System.IO.Path]::GetFileName($nativeScript)) (native)") }
  foreach ($c in @('.mcp.json', (Join-Path $homeDir '.claude.json'))) {
    if ((Test-Path -LiteralPath $c -PathType Leaf) -and (Select-String -LiteralPath $c -SimpleMatch $cfgName -Quiet)) { return @('detected', "$cfgName (mcp)") }
  }
  return @($null, $null)
}
$rt = Detect 'scripts/ss-ctx' 'context-mode'
$rtDet = if ($rt[0]) { 'detected' } else { 'not detected' }; $rtHint = if ($rt[1]) { $rt[1] } else { 'front 2 (ss-ctx) or install context-mode' }
$cx = Detect 'scripts/ss-munch' 'jcodemunch'
$cxDet = if ($cx[0]) { 'detected' } else { 'not detected' }; $cxHint = if ($cx[1]) { $cx[1] } else { 'front 3 (ss-munch) or install jcodemunch' }

if ($Check) {
  if ($pct -ge 60) {
    $rec = if ($flags.Count -gt 0) { ($flags[0] -replace '^.* - ','') } else { 'review /ss-context' }
    Write-Output "[ss-context] standing context ~$total tok = $pct% of $budget budget - $rec (run /ss-context)"
  }
  exit 0
}

$SEP = '-' * 54
$out = New-Object System.Collections.Generic.List[string]
$out.Add('ss-context: standing context budget'); $out.Add($SEP)
$out.Add('{0,-18}{1,-8}{2}' -f 'artifact','bytes','~tokens')
foreach ($r in $rows) { $out.Add('{0,-18}{1,-8}{2}' -f $r.n, $r.b, $r.t) }
$out.Add($SEP)
$out.Add("session-start: ~$total tokens / $budget budget ($pct%)   $verdict")
$out.Add($SEP)
$out.Add('context stack:')
$out.Add('  {0,-18} {1,-13} {2}' -f 'runtime sandbox', $rtDet, $rtHint)
$out.Add('  {0,-18} {1,-13} {2}' -f 'code exploration', $cxDet, $cxHint)
$out.Add($SEP)
$out.Add('flags:')
if ($flags.Count -gt 0) { foreach ($fl in $flags) { $out.Add($fl) } } else { $out.Add('  (none)') }
$out.Add("verdict: $verdict   (warn >=60%, over >100%)")
Write-Output ($out -join "`n")
if ($verdict -eq 'OVER') { exit 1 } else { exit 0 }
```

Parity notes for the implementer:
- **Integer math must match bash exactly:** `$pct = [int][math]::Floor((100*$total + [math]::Floor($budget/2)) / $budget)`; `$t = [math]::Floor($b/4)`. No rounding ops.
- **`$env:HOME` then `$env:USERPROFILE`** for the config-home (bash uses `$HOME`); the tests pin `HOME`, which PowerShell reads via `$env:HOME`.
- **Format strings** `'{0,-18}{1,-8}{2}'` and `'  {0,-18} {1,-13} {2}'` mirror the bash `printf` widths exactly.
- **`Get-ChildItem ... -Recurse` for `skills/*/SKILL.md`** — the sum is order-independent, but the description extraction (`Where-Object {$_ -match '^description:'} | Select -First 1` then `-replace '^description:[ ]*',''`) must mirror the bash `awk` (first `description:` line, strip the key + one-or-more spaces). Description values are ASCII so `.Length` (chars) == bytes.
- **`--check` always exits 0**; the full report exits 1 only on `OVER`.
- `[Parameter(ValueFromRemainingArguments)]$Rest` → exit 1 on extra args (mirrors bash unknown-flag).

- [ ] **Step 4: Run the tests to verify parity passes**

Run: `bash tests/context.test.sh`
Expected: all PASS incl. `ps1 parity report [...]` (both fixtures) and `ps1 parity --check` (or SKIP if no pwsh) → `CONTEXT TESTS PASS`. If parity fails, diff `bash scripts/ss-context` vs `pwsh -NoProfile -File scripts/ss-context.ps1 | tr -d '\r'` on the same fixture (with `HOME` pinned); likely culprits: the `pct`/`bytes/4` integer math, the `$env:HOME` config path, the description extraction, or a width mismatch.

- [ ] **Step 5: Run the full suite** — `bash tests/run.sh` → `[1/14]..[14/14]`, `ALL TESTS PASS`.

- [ ] **Step 6: Commit**

```bash
git add scripts/ss-context.ps1 tests/context.test.sh
git commit -m "feat(context): PowerShell parity for ss-context"
```

---

## Task 3: SessionStart hook — automatic advisory

**Model:** sonnet (modifies the always-loaded session bootstrap — care + its own review gate).

**Files:** Modify `hooks/session-start`; Modify `tests/run.sh` (extend the existing session-start hook self-test).

**Interfaces:** Consumes `scripts/ss-context --check` (Task 1). The hook stays bash-only (launched cross-platform via `run-hook.cmd`).

- [ ] **Step 1: Add the advisory to `hooks/session-start`**

In `hooks/session-start`, the line that builds `context` reads:
```bash
context="${intro}$(escape_json "$bootstrap")\n</EXTREMELY_IMPORTANT>"
```
Immediately AFTER that line, insert:
```bash
# Front 1: append the standing-context budget advisory iff over the warn threshold (silent otherwise).
adv="$(cd "$PWD" && bash "${PLUGIN_ROOT}/scripts/ss-context" --check 2>/dev/null || true)"
[ -n "$adv" ] && context="${context}\\n\\n$(escape_json "$adv")"
```
(`--check` prints nothing when under budget, so `$adv` is empty and `context` is unchanged — byte-identical to today. `2>/dev/null || true` means a missing/erroring `ss-context` can never break session start. The literal `\\n\\n` becomes two `\n` escapes inside the JSON string, matching the existing `\n` style in the file.)

- [ ] **Step 2: Extend the hook self-test in `tests/run.sh`**

Find the existing test that runs `hooks/session-start` and asserts it emits valid JSON (search `session-start` in `tests/run.sh`). Add two assertions using fixtures (place them within/after that test block; use the suite's existing `fail=1` convention):

```bash
# context advisory: present when over budget, absent when OK; JSON stays valid both ways.
ctxfix_over="$(mktemp -d)"; head -c 40000 /dev/zero | tr '\0' x > "$ctxfix_over/CLAUDE.md"   # ~10000 tok > 8000
ctxfix_ok="$(mktemp -d)";   head -c 400   /dev/zero | tr '\0' x > "$ctxfix_ok/CLAUDE.md"
over_out="$(cd "$ctxfix_over" && bash "$ROOT/hooks/session-start" 2>/dev/null)"
ok_out="$(cd "$ctxfix_ok"   && bash "$ROOT/hooks/session-start" 2>/dev/null)"
if printf '%s' "$over_out" | grep -qF '[ss-context]'; then echo "      PASS hook advisory present (over budget)"; else echo "      FAIL hook advisory missing"; fail=1; fi
if printf '%s' "$ok_out" | grep -qF '[ss-context]'; then echo "      FAIL hook advisory leaked (ok budget)"; fail=1; else echo "      PASS hook advisory silent (ok budget)"; fi
if printf '%s' "$over_out" | jq -e . >/dev/null 2>&1; then echo "      PASS hook JSON valid"; else echo "      FAIL hook JSON invalid"; fail=1; fi
```
(The hook computes `PLUGIN_ROOT` from its own path = `$ROOT`, so it finds `$ROOT/scripts/ss-context`; cwd = the fixture, so `--check` measures the fixture. `--check` output has no detection, so `HOME` is irrelevant here. If the suite lacks `jq`, reuse whatever JSON check the existing session-start test already uses instead of the `jq -e` line.)

- [ ] **Step 3: Run the suite**

Run: `bash tests/run.sh`
Expected: the hook test now prints the 3 new PASS lines; `[1/14]..[14/14]`, `ALL TESTS PASS`. Manually sanity-check no-regression: `bash hooks/session-start` in a dir with no/small CLAUDE.md emits the same JSON as before (no `[ss-context]`).

- [ ] **Step 4: Commit**

```bash
git add hooks/session-start tests/run.sh
git commit -m "feat(context): auto standing-context advisory in SessionStart hook"
```

---

## Task 4: `skills/context/SKILL.md`

**Model:** haiku (pure markdown).

**Files:** Create `skills/context/SKILL.md`.

- [ ] **Step 1: Write the skill**

```markdown
---
name: ss-context
description: Use to keep your standing (always-loaded) context lean - /ss-context audits the on-disk footprint (CLAUDE.md, STATE.md/CONTEXT.md, skill descriptions) against a token budget, flags bloat, and detects the rest of your context stack. It also runs automatically at session start, warning only when you are over budget. Front 1 of SuperStack's context all-rounder.
---

# Context - is my standing context lean?

`/ss-context` watches the **standing context** - the always-loaded files that are never evicted from
the window (CLAUDE.md especially). It estimates their token footprint (bytes/4) against a budget,
flags bloat, and detects the other two context fronts (runtime sandbox, code exploration). It is
read-only - it recommends, it never deletes. It also runs **automatically** in the SessionStart hook,
emitting a one-line advisory only when you are over budget.

## Steps

1. It runs on its own at session start; to inspect on demand run `scripts/ss-context`
   (PowerShell: `scripts/ss-context.ps1`). `--budget N` sets the token budget (default 8000).
2. Read the budget line: `OK` (<60%), `WARN` (60-100%), `OVER` (>100%, exits 1 for CI).
3. Read the `context stack` rows - is the runtime sandbox + code exploration wired?
4. Act on the flags / the advisory (below).

## Note - the autopilot playbook

When the advisory or the report says WARN/OVER, apply the levers (smaller curated context beats brute
force):
- `/compact` proactively at ~50% fill and at phase boundaries (a healthy session summarises better);
  `/clear` when switching tasks.
- Offload verbose research/reading to fresh-context subagents (the loop already does this per phase).
- Trim `CLAUDE.md` to stable instructions (it is never evicted); compact `STATE.md`/`CONTEXT.md` via
  [[ss-learn]]; archive a huge ledger.
- **Routing doctrine:** prefer the runtime sandbox (Front 2 `ss-ctx`, or context-mode) for verbose tool
  output, and the code-exploration tool (Front 3 `ss-munch`, or jcodemunch) over brute-reading files;
  fall back to Read/Grep when neither is present.
- **Right-size (Plan):** keep each planned task within one context window; split before starting if not.

## Lineage

Original to SuperStack - Front 1 of the context all-rounder (standing context). Complements [[ss-doctor]]
(dependency/config health, not size) and composes with the runtime/exploration tools rather than
replacing them.
```

- [ ] **Step 2: Verify it lints**

Run: `bash scripts/lint-skills.sh .`
Expected: PASS — 29 skills; `[[ss-learn]]`, `[[ss-doctor]]` resolve (both exist). Name `ss-context`, description 40–500 chars, one H1.

- [ ] **Step 3: Commit**

```bash
git add skills/context/SKILL.md
git commit -m "docs(context): add /ss-context skill"
```

---

## Task 5: README + CHANGELOG

**Model:** haiku (pure markdown).

**Files:** Modify `README.md`, `CHANGELOG.md`.

- [ ] **Step 1: Update the CHANGELOG**

Read `CHANGELOG.md`. The top `## [Unreleased]` already has an `### Added` group (with `/ss-stats` + `/ss-trace`). Add this bullet to that SAME group (do not create a second `### Added`):

```markdown
- **`/ss-context`:** read-only standing-context budget cockpit — estimates the always-loaded footprint
  (CLAUDE.md, STATE.md/CONTEXT.md, skill descriptions) vs a token budget (OK/WARN/OVER), detects the
  rest of the context stack, and flags bloat with fixes. Runs automatically at session start (advisory
  only when over budget). Front 1 of the context all-rounder. bash + PowerShell. (29 skills.)
```

Do NOT rename `[Unreleased]`; don't disturb the dated sections or footer.

- [ ] **Step 2: Surface it in the README**

Read `README.md`. Two surgical edits:
1. Add `/ss-context` to the **Supporting skills** inline list (the line with `/ss-init` … `/ss-trace`), right after `/ss-trace`. (Inline list only — NOT a standalone table.)
2. Bump the skills count **28 → 29** in BOTH the badge (`skills-28`) and the prose (`**28 skills, ...**`). Change only the number; if you find a different number, bump that and note it.

- [ ] **Step 3: Verify** — `bash scripts/lint-skills.sh .` → clean, 29 skills.

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: surface /ss-context in README + CHANGELOG"
```

---

## Self-Review (completed by plan author)

- **Spec coverage:** CLI + `--budget`/`--check` + exit codes (T1) · footprint incl. skill descs (T1+T2) · pct/verdict integer math (T1+T2) · detection native+mcp with `$HOME` (T1+T2) · flags advisory incl. the file-count refinement (T1+T2) · `--check` quiet line (T1+T2) · output format/widths (T1, spec §6) · byte-identical twins incl. integer math + `$env:HOME` + `$Rest` (T2) · parity on report + `--check` (T2) · **automatic SessionStart advisory + no-regression-when-OK** (T3) · hook self-test both cases (T3) · tests→`run.sh [14/14]` (T1–T3) · skill + playbook + routing doctrine (T4) · README 29 + CHANGELOG (T5). All spec sections map to a task.
- **Placeholder scan:** none — the bash script + tests are author-verified end-to-end (OK/WARN/OVER, `--check`, detection both ways with `HOME` pinned, flags, usage); the ps1 + hook change are complete.
- **Type/name consistency:** the `name|bytes|tokens` row protocol, the `pct=floor((100*total+floor(budget/2))/budget)` formula, the `%-18s%-8s%s` ≡ `{0,-18}{1,-8}{2}` and `%-18s %-13s %s` ≡ `{0,-18} {1,-13} {2}` widths, the `OK/WARN/OVER` thresholds, the flag strings + recommendations, the `[ss-context] … (run /ss-context)` advisory, and the detection hints are identical across bash, PowerShell, the tests, and the hook.

---

## Execution Handoff

Recommended: **subagent-driven** — Task 1 (bash, author-verified) + Task 2 (ps1 parity) + Task 3 (SessionStart hook) on sonnet (T3 touches the always-loaded bootstrap — review the no-regression-when-OK path adversarially); Tasks 4–5 (markdown) on haiku; per-task spec+quality review, opus whole-branch review at the end (probe: the hook no-regression path, cross-twin integer/`$HOME` parity, and detection determinism).
