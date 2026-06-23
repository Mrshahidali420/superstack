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
