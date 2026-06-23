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


# ss-audit: incomplete (only review recorded so far) -> exit 1
chk "audit incomplete" '! bash "$ROOT/scripts/ss-audit" >/dev/null 2>&1'
# add secure pass -> complete -> exit 0
bash "$ROOT/scripts/ledger" secure gate pass "clean" >/dev/null
chk "audit complete via pass" 'bash "$ROOT/scripts/ss-audit" >/dev/null 2>&1'
# fresh change where secure is explicitly skipped -> still complete
printf '{"ts":"t","change":"br2","phase":"review","event":"gate","status":"pass","note":""}\n'  >> "$SUPERSTACK_DIR/ledger.jsonl"
printf '{"ts":"t","change":"br2","phase":"secure","event":"skip","status":"skip","note":"no IO"}\n' >> "$SUPERSTACK_DIR/ledger.jsonl"
chk "audit complete via skip" 'bash "$ROOT/scripts/ss-audit" br2 >/dev/null 2>&1'
# attestation line contains a tick
chk "audit attest" 'bash "$ROOT/scripts/ss-audit" --attest | grep -q "SuperStack process:"'

# audit-check inert when SUPERSTACK_AUDIT unset
chk "hook inert" 'printf "%s" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push\"}}" | bash "$ROOT/hooks/audit-check"'

echo
[ "$fail" -eq 0 ] && echo "LEDGER TESTS PASS" || echo "LEDGER TESTS FAILED"
exit "$fail"
