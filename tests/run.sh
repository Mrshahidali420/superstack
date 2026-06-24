#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SuperStack self-test: the linter passes on this repo, rejects a broken skill, and the hooks
# behave (session-start emits valid JSON; guard-check is inert when disabled).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$ROOT/scripts/lint-skills.sh"
fail=0

echo "[1/8] linter passes on the real repo"
if bash "$LINT" "$ROOT" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - the repo should lint clean"; fail=1
fi

echo "[2/8] linter rejects the bad fixture for the right reason"
out="$(bash "$LINT" "$ROOT/tests/fixtures/badroot" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "ss-"; then
  echo "      PASS - rejected: $(printf '%s' "$out" | grep -m1 -i fail)"
else
  echo "      FAIL - bad fixture should have been rejected for a name/ss- reason (rc=$rc)"; fail=1
fi

echo "[3/8] hooks behave (valid JSON output + guard inert when off)"
if bash "$ROOT/hooks/session-start" 2>/dev/null | jq empty 2>/dev/null \
   && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}' | bash "$ROOT/hooks/guard-check"; then
  echo "      PASS"
else
  echo "      FAIL - session-start must emit valid JSON and guard-check must be inert when disabled"; fail=1
fi

echo "[4/8] ledger + audit behavior"
if bash "$ROOT/tests/ledger.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - ledger/audit suite"; fail=1
fi

echo "[5/8] run-report behavior + parity"
if bash "$ROOT/tests/report.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - run-report suite"; fail=1
fi

echo "[6/8] evolve detection + apply"
if bash "$ROOT/tests/evolve.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - evolve suite"; fail=1
fi

echo "[7/8] evolve follow-ups: --since + --explore"
if bash "$ROOT/tests/evolve-followups.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - evolve follow-ups suite"; fail=1
fi

echo "[8/8] loop replay behavior"
if bash "$ROOT/tests/replay.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - loop replay suite"; fail=1
fi

echo
[ "$fail" -eq 0 ] && echo "ALL TESTS PASS" || echo "TESTS FAILED"
exit "$fail"
