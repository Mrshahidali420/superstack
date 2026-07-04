#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavioral tests for the ss-munch MCP server (drives it via piped JSON-RPC over stdio).
# Paths passed to the server are repo-relative; the server runs with cwd=$ROOT so they
# resolve (Node existsSync cannot resolve Git-Bash /c/... absolutes on Windows).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }

if ! command -v node >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "  SKIP munch (node/jq missing)"
else
  SRV="$ROOT/mcp/munch/server.mjs"
  node --check "$SRV" || fail=1
  node --check "$ROOT/mcp/munch/extract.mjs" || fail=1

  INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}'
  # drive(): feed INIT + the given JSON-RPC lines, capture all response lines (cwd=$ROOT)
  drive() { { printf '%s\n' "$INIT"; printf '%s\n' "$@"; } | timeout 60 node "$SRV" 2>/dev/null; }
  rid() { printf '%s\n' "$1" | jq -c "select(.id==$2)"; }
  txt() { rid "$1" "$2" | jq -r '.result.content[0].text'; }

  # --- protocol ---
  O="$(drive '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' '{"jsonrpc":"2.0","id":3,"method":"ping"}')"
  chk "init serverInfo ss-munch" '[ "$(rid "$O" 1 | jq -r ".result.serverInfo.name")" = "ss-munch" ] && [ "$(rid "$O" 1 | jq -r ".result.capabilities.tools|type")" = "object" ]'
  chk "init echoes protocol"     '[ "$(rid "$O" 1 | jq -r ".result.protocolVersion")" = "2025-06-18" ]'
  chk "tools/list = 3"           '[ "$(rid "$O" 2 | jq -r ".result.tools|length")" = "3" ]'
  chk "tool names"               '[ "$(rid "$O" 2 | jq -rc "[.result.tools[].name]|sort|join(\",\")")" = "munch_outline,munch_search,munch_symbol" ]'
  chk "ping empty result"        '[ "$(rid "$O" 3 | jq -c ".result")" = "{}" ]'

  # --- munch_outline (JS: function / arrow / class / method) ---
  A="$(drive '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"munch_outline","arguments":{"file":"tests/fixtures/munch/calc.js"}}}')"
  chk "outline js symbols" 'T="$(txt "$A" 4)"; printf "%s" "$T" | grep -q "function  alpha" && printf "%s" "$T" | grep -q "function  beta" && printf "%s" "$T" | grep -q "class  Gamma" && printf "%s" "$T" | grep -q "method  doThing"'

  # --- cross-language outline (Python, Go) ---
  P="$(drive '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"munch_outline","arguments":{"file":"tests/fixtures/munch/util.py"}}}' '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"munch_outline","arguments":{"file":"tests/fixtures/munch/main.go"}}}')"
  chk "outline python" 'printf "%s" "$(txt "$P" 5)" | grep -q "function  do_thing" && printf "%s" "$(txt "$P" 5)" | grep -q "class  Gamma"'
  chk "outline go"     'printf "%s" "$(txt "$P" 6)" | grep -q "function  Alpha" && printf "%s" "$(txt "$P" 6)" | grep -q "method  Area"'

  # --- munch_symbol exact body + prefix ---
  S="$(drive '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"munch_symbol","arguments":{"file":"tests/fixtures/munch/util.py","name":"do_thing"}}}')"
  chk "symbol prefix line" 'printf "%s" "$(txt "$S" 7)" | head -1 | grep -qE "^# tests/fixtures/munch/util.py:[0-9]+-[0-9]+$"'
  chk "symbol body"        'printf "%s" "$(txt "$S" 7)" | grep -qF "def do_thing(self):"'

  # --- munch_search across git-tracked fixtures (alpha is in calc.js + util.py + lib.rs) ---
  H="$(drive '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"munch_search","arguments":{"name":"alpha","path":"tests/fixtures/munch"}}}')"
  chk "search finds js"  'printf "%s" "$(txt "$H" 8)" | grep -qE "calc.js:[0-9]+  function  alpha"'
  chk "search finds py"  'printf "%s" "$(txt "$H" 8)" | grep -qE "util.py:[0-9]+  function  alpha"'

  # --- error paths ---
  E="$(drive '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"munch_outline","arguments":{"file":"tests/fixtures/munch/README.txt"}}}' '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"munch_symbol","arguments":{"file":"tests/fixtures/munch/calc.js","name":"nope"}}}')"
  chk "unsupported ext"   'printf "%s" "$(txt "$E" 9)" | grep -qF "unsupported file type"'
  chk "symbol not found"  'printf "%s" "$(txt "$E" 10)" | grep -qF "not found in" && printf "%s" "$(txt "$E" 10)" | grep -qF "munch_outline"'

  # --- unknown tool -> isError; unknown method -> -32601; notifications -> no output ---
  U="$(drive '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"nope","arguments":{}}}')"
  chk "unknown tool isError" '[ "$(rid "$U" 11 | jq -r ".result.isError")" = "true" ]'
  M="$(drive '{"jsonrpc":"2.0","id":12,"method":"bogus/method"}')"
  chk "unknown method -32601" '[ "$(rid "$M" 12 | jq -r ".error.code")" = "-32601" ]'
  N="$(drive '{"jsonrpc":"2.0","method":"notifications/initialized"}' '{"jsonrpc":"2.0","method":"notifications/whatever"}')"
  chk "notifications no output" '[ "$(printf "%s\n" "$N" | grep -c .)" -eq 1 ]'
fi

echo
[ "$fail" -eq 0 ] && echo "MUNCH TESTS PASS" || echo "MUNCH TESTS FAILED"
exit "$fail"
