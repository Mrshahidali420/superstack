#!/usr/bin/env bash
# SuperStack self-test: the skill linter must pass on this repo and must reject a broken skill.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$ROOT/scripts/lint-skills.sh"
fail=0

echo "[1/2] linter passes on the real repo"
if bash "$LINT" "$ROOT" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - the repo should lint clean"; fail=1
fi

echo "[2/2] linter rejects the bad fixture for the right reason"
out="$(bash "$LINT" "$ROOT/tests/fixtures/badroot" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "ss-"; then
  echo "      PASS - rejected: $(printf '%s' "$out" | grep -m1 -i fail)"
else
  echo "      FAIL - bad fixture should have been rejected for a name/ss- reason (rc=$rc)"; fail=1
fi

echo
[ "$fail" -eq 0 ] && echo "ALL TESTS PASS" || echo "TESTS FAILED"
exit "$fail"
