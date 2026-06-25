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

echo
[ "$fail" -eq 0 ] && echo "CTX TESTS PASS" || echo "CTX TESTS FAILED"
exit "$fail"
