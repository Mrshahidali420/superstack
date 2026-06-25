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
