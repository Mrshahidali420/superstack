#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SuperStack self-test: the linter passes on this repo, rejects a broken skill, and the hooks
# behave (session-start emits valid JSON; guard-check is inert when disabled).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$ROOT/scripts/lint-skills.sh"
fail=0

echo "[1/16] linter passes on the real repo"
if bash "$LINT" "$ROOT" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - the repo should lint clean"; fail=1
fi

echo "[2/16] linter rejects the bad fixture for the right reason"
out="$(bash "$LINT" "$ROOT/tests/fixtures/badroot" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "ss-"; then
  echo "      PASS - rejected: $(printf '%s' "$out" | grep -m1 -i fail)"
else
  echo "      FAIL - bad fixture should have been rejected for a name/ss- reason (rc=$rc)"; fail=1
fi

echo "[3/16] hooks behave (valid JSON output + guard inert when off)"
if bash "$ROOT/hooks/session-start" 2>/dev/null | jq empty 2>/dev/null \
   && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}' | bash "$ROOT/hooks/guard-check"; then
  echo "      PASS"
else
  echo "      FAIL - session-start must emit valid JSON and guard-check must be inert when disabled"; fail=1
fi

# context advisory: present when over budget, absent when OK; JSON stays valid both ways.
ctxfix_over="$(mktemp -d)"; head -c 40000 /dev/zero | tr '\0' x > "$ctxfix_over/CLAUDE.md"   # ~10000 tok > 8000
ctxfix_ok="$(mktemp -d)";   head -c 400   /dev/zero | tr '\0' x > "$ctxfix_ok/CLAUDE.md"
over_out="$(cd "$ctxfix_over" && bash "$ROOT/hooks/session-start" 2>/dev/null)"
ok_out="$(cd "$ctxfix_ok"   && bash "$ROOT/hooks/session-start" 2>/dev/null)"
if printf '%s' "$over_out" | grep -qF '[ss-context]'; then echo "      PASS hook advisory present (over budget)"; else echo "      FAIL hook advisory missing"; fail=1; fi
if printf '%s' "$ok_out" | grep -qF '[ss-context]'; then echo "      FAIL hook advisory leaked (ok budget)"; fail=1; else echo "      PASS hook advisory silent (ok budget)"; fi
if printf '%s' "$over_out" | jq -e . >/dev/null 2>&1; then echo "      PASS hook JSON valid"; else echo "      FAIL hook JSON invalid"; fail=1; fi

echo "[4/16] ledger + audit behavior"
if bash "$ROOT/tests/ledger.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - ledger/audit suite"; fail=1
fi

echo "[5/16] run-report behavior + parity"
if bash "$ROOT/tests/report.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - run-report suite"; fail=1
fi

echo "[6/16] evolve detection + apply"
if bash "$ROOT/tests/evolve.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - evolve suite"; fail=1
fi

echo "[7/16] evolve follow-ups: --since + --explore"
if bash "$ROOT/tests/evolve-followups.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - evolve follow-ups suite"; fail=1
fi

echo "[8/16] loop replay behavior"
if bash "$ROOT/tests/replay.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - loop replay suite"; fail=1
fi

echo "[9/16] init behavior"
if bash "$ROOT/tests/init.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - init suite"; fail=1
fi

echo "[10/16] doctor behavior"
if bash "$ROOT/tests/doctor.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - doctor suite"; fail=1
fi

echo "[11/16] drift behavior"
if bash "$ROOT/tests/drift.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - drift suite"; fail=1
fi

echo "[12/16] stats behavior"
if bash "$ROOT/tests/stats.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - stats suite"; fail=1
fi

echo "[13/16] trace behavior"
if bash "$ROOT/tests/trace.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - trace suite"; fail=1
fi

echo "[14/16] context behavior"
if bash "$ROOT/tests/context.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - context suite"; fail=1
fi

echo "[15/16] ctx shrink + retrieval"
if bash "$ROOT/tests/ctx.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - ctx suite"; fail=1
fi

echo "[16/16] ctx-mcp server"
if bash "$ROOT/tests/ctx-mcp.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - ctx-mcp suite"; fail=1
fi

echo
[ "$fail" -eq 0 ] && echo "ALL TESTS PASS" || echo "TESTS FAILED"
exit "$fail"
