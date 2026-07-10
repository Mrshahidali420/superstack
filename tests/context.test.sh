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
over_out="$(run "$D" --budget 1000 || true)"   # capture despite exit 1 (OVER); pipefail-safe
chk "over verdict" 'printf "%s" "$over_out" | grep -qF "verdict: OVER"'
# Capture-first (printf|grep): under `set -o pipefail`, piping `run` into `grep -q` lets grep close
# the pipe on a mid-report match, SIGPIPE-killing ss-context's later writes -> pipefail false-FAIL.
# Capturing the output first (single printf write) avoids the early-close.
# WARN band: budget 4000 -> pct floor((100*2463+2000)/4000)=62 -> WARN (exit 0)
warn_out="$(run "$D" --budget 4000)"
chk "warn verdict" 'printf "%s" "$warn_out" | grep -qF "session-start: ~2463 tokens / 4000 budget (62%)   WARN"'

# --check: silent when OK, one line when over
chk "check silent" '[ -z "$(run "$D" --check)" ]'
adv_out="$(run "$D" --check --budget 1000)"
chk "check advisory" 'printf "%s" "$adv_out" | grep -qE "^\[ss-context\] standing context ~2463 tok = 246% of 1000 budget - review /ss-context \(run /ss-context\)$"'

# detection: cwd .mcp.json (context-mode -> mcp; registered ss-munch -> native)
Dm="$(mkfix)"; printf '{"mcpServers":{"context-mode":{}}}\n' > "$Dm/.mcp.json"
dm_out="$(run "$Dm")"
chk "detect mcp"   'printf "%s" "$dm_out" | grep -qE "^  runtime sandbox +detected +context-mode \(mcp\)$"'
Dn="$(mkfix)"; printf '{"mcpServers":{"ss-munch":{}}}\n' > "$Dn/.mcp.json"
dn_out="$(run "$Dn")"
chk "detect native" 'printf "%s" "$dn_out" | grep -qE "^  code exploration +detected +ss-munch \(native\)$"'
# a stray scripts/ss-munch file is NOT the capability - only the registered server counts
Ds="$(mkfix)"; mkdir -p "$Ds/scripts"; : > "$Ds/scripts/ss-munch"
ds_out="$(run "$Ds")"
chk "stray munch script ignored" 'printf "%s" "$ds_out" | grep -qE "^  code exploration +not detected "'
# routing doctrine row: marker in ./CLAUDE.md -> detected; absent/mixed-case -> not
chk "routing not detected" 'printf "%s" "$out" | grep -qE "^  routing doctrine +not detected +run /ss-init to install the routing block$"'
Dr="$(mkfix)"; printf '%s\n' '<!-- superstack:context-routing -->' >> "$Dr/CLAUDE.md"
dr_out="$(run "$Dr")"
chk "routing detected" 'printf "%s" "$dr_out" | grep -qE "^  routing doctrine +detected +CLAUDE.md \(superstack:context-routing\)$"'
Drc="$(mkfix)"; printf '%s\n' '<!-- SUPERSTACK:CONTEXT-ROUTING -->' >> "$Drc/CLAUDE.md"
drc_out="$(run "$Drc")"
chk "routing mixed-case not detected" 'printf "%s" "$drc_out" | grep -qE "^  routing doctrine +not detected "'

# flags: oversized CLAUDE.md + >1000-line ledger
Df="$(mkfix)"; head -c 20000 /dev/zero | tr '\0' x > "$Df/CLAUDE.md"; yes '{"ts":"t"}' 2>/dev/null | head -1001 > "$Df/.superstack/ledger.jsonl"
df_out="$(run "$Df" --budget 100000)"
chk "flag claude"  'printf "%s" "$df_out" | grep -qF "  ! CLAUDE.md 20000 bytes - trim to stable instructions (it is never evicted)"'
chk "flag ledger"  'printf "%s" "$df_out" | grep -qF "  ! ledger.jsonl 1001 lines - archive old entries"'

# usage
( run "$D" --budget 0 ) >/dev/null 2>&1; chk "budget 0 exit 1" '[ "$?" -eq 1 ]'
( run "$D" --bogus )    >/dev/null 2>&1; chk "bogus exit 1"   '[ "$?" -eq 1 ]'

if command -v pwsh >/dev/null 2>&1; then
  if command -v cygpath >/dev/null 2>&1; then ps1arg="$(cygpath -w "$ROOT/scripts/ss-context.ps1")"; else ps1arg="$ROOT/scripts/ss-context.ps1"; fi
  Dp="$(mkfix)"; Dp2="$(mkfix)"; printf '{"mcpServers":{"context-mode":{}}}\n' > "$Dp2/.mcp.json"
  # full report parity (default budget; detection none) and (with mcp detection)
  for fx in "$Dp" "$Dp2" "$Dn" "$Ds" "$Dr" "$Drc"; do
    pb="$(cd "$fx" && HOME="$HOMEDIR" SUPERSTACK_DIR="$fx/.superstack" bash "$ROOT/scripts/ss-context")"
    pp="$(cd "$fx" && HOME="$HOMEDIR" SUPERSTACK_DIR="$fx/.superstack" pwsh -NoProfile -File "$ps1arg" | tr -d '\r')"
    chk "ps1 parity report [$fx]" '[ "$pb" = "$pp" ]'
  done
  # MIXED-CASE detection regression: bash grep + ps1 Select-String -CaseSensitive must BOTH miss "Context-Mode"
  Dmc="$(mkfix)"; printf '{"mcpServers":{"Context-Mode":{}}}\n' > "$Dmc/.mcp.json"
  mb="$(cd "$Dmc" && HOME="$HOMEDIR" SUPERSTACK_DIR="$Dmc/.superstack" bash "$ROOT/scripts/ss-context")"
  mp="$(cd "$Dmc" && HOME="$HOMEDIR" SUPERSTACK_DIR="$Dmc/.superstack" pwsh -NoProfile -File "$ps1arg" | tr -d '\r')"
  chk "ps1 parity mixed-case detect" '[ "$mb" = "$mp" ]'
  chk "mixed-case not detected (case-sensitive)" 'printf "%s" "$mb" | grep -qE "^  runtime sandbox +not detected"'
  # --check advisory parity (over budget)
  cb="$(cd "$Dp" && HOME="$HOMEDIR" SUPERSTACK_DIR="$Dp/.superstack" bash "$ROOT/scripts/ss-context" --check --budget 1000)"
  cp="$(cd "$Dp" && HOME="$HOMEDIR" SUPERSTACK_DIR="$Dp/.superstack" pwsh -NoProfile -File "$ps1arg" -Check -Budget 1000 | tr -d '\r')"
  chk "ps1 parity --check" '[ "$cb" = "$cp" ]'
else
  echo "  SKIP ps1 parity (pwsh not installed)"
fi

echo
[ "$fail" -eq 0 ] && echo "CONTEXT TESTS PASS" || echo "CONTEXT TESTS FAILED"
exit "$fail"
