#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavioral tests for the ss-ctx MCP server (drives it via piped JSON-RPC over stdio).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }

if ! command -v node >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "  SKIP ctx-mcp (node/jq missing)"
else
  SRV="$ROOT/mcp/server.mjs"
  node --check "$SRV" || fail=1
  SD="$(mktemp -d)/.superstack"; mkdir -p "$SD/ctx"
  printf 'alpha\nNEEDLE here\ngamma\n' > "$SD/ctx/seed1.txt"
  INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}'
  # drive(): feed INIT + the given JSON-RPC lines, capture all response lines
  drive() { { printf '%s\n' "$INIT"; printf '%s\n' "$@"; } | timeout 40 env SUPERSTACK_DIR="$SD" node "$SRV" 2>/dev/null; }
  rid() { printf '%s\n' "$1" | jq -c "select(.id==$2)"; }   # extract response by id
  txt() { rid "$1" "$2" | jq -r '.result.content[0].text'; }

  O="$(drive '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' '{"jsonrpc":"2.0","id":3,"method":"ping"}')"
  chk "init echoes protocol"  '[ "$(rid "$O" 1 | jq -r ".result.protocolVersion")" = "2025-06-18" ]'
  chk "init tools capability" '[ "$(rid "$O" 1 | jq -r ".result.capabilities.tools|type")" = "object" ] && [ "$(rid "$O" 1 | jq -r ".result.serverInfo.name")" = "ss-ctx" ]'
  chk "tools/list = 5"        '[ "$(rid "$O" 2 | jq -r ".result.tools|length")" = "5" ]'
  chk "tool names"            '[ "$(rid "$O" 2 | jq -rc "[.result.tools[].name]|sort|join(\",\")")" = "ctx_batch_execute,ctx_execute,ctx_fetch_and_index,ctx_search,ctx_show" ]'
  chk "ping empty result"     '[ "$(rid "$O" 3 | jq -c ".result")" = "{}" ]'

  # ctx_execute: small (full) vs large (summary+marker, byte-exact store)
  S="$(drive '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"ctx_execute","arguments":{"command":"seq 1 100"}}}' '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"ctx_execute","arguments":{"command":"seq 1 4000"}}}')"
  chk "execute small no marker" 'M="$(txt "$S" 4)"; printf "%s" "$M" | grep -q "100" && ! printf "%s" "$M" | grep -q "ss-ctx] truncated"'
  big="$(txt "$S" 5)"
  chk "execute large has marker" 'printf "%s" "$big" | grep -qF "[ss-ctx] truncated"'
  bid="$(printf "%s\n" "$big" | sed -n "1s/^id: //p")"
  chk "execute large stored byte-exact" '[ "$(wc -c < "$SD/ctx/$bid.txt")" -eq "$(seq 1 4000 | wc -c)" ]'
  chk "execute marker forward-slash path" 'printf "%s" "$big" | grep -qE "full: [^ ]*/ctx/$bid.txt "'

  # stderr + exit capture
  E="$(drive '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"ctx_execute","arguments":{"command":"echo out; echo err >&2; exit 3"}}}')"
  chk "execute captures exit+stderr" 'printf "%s" "$(txt "$E" 6)" | grep -q "exit: 3" && printf "%s" "$(txt "$E" 6)" | grep -q "err"'

  # batch
  B="$(drive '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"ctx_batch_execute","arguments":{"commands":["echo hi","echo bye"]}}}')"
  chk "batch two blocks" '[ "$(printf "%s\n" "$(txt "$B" 7)" | grep -c "^### ")" -eq 2 ]'

  # search hit + miss
  H="$(drive '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"ctx_search","arguments":{"query":"NEEDLE"}}}' '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"ctx_search","arguments":{"query":"ZZZNOPE"}}}')"
  chk "search hit"  'printf "%s" "$(txt "$H" 8)" | grep -qF "seed1: NEEDLE here"'
  chk "search miss" 'printf "%s" "$(txt "$H" 9)" | grep -qF "no matches for"'

  # show byte-exact + missing
  W="$(drive '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"ctx_show","arguments":{"id":"seed1"}}}' '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"ctx_show","arguments":{"id":"nope"}}}')"
  chk "show byte-exact" '[ "$(txt "$W" 10 | sed -n "2p")" = "NEEDLE here" ]'
  chk "show missing"    'printf "%s" "$(txt "$W" 11)" | grep -qF "no entry"'

  # fetch_and_index against a data: URL (offline, deterministic HTML->text)
  DURL="data:text/html,<h1>Title</h1><p>Hello%20%26%20world</p><ul><li>one</li><li>two</li></ul>"
  F="$(drive "$(jq -nc --arg u "$DURL" '{jsonrpc:"2.0",id:12,method:"tools/call",params:{name:"ctx_fetch_and_index",arguments:{url:$u}}}')")"
  chk "fetch status 200"  'printf "%s" "$(txt "$F" 12)" | grep -q "status: 200"'
  chk "fetch html->md"    'printf "%s" "$(txt "$F" 12)" | grep -qF "# Title" && printf "%s" "$(txt "$F" 12)" | grep -qF -- "- one"'

  # unknown tool -> isError
  U="$(drive '{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"nope","arguments":{}}}')"
  chk "unknown tool isError" '[ "$(rid "$U" 13 | jq -r ".result.isError")" = "true" ]'

  # unknown METHOD (with id) -> JSON-RPC error -32601
  M="$(drive '{"jsonrpc":"2.0","id":14,"method":"bogus/method"}')"
  chk "unknown method -32601" '[ "$(rid "$M" 14 | jq -r ".error.code")" = "-32601" ]'

  # a notification (no id) and an unknown notification produce NO response (only the init reply)
  N="$(drive '{"jsonrpc":"2.0","method":"notifications/initialized"}' '{"jsonrpc":"2.0","method":"notifications/whatever"}')"
  chk "notifications no output" '[ "$(printf "%s\n" "$N" | grep -c .)" -eq 1 ]'
fi

echo
[ "$fail" -eq 0 ] && echo "CTX-MCP TESTS PASS" || echo "CTX-MCP TESTS FAILED"
exit "$fail"
