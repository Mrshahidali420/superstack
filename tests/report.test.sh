#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavior + parity tests for scripts/ss-report.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; export SUPERSTACK_DIR="$TMP/.superstack"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }

# temp git repo: commit 1 on main (app.sh), commit 2 on feat/x (app.test.sh)
cd "$TMP"
git init -q .
git config user.email t@t; git config user.name t
git checkout -q -b main 2>/dev/null || git branch -m main
printf 'hello\n' > app.sh; git add app.sh; git commit -q -m "init"
git checkout -q -b feat/x
printf 'x\n' > app.test.sh; git add app.test.sh; git commit -q -m "add test"

# seed the ledger for change feat/x (ledger resolves change from the branch)
bash "$ROOT/scripts/ledger" frame  gate pass >/dev/null
bash "$ROOT/scripts/ledger" plan   gate pass >/dev/null
bash "$ROOT/scripts/ledger" build  gate pass >/dev/null
bash "$ROOT/scripts/ledger" review gate pass >/dev/null
bash "$ROOT/scripts/ledger" secure skip skip "no IO" >/dev/null

rep="$(bash "$ROOT/scripts/ss-report")"
chk "heading"  'printf "%s" "$rep" | grep -q "### SuperStack run: feat/x"'
chk "attest"   'printf "%s" "$rep" | grep -q "SuperStack process:"'
chk "phases"   'printf "%s" "$rep" | grep -q "Phases: 4 run, 1 skipped"'
chk "skipped"  'printf "%s" "$rep" | grep -q "Skipped: secure (no IO)"'
chk "change"   'printf "%s" "$rep" | grep -qE "Change: 1 commits, 1 files"'
chk "tests"    'printf "%s" "$rep" | grep -q "1 test files touched"'
chk "save"     'bash "$ROOT/scripts/ss-report" --save >/dev/null 2>&1; [ -f "$SUPERSTACK_DIR/run-report-feat-x.md" ]'
chk "badflag"  '! bash "$ROOT/scripts/ss-report" --nope >/dev/null 2>&1'
chk "empty"    'rm -f "$SUPERSTACK_DIR/ledger.jsonl"; bash "$ROOT/scripts/ss-report" | grep -q "Phases: 0 run, 0 skipped"'

# re-seed the ledger (the "empty" test above removed it), then check bash<->ps1 parity
bash "$ROOT/scripts/ledger" frame  gate pass >/dev/null
bash "$ROOT/scripts/ledger" plan   gate pass >/dev/null
bash "$ROOT/scripts/ledger" build  gate pass >/dev/null
bash "$ROOT/scripts/ledger" review gate pass >/dev/null
bash "$ROOT/scripts/ledger" secure skip skip "no IO" >/dev/null
pb="$(bash "$ROOT/scripts/ss-report" | grep -vE '^Built through the loop')"
PS1_WIN="$(cygpath -w "$ROOT/scripts/ss-report.ps1")"
pp="$(pwsh -NoProfile -File "$PS1_WIN" | tr -d '\r' | grep -vE '^Built through the loop')"
chk "ps1 parity" '[ "$pb" = "$pp" ]'

echo
[ "$fail" -eq 0 ] && echo "REPORT TESTS PASS" || echo "REPORT TESTS FAILED"
exit "$fail"
