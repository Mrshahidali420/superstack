#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavior + parity tests for scripts/ss-stats.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }
J() { printf '{"ts":"%s","change":"%s","phase":"%s","event":"%s","status":"%s","note":""}\n' "$1" "$2" "$3" "$4" "$5"; }

# 5-run fixture (deterministic): r1..r5. Returns the dir.
mkfix() {
  local d; d="$(mktemp -d)"; local L="$d/.superstack"; mkdir -p "$L"
  {
    J 2026-06-20T00:00:00Z r1 plan   gate pass
    J 2026-06-20T00:15:00Z r1 build  gate pass
    J 2026-06-20T00:30:00Z r1 review gate fail
    J 2026-06-21T00:00:00Z r2 plan   gate pass
    J 2026-06-21T00:20:00Z r2 build  gate pass
    J 2026-06-22T00:00:00Z r3 plan   gate pass
    J 2026-06-22T00:20:00Z r3 review gate fail
    J 2026-06-22T00:40:00Z r3 secure skip skip
    J 2026-06-23T00:00:00Z r4 plan   gate pass
    J 2026-06-23T00:10:00Z r4 build  gate pass
    J 2026-06-23T00:25:00Z r4 ship   gate pass
    J 2026-06-24T00:00:00Z r5 plan   gate pass
    J 2026-06-24T00:10:00Z r5 plan   note na
  } > "$L/ledger.jsonl"
  printf '%s' "$d"
}

# --- full table + rollup ---
D="$(mkfix)"; export SUPERSTACK_DIR="$D/.superstack"
out="$(bash "$ROOT/scripts/ss-stats")"; rc=$?
chk "runs/window line"  'printf "%s" "$out" | grep -qF "runs: 5   window: all"'
chk "row r5"  'printf "%s" "$out" | grep -qE "^r5 +06-24 +1 +0 +0 +\+10m"'
chk "row r3"  'printf "%s" "$out" | grep -qE "^r3 +06-22 +3 +1 +1 +\+40m"'
chk "row r1"  'printf "%s" "$out" | grep -qE "^r1 +06-20 +3 +1 +0 +\+30m"'
chk "table order r5 before r1" 'printf "%s" "$out" | awk "/^r5 /{a=NR} /^r1 /{b=NR} END{exit !(a&&b&&a<b)}"'
chk "rollup"  'printf "%s" "$out" | grep -qF "gate-fail rate: 18% (2/11)   skips: 1   trend: improving"'
chk "exit 0"  '[ "$rc" -eq 0 ]'

# --- --limit caps table, not rollup ---
outl="$(bash "$ROOT/scripts/ss-stats" --limit 2)"
chk "limit shows r5"     'printf "%s" "$outl" | grep -qE "^r5 "'
chk "limit shows r4"     'printf "%s" "$outl" | grep -qE "^r4 "'
chk "limit hides r3"     '! printf "%s" "$outl" | grep -qE "^r3 "'
chk "limit rollup full"  'printf "%s" "$outl" | grep -qF "gate-fail rate: 18% (2/11)"'

# --- --since drops older runs from table AND rollup; small-n trend n/a ---
outs="$(bash "$ROOT/scripts/ss-stats" --since 2026-06-23)"
chk "since runs 2"     'printf "%s" "$outs" | grep -qF "runs: 2   window: since 2026-06-23"'
chk "since drops r3"   '! printf "%s" "$outs" | grep -qE "^r3 "'
chk "since rate"       'printf "%s" "$outs" | grep -qF "gate-fail rate: 0% (0/4)"'
chk "since trend n/a"  'printf "%s" "$outs" | grep -qF "trend: n/a"'

# --- worsening trend (4-run fixture) ---
W="$(mktemp -d)"; mkdir -p "$W/.superstack"
{ J 2026-06-20T00:00:00Z w1 plan gate pass
  J 2026-06-21T00:00:00Z w2 plan gate pass
  J 2026-06-22T00:00:00Z w3 plan gate fail
  J 2026-06-23T00:00:00Z w4 plan gate fail; } > "$W/.superstack/ledger.jsonl"
