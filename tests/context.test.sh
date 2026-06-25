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
