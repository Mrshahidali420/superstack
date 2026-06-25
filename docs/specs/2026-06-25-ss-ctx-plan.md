# ss-ctx (Front 2a: transparent output shrinker) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `ss-ctx` — an always-on `PostToolUse` hook that transparently replaces oversized clean **Bash** stdout with a head/tail summary (offloading the full output to `.superstack/ctx/<id>.txt`), plus a `/ss-ctx` retrieval command (bash + PowerShell twins), a skill, and docs.

**Architecture:** A bash `PostToolUse` hook reads the tool result on stdin, and when a Bash result exceeds a byte threshold (and is clean — no stderr, not interrupted), saves the full stdout byte-exactly to disk and emits `hookSpecificOutput.updatedToolOutput` with stdout replaced by a head+tail+marker summary (Claude Code v2.1.121+ honors this for built-in tools). `/ss-ctx list|show|search|prune` reads that store. Zero runtime; fits SuperStack's bash-hooks-plus-files idiom; flips Front-1's `runtime sandbox: detected (native)` row.

**Tech Stack:** Bash (`jq`, `base64`, coreutils); PowerShell 7 (retrieval twin only); the `chk` harness.

## Global Constraints

(From the spec + the controller's end-to-end pre-verification of the hook. Every task implicitly includes these.)

- **The hook (`hooks/ctx-shrink`) is author-verified** against real PostToolUse payloads — transcribe it verbatim in Task 1. Do not "simplify" the `@base64 | tr -d '\r\n' | base64 -d` round-trip or the raw-id-then-sanitize order; both fix confirmed Windows/Git-Bash bugs:
  - `jq -r` emits `\r\n` on Git Bash → piping into `tr -c` mangles the id (CR+LF → `__`). Fix: capture `raw_id="$(… jq …)"` first (command-subst strips the newline), THEN `tr -c 'A-Za-z0-9_-' '_'`.
  - jq's Windows text-mode inflates `jq -j '.tool_response.stdout' > file` LF→CRLF (not byte-faithful). Fix: `jq -r '.tool_response.stdout | @base64' | tr -d '\r\n' | base64 -d > file` — byte-exact regardless of platform; the `tr -d '\r\n'` strips only jq's base64 padding (the base64 alphabet has no `\r`/`\n`), never content CRs (verified: 699 embedded CRs preserved).
- **Fail-safe, always:** any problem — missing `jq`/`base64`, malformed input, non-string stdout, write failure — makes the hook a **silent no-op (emit nothing, exit 0)**. The hook can NEVER break a session.
- **No-op (emit nothing, exit 0) unless ALL hold:** `SS_CTX_DISABLE` empty; `tool_name == "Bash"`; `tool_response` is an object with empty `stderr`, `interrupted != true`, string `stdout`; and `stdout` byte length `> SS_CTX_THRESHOLD` (default **8000**).
- **Schema-safe emission:** build `updatedToolOutput` as `(.tool_response | .stdout = $summary)` — start from the ORIGINAL response object and overwrite only `.stdout`, so every other Bash field (`stderr`, `interrupted`, `isImage`, any extras) is preserved and the built-in schema-match cannot fail (a non-matching value is silently ignored by Claude Code).
- **Summary** = first `SS_CTX_HEAD` (30) lines capped to `SS_CTX_HEAD_BYTES` (4000) + a marker line + last `SS_CTX_TAIL` (15) lines capped to `SS_CTX_TAIL_BYTES` (2000). Marker (exact): `[ss-ctx] truncated - <bytes> bytes, <lines> lines total - full: <relpath> - retrieve: /ss-ctx show <id>`.
- **Store:** `${SUPERSTACK_DIR:-.superstack}/ctx/<id>.txt`, `<id>` = `tool_use_id` sanitized via `tr -c 'A-Za-z0-9_-' '_'` (fallback `unknown`). Full original stdout, byte-exact.
- **Env:** `SS_CTX_DISABLE` (off-switch), `SS_CTX_THRESHOLD` (8000), `SS_CTX_HEAD`/`SS_CTX_TAIL` (30/15), `SS_CTX_HEAD_BYTES`/`SS_CTX_TAIL_BYTES` (4000/2000), `SUPERSTACK_DIR`.
- **Hook is bash-only** (no `.ps1` twin — SuperStack hooks run cross-platform via `run-hook.cmd`). The **retrieval script** `scripts/ss-ctx` DOES get a byte-identical `scripts/ss-ctx.ps1` twin (the project's twin law): `LC_ALL=C`/`[StringComparer]::Ordinal`, ASCII, identical stdout. Parity gotchas per the project memory: PS string ops default case-insensitive/culture → use ordinal; pin store mtimes in parity fixtures; mixed-case fixtures.
- Conventional commits, no AI attribution. Skills → **30**. Tests wired as `[15/15]`.

Reference siblings: `hooks/session-start` (bash hook returning JSON on stdout via `run-hook.cmd`), `hooks/hooks.json` (matcher → `run-hook.cmd <name>`), `scripts/ss-context` + `.ps1` (read-only report twin, parity idioms, `$Rest` rejection), `tests/context.test.sh` (capture-first assertions, HOME/store-pinned fixtures). Spec: `docs/specs/2026-06-25-ss-ctx-design.md`.

---

## File Structure

- `hooks/ctx-shrink` — the bash PostToolUse hook (Task 1, verified)
- `hooks/hooks.json` — add a `PostToolUse` `Bash` entry (Task 1)
- `tests/ctx.test.sh` — hook unit tests (Task 1) + retrieval behavior (Task 2) + parity (Task 3)
- `tests/run.sh` — wire `[15/15]` (Task 1)
- `scripts/ss-ctx` — retrieval bash (Task 2)
- `scripts/ss-ctx.ps1` — retrieval PowerShell twin (Task 3)
- `skills/ctx/SKILL.md` — the `/ss-ctx` skill (Task 4)
- `README.md`, `CHANGELOG.md` — surface it (Task 5)

---

## Task 1: `hooks/ctx-shrink` (PostToolUse hook) + tests + wiring

**Model:** sonnet.

**Files:** Create `hooks/ctx-shrink`, `tests/ctx.test.sh`; Modify `hooks/hooks.json`, `tests/run.sh`.

This hook is **author-verified end-to-end** (shrink path, byte-exact offload incl. embedded CRs, all no-op gates, schema-safe emission, long-single-line byte-cap). Transcribe verbatim.

- [ ] **Step 1: Write the failing tests** — create `tests/ctx.test.sh`

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Tests for the ss-ctx shrink hook + the /ss-ctx retrieval twins.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }

if ! command -v jq >/dev/null 2>&1 || ! command -v base64 >/dev/null 2>&1; then
  echo "  SKIP ctx hook (jq/base64 missing)"
else
  HOOK="$ROOT/hooks/ctx-shrink"
  SD="$(mktemp -d)/.superstack"
  big="$(seq 1 600 | sed 's/^/log line number /')"; bb="$(printf '%s' "$big" | wc -c)"
  run(){ printf '%s' "$1" | SUPERSTACK_DIR="$SD" bash "$HOOK" 2>/dev/null; }
  mkpayload(){ jq -n --arg s "$2" --arg t "$1" --arg id "$3" \
    '{tool_name:$t,tool_use_id:$id,tool_response:{stdout:$s,stderr:"",interrupted:false,isImage:false,extra:"keep"}}'; }

  o1="$(run "$(mkpayload Bash "$big" toolu_01ABCdef)")"
  chk "hook emits valid JSON"  'printf "%s" "$o1" | jq -e . >/dev/null'
  chk "marker clean id"        'printf "%s" "$o1" | jq -r ".hookSpecificOutput.updatedToolOutput.stdout" | grep -qE "/ss-ctx show toolu_01ABCdef$"'
  chk "preserves extra field"  '[ "$(printf "%s" "$o1" | jq -r ".hookSpecificOutput.updatedToolOutput.extra")" = "keep" ]'
  chk "preserves stderr/intr/img" '[ "$(printf "%s" "$o1" | jq -r ".hookSpecificOutput.updatedToolOutput|[.stderr,(.interrupted|tostring),(.isImage|tostring)]|join(\",\")")" = ",false,false" ]'
  chk "summary < original"     '[ "$(printf "%s" "$o1" | jq -r ".hookSpecificOutput.updatedToolOutput.stdout" | wc -c)" -lt "$bb" ]'
  chk "offload byte-exact"     '[ "$(wc -c < "$SD/ctx/toolu_01ABCdef.txt")" -eq "$bb" ]'
  chk "offload no spurious CR" '[ "$(tr -cd "\r" < "$SD/ctx/toolu_01ABCdef.txt" | wc -c)" -eq 0 ]'
  chk "no mangled __ filename" '[ -z "$(ls "$SD/ctx" | grep "__")" ]'

  # embedded-CR content (>threshold) must round-trip byte-exact with CRs preserved
  crbig="$(printf 'data line with CR\r\n%.0s' $(seq 1 700))"; cb="$(printf '%s' "$crbig" | wc -c)"; cc="$(printf '%s' "$crbig" | tr -cd '\r' | wc -c)"
  run "$(mkpayload Bash "$crbig" crid)" >/dev/null
  chk "embedded CR byte-exact" '[ "$(wc -c < "$SD/ctx/crid.txt")" -eq "$cb" ] && [ "$(tr -cd "\r" < "$SD/ctx/crid.txt" | wc -c)" -eq "$cc" ]'

  # no-op gates
  chk "under-threshold no-op"  '[ -z "$(run "$(mkpayload Bash "small" t2)")" ]'
  chk "non-Bash no-op"         '[ -z "$(run "$(mkpayload Read "$big" t5)")" ]'
  chk "disabled no-op"         '[ -z "$(printf "%s" "$(mkpayload Bash "$big" t6)" | SS_CTX_DISABLE=1 SUPERSTACK_DIR="$SD" bash "$HOOK" 2>/dev/null)" ]'
  # stderr-present and interrupted (build payloads explicitly, override the clean defaults)
  se="$(jq -n --arg s "$big" '{tool_name:"Bash",tool_use_id:"t3",tool_response:{stdout:$s,stderr:"boom",interrupted:false,isImage:false}}')"
  chk "stderr-present no-op"    '[ -z "$(run "$se")" ]'
  it="$(jq -n --arg s "$big" '{tool_name:"Bash",tool_use_id:"t4",tool_response:{stdout:$s,stderr:"",interrupted:true,isImage:false}}')"
  chk "interrupted no-op"       '[ -z "$(run "$it")" ]'
  # long single line over threshold: bounded summary, byte-exact offload
  huge="$(printf 'x%.0s' $(seq 1 20000))"
  o7="$(run "$(mkpayload Bash "$huge" t7)")"
  chk "1-line blob bounded"    'printf "%s" "$o7" | jq -e . >/dev/null && [ "$(printf "%s" "$o7" | jq -r ".hookSpecificOutput.updatedToolOutput.stdout" | wc -c)" -lt 9000 ] && [ "$(wc -c < "$SD/ctx/t7.txt")" -eq 20000 ]'
fi

echo
[ "$fail" -eq 0 ] && echo "CTX TESTS PASS" || echo "CTX TESTS FAILED"
exit "$fail"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/ctx.test.sh`
Expected: FAIL — `hooks/ctx-shrink` does not exist yet (or SKIP if jq/base64 missing).

- [ ] **Step 3: Write `hooks/ctx-shrink`** (verbatim — author-verified)

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# ss-ctx PostToolUse shrinker (Front 2a): replace oversized clean Bash stdout with a head/tail summary,
# offloading the full output to ${SUPERSTACK_DIR}/ctx/<id>.txt. Fail-safe: any problem -> no-op (exit 0).
set -uo pipefail

[ -n "${SS_CTX_DISABLE:-}" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v base64 >/dev/null 2>&1 || exit 0

input="$(cat)"
[ -n "$input" ] || exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null)" || exit 0
[ "$tool" = "Bash" ] || exit 0

# Only shrink clean, non-interrupted, string-stdout results (never strip errors the agent needs).
gate="$(printf '%s' "$input" | jq -r '
  if (.tool_response | type) != "object" then "skip"
  elif ((.tool_response.stderr // "") | length) > 0 then "skip"
  elif (.tool_response.interrupted // false) == true then "skip"
  elif (.tool_response.stdout | type) != "string" then "skip"
  else "go" end' 2>/dev/null)" || exit 0
[ "$gate" = "go" ] || exit 0

threshold="${SS_CTX_THRESHOLD:-8000}"
head_n="${SS_CTX_HEAD:-30}"; tail_n="${SS_CTX_TAIL:-15}"
hb="${SS_CTX_HEAD_BYTES:-4000}"; tb="${SS_CTX_TAIL_BYTES:-2000}"
dir="${SUPERSTACK_DIR:-.superstack}"; store="$dir/ctx"

raw_id="$(printf '%s' "$input" | jq -r '.tool_use_id // "unknown"' 2>/dev/null)" || exit 0
id="$(printf '%s' "$raw_id" | tr -c 'A-Za-z0-9_-' '_')"   # sanitize clean value (subst already stripped CR/LF)
[ -n "$id" ] || id="unknown"

tmp="$(mktemp)" || exit 0
trap 'rm -f "$tmp"' EXIT
# base64 round-trip: byte-exact stdout regardless of jq's platform text-mode (Windows LF->CRLF). The
# tr -d '\r\n' strips only jq's base64 line-wrapping (the base64 alphabet has no CR/LF), never content.
printf '%s' "$input" | jq -r '.tool_response.stdout | @base64' 2>/dev/null | tr -d '\r\n' | base64 -d > "$tmp" 2>/dev/null || exit 0
bytes="$(wc -c < "$tmp" | tr -d ' ')"
[ "$bytes" -gt "$threshold" ] 2>/dev/null || exit 0

lines="$(wc -l < "$tmp" | tr -d ' ')"
mkdir -p "$store" 2>/dev/null || exit 0
out="$store/$id.txt"
cp "$tmp" "$out" 2>/dev/null || exit 0

head_part="$(head -n "$head_n" "$tmp" | head -c "$hb")"
tail_part="$(tail -n "$tail_n" "$tmp" | tail -c "$tb")"
marker="[ss-ctx] truncated - ${bytes} bytes, ${lines} lines total - full: ${out} - retrieve: /ss-ctx show ${id}"
summary="$(printf '%s\n%s\n%s' "$head_part" "$marker" "$tail_part")"

printf '%s' "$input" | jq --arg s "$summary" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    updatedToolOutput: (.tool_response | .stdout = $s)
  }
}' 2>/dev/null || exit 0
exit 0
```

- [ ] **Step 4: Make it executable and run the tests**

Run: `chmod +x hooks/ctx-shrink && bash tests/ctx.test.sh`
Expected: `CTX TESTS PASS` (or SKIP if jq/base64 absent).

- [ ] **Step 5: Register the hook in `hooks/hooks.json`**

Read `hooks/hooks.json`. Add a `PostToolUse` array (mirroring the existing `PreToolUse` entries' structure) with one entry: matcher `Bash`, command `run-hook.cmd ctx-shrink`. Match the exact JSON shape/quoting the file already uses for `PreToolUse` (same `type`/`command` fields, same `run-hook.cmd <name>` form). If a `PostToolUse` key already exists, append to its array instead of creating a second key.

- [ ] **Step 6: Wire the suite into `tests/run.sh`**

In `tests/run.sh`: change the fourteen labels `[1/14]`…`[14/14]` to `[1/15]`…`[14/15]`. Insert after the `[14/15] context behavior` block (after its closing `fi`, before the final summary):

```bash
echo "[15/15] ctx shrink + retrieval"
if bash "$ROOT/tests/ctx.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - ctx suite"; fail=1
fi
```

- [ ] **Step 7: Run the full suite + lint**

Run: `bash tests/run.sh && bash scripts/lint-skills.sh .` (allow ~450000ms).
Expected: `[1/15]`…`[15/15]` PASS, `ALL TESTS PASS`; lint clean. (A `[1/15]` JSON-lint false alarm in a restricted sandbox is known; the `ctx.test.sh` suite passing is the real signal.)

- [ ] **Step 8: Commit**

```bash
git add hooks/ctx-shrink hooks/hooks.json tests/ctx.test.sh tests/run.sh
git commit -m "feat(ctx): PostToolUse shrink hook for oversized Bash output"
```

---

## Task 2: `scripts/ss-ctx` (retrieval, bash) + tests

**Model:** sonnet.

**Files:** Create `scripts/ss-ctx`; Modify `tests/ctx.test.sh` (append a retrieval block).

**Interfaces:** Reads the store `${SUPERSTACK_DIR:-.superstack}/ctx/<id>.txt` that Task 1's hook fills.

- [ ] **Step 1: Append the failing retrieval tests** to `tests/ctx.test.sh`, before the final `echo`/summary:

```bash
# --- retrieval: scripts/ss-ctx ---
SC="$ROOT/scripts/ss-ctx"
RS="$(mktemp -d)/.superstack"; mkdir -p "$RS/ctx"
printf 'alpha\nNEEDLE here\ngamma\n' > "$RS/ctx/aaa.txt"
printf 'just delta\n' > "$RS/ctx/bbb.txt"
touch -t 202606240000 "$RS/ctx/aaa.txt"; touch -t 202606250000 "$RS/ctx/bbb.txt"   # bbb newer
rc(){ SUPERSTACK_DIR="$RS" bash "$SC" "$@" 2>/dev/null; }
chk "list newest-first"   '[ "$(rc list | awk "{print \$2}" | head -1)" = "bbb" ]'
chk "list shows bytes+id" 'rc list | grep -qE "^[0-9]+ +aaa$"'
chk "show prints content" '[ "$(rc show aaa | sed -n "2p")" = "NEEDLE here" ]'
chk "show byte-exact"     '[ "$(rc show aaa | wc -c)" -eq "$(wc -c < "$RS/ctx/aaa.txt")" ]'
chk "show missing exit 1" 'rc show nope >/dev/null 2>&1; [ "$?" -eq 1 ]'
chk "search finds id"     'rc search NEEDLE | grep -qF "aaa: NEEDLE here"'
chk "search miss message" 'rc search ZZZ | grep -qF "no matches"'
chk "usage exit 2"        'SUPERSTACK_DIR="$RS" bash "$SC" bogus >/dev/null 2>&1; [ "$?" -eq 2 ]'
# prune keeps N newest
for i in $(seq 1 5); do printf 'x\n' > "$RS/ctx/p$i.txt"; touch -t 20260625000$i "$RS/ctx/p$i.txt"; done
rc prune --keep 3 >/dev/null
chk "prune keeps N"       '[ "$(ls "$RS/ctx"/*.txt | wc -l)" -eq 3 ]'
```

- [ ] **Step 2: Run to confirm the retrieval checks fail** — `bash tests/ctx.test.sh` → hook checks PASS, retrieval FAIL (no `scripts/ss-ctx`).

- [ ] **Step 3: Write `scripts/ss-ctx`**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# ss-ctx: read-only access to the PostToolUse shrink store (.superstack/ctx). Front 2a.
# Usage: ss-ctx {list | show <id> | search <term> | prune [--keep N]}
set -uo pipefail
export LC_ALL=C
dir="${SUPERSTACK_DIR:-.superstack}"; store="$dir/ctx"
cmd="${1:-}"
sanitize() { printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '_'; }

case "$cmd" in
  list)
    [ -d "$store" ] || { echo "ss-ctx: store empty ($store)"; exit 0; }
    rows=""; found=0
    for f in "$store"/*.txt; do
      [ -e "$f" ] || continue; found=1
      b="$(wc -c < "$f" | tr -d ' ')"; m="$(date -r "$f" +%s 2>/dev/null || echo 0)"
      n="$(basename "$f" .txt)"; rows="${rows}${m}|${b}|${n}"$'\n'
    done
    [ "$found" = "1" ] || { echo "ss-ctx: store empty ($store)"; exit 0; }
    printf '%s' "$rows" | sort -t'|' -k1,1nr -k3,3 | while IFS='|' read -r m b n; do
      [ -n "$n" ] || continue; printf '%-12s %s\n' "$b" "$n"
    done
    ;;
  show)
    id="$(sanitize "${2:-}")"
    [ -n "$id" ] && [ -n "${2:-}" ] || { echo "ss-ctx: show needs an id" >&2; exit 2; }
    f="$store/$id.txt"
    [ -f "$f" ] || { echo "ss-ctx: no entry '$id'" >&2; exit 1; }
    cat "$f"
    ;;
  search)
    term="${2:-}"
    [ -n "$term" ] || { echo "ss-ctx: search needs a term" >&2; exit 2; }
    [ -d "$store" ] || { echo "ss-ctx: no matches for '$term'"; exit 0; }
    hit=0
    for f in "$store"/*.txt; do
      [ -e "$f" ] || continue; n="$(basename "$f" .txt)"
      matches="$(grep -nF -- "$term" "$f" 2>/dev/null || true)"
      [ -n "$matches" ] || continue
      hit=1; printf '%s' "$matches" | while IFS= read -r ln; do printf '%s: %s\n' "$n" "${ln#*:}"; done
    done
    [ "$hit" = "1" ] || echo "ss-ctx: no matches for '$term'"
    ;;
  prune)
    keep=50
    if [ "${2:-}" = "--keep" ]; then keep="${3:-50}"; fi
    case "$keep" in ''|*[!0-9]*) echo "ss-ctx: --keep needs a number" >&2; exit 2;; esac
    [ -d "$store" ] || { echo "ss-ctx: store empty"; exit 0; }
    rows=""; for f in "$store"/*.txt; do [ -e "$f" ] || continue; rows="${rows}$(date -r "$f" +%s 2>/dev/null || echo 0)|${f}"$'\n'; done
    idx=0
    printf '%s' "$rows" | sort -t'|' -k1,1nr -k2,2 | while IFS='|' read -r m f; do
      [ -n "$f" ] || continue; idx=$((idx+1)); [ "$idx" -le "$keep" ] || rm -f "$f"
    done
    echo "ss-ctx: kept up to $keep newest"
    ;;
  *) echo "usage: ss-ctx {list | show <id> | search <term> | prune [--keep N]}" >&2; exit 2;;
esac
```

Note for the implementer: the `prune` delete runs inside a `sort | while` subshell — that is fine here (the side effect is `rm -f`, not a variable mutation). The `idx` counter is local to the subshell, which is correct because the whole pipeline is one pass.

- [ ] **Step 4: Make executable + run** — `chmod +x scripts/ss-ctx && bash tests/ctx.test.sh` → `CTX TESTS PASS`.

- [ ] **Step 5: Run the full suite** — `bash tests/run.sh` → `[15/15]`, `ALL TESTS PASS`.

- [ ] **Step 6: Commit**

```bash
git add scripts/ss-ctx tests/ctx.test.sh
git commit -m "feat(ctx): /ss-ctx retrieval command (list/show/search/prune)"
```

---

## Task 3: `scripts/ss-ctx.ps1` (PowerShell twin) + parity test

**Model:** sonnet.

**Files:** Create `scripts/ss-ctx.ps1`; Modify `tests/ctx.test.sh` (append a parity block).

**Interfaces:** Byte-identical stdout to `scripts/ss-ctx` for the same store/args.

- [ ] **Step 1: Append the failing parity test** to `tests/ctx.test.sh`, before the final `echo`:

```bash
if command -v pwsh >/dev/null 2>&1; then
  if command -v cygpath >/dev/null 2>&1; then ps1="$(cygpath -w "$ROOT/scripts/ss-ctx.ps1")"; else ps1="$ROOT/scripts/ss-ctx.ps1"; fi
  PS="$(mktemp -d)/.superstack"; mkdir -p "$PS/ctx"
  printf 'alpha\nNEEDLE here\nGamma\n' > "$PS/ctx/aaa.txt"
  printf 'beta\nneedle lower\n' > "$PS/ctx/Bbb.txt"     # mixed case id (ordinal tiebreak)
  printf 'gamma\n' > "$PS/ctx/ccc.txt"
  touch -t 202606240000 "$PS/ctx/aaa.txt"; touch -t 202606240000 "$PS/ctx/Bbb.txt"; touch -t 202606250000 "$PS/ctx/ccc.txt"
  for sub in "list" "show aaa" "search NEEDLE" "search needle"; do
    pb="$(SUPERSTACK_DIR="$PS" bash "$ROOT/scripts/ss-ctx" $sub 2>/dev/null)"
    pp="$(SUPERSTACK_DIR="$PS" pwsh -NoProfile -File "$ps1" $sub 2>/dev/null | tr -d '\r')"
    chk "ps1 parity [$sub]" '[ "$pb" = "$pp" ]'
  done
else
  echo "  SKIP ctx ps1 parity (pwsh not installed)"
fi
```

- [ ] **Step 2: Run to confirm parity fails** — `bash tests/ctx.test.sh` → parity FAIL (no `.ps1`) or SKIP.

- [ ] **Step 3: Write `scripts/ss-ctx.ps1`** — mirror `scripts/ss-ctx` exactly, byte-identical stdout.

```powershell
#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# ss-ctx: read-only access to the PostToolUse shrink store (.superstack/ctx). Front 2a.
param([Parameter(Position=0)][string]$Cmd='', [Parameter(Position=1)][string]$A1='', [Parameter(Position=2)][string]$A2='')
$ErrorActionPreference = 'Stop'
$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
if ($dir -match '^/[a-zA-Z]/') { try { $dir = (& cygpath -w $dir 2>$null).Trim() } catch {} }
$store = Join-Path $dir 'ctx'
function San($s) { ($s -replace '[^A-Za-z0-9_-]','_') }
function Entries { Get-ChildItem -LiteralPath $store -Filter '*.txt' -File -ErrorAction SilentlyContinue }
# Newest-first by mtime (epoch), ordinal id tiebreak. Sort with explicit ordinal comparer keys.
function SortRows($items) {
  $items | Sort-Object @{Expression={[long]([datetimeoffset]$_.LastWriteTimeUtc).ToUnixTimeSeconds()};Descending=$true}, `
                       @{Expression={$_.BaseName};Descending=$false}
  # NOTE: $_.BaseName ties must sort ORDINAL; see Step-3 note for the ordinal-safe variant.
}

switch ($Cmd) {
  'list' {
    if (-not (Test-Path -LiteralPath $store -PathType Container)) { Write-Output "ss-ctx: store empty ($store)"; exit 0 }
    $items = @(Entries); if ($items.Count -eq 0) { Write-Output "ss-ctx: store empty ($store)"; exit 0 }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($f in (SortRows $items)) { $out.Add(('{0,-12} {1}' -f $f.Length, $f.BaseName)) }
    Write-Output ($out -join "`n")
  }
  'show' {
    $id = San $A1
    if (-not $A1 -or -not $id) { [Console]::Error.WriteLine('ss-ctx: show needs an id'); exit 2 }
    $f = Join-Path $store "$id.txt"
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { [Console]::Error.WriteLine("ss-ctx: no entry '$id'"); exit 1 }
    [Console]::Out.Write([System.IO.File]::ReadAllText($f))
  }
  'search' {
    $term = $A1
    if (-not $term) { [Console]::Error.WriteLine('ss-ctx: search needs a term'); exit 2 }
    if (-not (Test-Path -LiteralPath $store -PathType Container)) { Write-Output "ss-ctx: no matches for '$term'"; exit 0 }
    $hit = $false; $out = New-Object System.Collections.Generic.List[string]
    foreach ($f in (Entries | Sort-Object BaseName)) {
      $i = 0
      foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        $i++
        if ($line.IndexOf($term, [System.StringComparison]::Ordinal) -ge 0) { $hit = $true; $out.Add(('{0}: {1}' -f $f.BaseName, $line)) }
      }
    }
    if ($hit) { Write-Output ($out -join "`n") } else { Write-Output "ss-ctx: no matches for '$term'" }
  }
  'prune' {
    $keep = 50
    if ($A1 -eq '--keep') { $keep = $A2 }
    if ($keep -notmatch '^[0-9]+$') { [Console]::Error.WriteLine('ss-ctx: --keep needs a number'); exit 2 }
    $keep = [int]$keep
    if (-not (Test-Path -LiteralPath $store -PathType Container)) { Write-Output 'ss-ctx: store empty'; exit 0 }
    $i = 0
    foreach ($f in (SortRows @(Entries))) { $i++; if ($i -gt $keep) { Remove-Item -LiteralPath $f.FullName -Force } }
    Write-Output "ss-ctx: kept up to $keep newest"
  }
  default { [Console]::Error.WriteLine('usage: ss-ctx {list | show <id> | search <term> | prune [--keep N]}'); exit 2 }
}
```

Parity notes for the implementer (resolve these to achieve byte-identical output — verify against the bash twin, do not guess):
- **Ordinal tiebreak:** `Sort-Object BaseName` is culture/case-aware; bash `sort` under `LC_ALL=C` is ordinal. Replace the `BaseName` sort keys with an ordinal-safe comparison (e.g. project each name through `[System.Text.Encoding]::ASCII`/codepoint ordering, or sort via `[System.Array]::Sort($names,[System.StringComparer]::Ordinal)` and reindex) so a mixed-case fixture (`aaa.txt`, `Bbb.txt`) orders identically to bash (`B`=0x42 sorts before `a`=0x61). The `search` file iteration order also affects output ordering — make it ordinal too.
- **`list` column:** bash `printf '%-12s %s'` ≡ ps1 `'{0,-12} {1}'` (12-wide left-justified bytes, one space, id). `$f.Length` is the byte count for ASCII files (the store is text). Match exactly.
- **`show` is byte-exact:** use `[System.IO.File]::ReadAllText` + `[Console]::Out.Write` (NOT `Get-Content`/`Write-Output`, which re-encode/append a newline) so the bytes match `cat`. The parity test strips `\r` from the pwsh side; ensure no EXTRA trailing newline is added.
- **`search` line numbers:** bash prints `<id>: <line>` (it strips grep's `<lineno>:` prefix via `${ln#*:}`). The ps1 prints `<id>: <line>` directly. Confirm both emit the raw matched line with no line-number prefix, ordinal substring match (`IndexOf(..., Ordinal)` ≡ `grep -F`).
- Mtime sort: both read the SAME store files (the parity fixture seeds one dir), so `LastWriteTimeUtc` epoch == `date -r +%s`. Keep both as integer Unix seconds, descending.

- [ ] **Step 4: Run the parity tests** — `bash tests/ctx.test.sh` → all PASS incl. `ps1 parity [...]` (or SKIP). If a parity case fails, diff `bash scripts/ss-ctx <sub>` vs `pwsh -NoProfile -File scripts/ss-ctx.ps1 <sub> | tr -d '\r'` on the same seeded store; the usual culprit is the ordinal tiebreak or a trailing newline in `show`.

- [ ] **Step 5: Full suite** — `bash tests/run.sh` → `[15/15]`, `ALL TESTS PASS`.

- [ ] **Step 6: Commit**

```bash
git add scripts/ss-ctx.ps1 tests/ctx.test.sh
git commit -m "feat(ctx): PowerShell parity for /ss-ctx retrieval"
```

---

## Task 4: `skills/ctx/SKILL.md`

**Model:** haiku (pure markdown).

**Files:** Create `skills/ctx/SKILL.md`.

- [ ] **Step 1: Write the skill**

```markdown
---
name: ss-ctx
description: Use to keep verbose tool output out of your context window - an always-on PostToolUse hook transparently replaces oversized Bash output with a head/tail summary and offloads the full text to .superstack/ctx/, and /ss-ctx list|show|search|prune retrieves it on demand. Front 2 of SuperStack's context all-rounder (the runtime-output sandbox).
---

# Ctx - keep verbose tool output out of context

Tool results are 49-73% of the tokens in agentic sessions, and verbose `Bash` output (test runs, build
logs, `git log`) is the worst offender. `ss-ctx` is an **always-on** `PostToolUse` hook: when a clean
Bash result is large, it saves the full output to `.superstack/ctx/<id>.txt` and lets you (the agent)
see only a head + tail + a marker. Nothing is lost - the marker tells you the id, and `/ss-ctx show <id>`
returns the full text. It is the runtime-output sandbox rebuilt natively, with zero runtime - just a
bash hook + files. Front 2 of the context all-rounder; the cockpit ([[ss-context]]) reports it as
`runtime sandbox: detected (native)`.

## Steps

1. It runs automatically. When you see a `[ss-ctx] truncated - ... retrieve: /ss-ctx show <id>` marker
   in a Bash result, the full output is on disk under that `<id>`.
2. `scripts/ss-ctx show <id>` (PowerShell: `scripts/ss-ctx.ps1 show <id>`) prints the full saved output.
3. `scripts/ss-ctx search <term>` greps across all saved outputs; `scripts/ss-ctx list` shows recent
   ones (`<bytes> <id>`, newest first); `scripts/ss-ctx prune [--keep N]` trims the store.

## Note

- Only **clean, successful, large** Bash stdout is shrunk - never errors, never interrupted runs, never
  `Read`/`Edit` output (you need those verbatim). The threshold is generous (8000 bytes) so normal
  output passes through untouched.
- Tune or disable via env: `SS_CTX_DISABLE=1` (off), `SS_CTX_THRESHOLD` (bytes), `SS_CTX_HEAD`/
  `SS_CTX_TAIL` (lines kept).
- If you need the whole result inline, retrieve it (`/ss-ctx show <id>`) or re-run the command more
  narrowly - don't fight the summary.
- The store holds raw command output (could include secrets in logs); it shares the `.superstack/`
  trust boundary. `ss-ctx prune` clears it.

## Lineage

Original to SuperStack - Front 2 of the context all-rounder (the runtime-output sandbox, the
context-mode capability rebuilt natively via the `updatedToolOutput` hook primitive). Complements
[[ss-context]] (the standing-context cockpit, Front 1). A later cycle adds an MCP server for sandboxed
execution + FTS5 search over the same store.
```

- [ ] **Step 2: Verify it lints** — `bash scripts/lint-skills.sh .` → PASS, **30 skills**, `[[ss-context]]` resolves, name `ss-ctx`, description 40–500 chars, one H1.

- [ ] **Step 3: Commit**

```bash
git add skills/ctx/SKILL.md
git commit -m "docs(ctx): add /ss-ctx skill"
```

---

## Task 5: README + CHANGELOG

**Model:** haiku (pure markdown).

**Files:** Modify `README.md`, `CHANGELOG.md`.

- [ ] **Step 1: Update the CHANGELOG**

Read `CHANGELOG.md`. Add this bullet to the existing top `## [Unreleased]` → `### Added` group (which already lists `/ss-stats`, `/ss-trace`, `/ss-context`) — do NOT create a second `### Added`, do NOT rename `[Unreleased]`, do NOT touch dated sections:

```markdown
- **`/ss-ctx`:** transparent tool-output shrinker - an always-on `PostToolUse` hook replaces oversized
  clean Bash output with a head/tail summary and offloads the full text to `.superstack/ctx/`;
  `/ss-ctx list|show|search|prune` retrieves it. Zero runtime (bash hook + files). Front 2 of the
  context all-rounder (the runtime-output sandbox). bash + PowerShell. (30 skills.)
```

- [ ] **Step 2: Surface it in the README**

Read `README.md`. Two edits:
1. Add `/ss-ctx` to the **Supporting skills** inline list, right after `/ss-context`. (Inline list only — no new table.)
2. Bump the skills count **29 → 30** in BOTH the badge (`skills-29`) and the prose (`**29 skills, ...**`). Change only the number; if you find a different number, bump that and note it.

- [ ] **Step 3: Verify** — `bash scripts/lint-skills.sh .` → clean, 30 skills.

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: surface /ss-ctx in README + CHANGELOG"
```

---

## Self-Review (completed by plan author)

- **Spec coverage:** transparent shrink via `updatedToolOutput` (T1, verified) · Bash-only + clean-only gates (T1) · byte-exact offload incl. CR preservation (T1, verified) · schema-safe `(.tool_response|.stdout=$s)` emission (T1) · marker + store + env config (T1) · fail-safe no-op incl. missing jq/base64 (T1) · hooks.json registration (T1) · `/ss-ctx list|show|search|prune` (T2) · PowerShell parity (T3) · skill + retrieval playbook + cockpit tie-in (T4) · README 30 + CHANGELOG (T5) · tests→`run.sh [15/15]` (T1–T3). All spec sections map to a task.
- **Placeholder scan:** none — the hook is author-verified verbatim; the retrieval bash + ps1 are complete (the ps1 ordinal-tiebreak is called out as an implementer resolution point with the exact failure it prevents, not a TODO).
- **Consistency:** the marker string, the `updatedToolOutput.stdout` shape, the `<bytes> <id>` list column, the `<id>: <line>` search line, the env var names, and the store path are identical across the hook, the retrieval twins, the tests, and the skill.

---

## Execution Handoff

Recommended: **subagent-driven** — T1 (hook, author-verified) + T2 (retrieval bash) + T3 (ps1 parity) on sonnet (T1 touches a new always-on hook — review the fail-safe no-op paths adversarially; T3's ordinal tiebreak is the parity risk); T4–T5 (markdown) on haiku; per-task spec+quality review; opus whole-branch review at the end (probe: the hook's never-break-a-session guarantee, byte-exact offload across platforms, and cross-twin ordinal/`show`-newline parity).