export SUPERSTACK_DIR="$W/.superstack"
outw="$(bash "$ROOT/scripts/ss-stats")"
chk "worsening trend" 'printf "%s" "$outw" | grep -qF "trend: worsening"'

# --- empty + bad inputs ---
E="$(mktemp -d)"; export SUPERSTACK_DIR="$E/.superstack"
oute="$(bash "$ROOT/scripts/ss-stats")"; rce=$?
chk "empty no runs yet" 'printf "%s" "$oute" | grep -qF "ss-stats: no runs yet"'
chk "empty exit 0"      '[ "$rce" -eq 0 ]'
export SUPERSTACK_DIR="$D/.superstack"
( bash "$ROOT/scripts/ss-stats" --limit 0 ) >/dev/null 2>&1; chk "limit 0 exit 1" '[ "$?" -eq 1 ]'
( bash "$ROOT/scripts/ss-stats" --limit x ) >/dev/null 2>&1; chk "limit x exit 1" '[ "$?" -eq 1 ]'
( bash "$ROOT/scripts/ss-stats" --bogus ) >/dev/null 2>&1; chk "bad flag exit 1" '[ "$?" -eq 1 ]'
outn="$(bash "$ROOT/scripts/ss-stats" --since 2030-01-01)"
chk "no runs in window" 'printf "%s" "$outn" | grep -qF "ss-stats: no runs in window"'

# parity: read-only, compare a real run on the fixture (full) and with --limit + --since
if command -v pwsh >/dev/null 2>&1; then
  if command -v cygpath >/dev/null 2>&1; then ps1arg="$(cygpath -w "$ROOT/scripts/ss-stats.ps1")"; else ps1arg="$ROOT/scripts/ss-stats.ps1"; fi
  P="$(mkfix)"; export SUPERSTACK_DIR="$P/.superstack"
  for args in "" "--limit 2 --since 2026-06-21"; do
    pb="$(bash "$ROOT/scripts/ss-stats" $args)"
    # translate bash flags to ps1 flags
    ppargs="$(printf '%s' "$args" | sed 's/--limit/-Limit/; s/--since/-Since/')"
    pp="$(pwsh -NoProfile -File "$ps1arg" $ppargs | tr -d '\r')"
    chk "ps1 parity [$args]" '[ "$pb" = "$pp" ]'
  done

  # --- mixed-case parity fixture ---
  # Seeds case-distinct changes + a timestamp tie (Zeta/alpha share first-ts) to exercise
  # both case-sensitive grouping (Finding 1) and ordinal tiebreak sort (Finding 2).
  MC="$(mktemp -d)"; mkdir -p "$MC/.superstack"
  {
    J 2026-06-20T00:00:00Z Mid   plan gate fail
    J 2026-06-21T00:00:00Z mid   plan gate pass
    J 2026-06-22T00:00:00Z Zeta  plan gate pass
    J 2026-06-22T00:00:00Z alpha plan gate pass
  } > "$MC/.superstack/ledger.jsonl"
  export SUPERSTACK_DIR="$MC/.superstack"
  mcb="$(bash "$ROOT/scripts/ss-stats")"
  # (a) bash sees 4 distinct runs (Mid != mid, Zeta != alpha — all case-sensitive)
  chk "mixed-case bash runs 4" 'printf "%s" "$mcb" | grep -qF "runs: 4"'
  # (b) byte-identical output between bash and ps1 (catches grouping + tiebreak bugs)
  mcp="$(pwsh -NoProfile -File "$ps1arg" | tr -d '\r')"
  chk "mixed-case ps1 parity" '[ "$mcb" = "$mcp" ]'
  # (c) unknown arg exits 1
  pwsh -NoProfile -File "$ps1arg" -Bogus >/dev/null 2>&1
  chk "ps1 unknown arg exit 1" '[ "$?" -eq 1 ]'
else
  echo "  SKIP ps1 parity (pwsh not installed)"
fi

echo
[ "$fail" -eq 0 ] && echo "STATS TESTS PASS" || echo "STATS TESTS FAILED"
exit "$fail"
