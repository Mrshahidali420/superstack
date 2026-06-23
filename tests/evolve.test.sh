#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavior + parity tests for scripts/ss-evolve.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; export SUPERSTACK_DIR="$TMP/.superstack"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }

cd "$TMP"
git init -q .; git config user.email t@t; git config user.name t
printf 'init\n' > seed.txt; git add seed.txt; git commit -q -m "init"

# seed ledger: 3 secure skips (reason "no IO"), 4 review gate fails, 2 plan skips (below threshold)
for i in 1 2 3; do bash "$ROOT/scripts/ledger" secure skip skip "no IO" >/dev/null; done
for i in 1 2 3 4; do bash "$ROOT/scripts/ledger" review gate fail >/dev/null; done
for i in 1 2; do bash "$ROOT/scripts/ledger" plan skip skip "trivial" >/dev/null; done

j="$(bash "$ROOT/scripts/ss-evolve" --json)"
chk "detect skipped" 'printf "%s" "$j" | jq -e ".[]|select(.id==\"skipped:secure\" and .count==3 and .reason==\"no IO\")" >/dev/null'
chk "detect failing" 'printf "%s" "$j" | jq -e ".[]|select(.id==\"failing:review\" and .count==4)" >/dev/null'
chk "threshold" '! (printf "%s" "$j" | jq -e ".[]|select(.phase==\"plan\")" >/dev/null)'

# --apply: appends to CONTEXT.md, commits, records state
out="$(bash "$ROOT/scripts/ss-evolve" --apply)"
chk "apply context" 'grep -q "is routinely skipped" CONTEXT.md && grep -q "gate often fails" CONTEXT.md'
chk "apply state"   'grep -qxF "skipped:secure" "$SUPERSTACK_DIR/evolve-state" && grep -qxF "failing:review" "$SUPERSTACK_DIR/evolve-state"'
chk "apply commits" '[ "$(git log --oneline --grep="chore(evolve)" | wc -l | tr -d " ")" -ge 2 ]'

# dedup: second apply does nothing new
before="$(git rev-parse HEAD)"
bash "$ROOT/scripts/ss-evolve" --apply >/dev/null
chk "dedup" '[ "$(git rev-parse HEAD)" = "$before" ]'
chk "new-only empty" '[ -z "$(bash "$ROOT/scripts/ss-evolve" --json --new-only | jq -r ".[]" 2>/dev/null)" ]'

# dry-run on fresh state: prints intent, writes nothing
rm -f "$SUPERSTACK_DIR/evolve-state"; git checkout -q -- CONTEXT.md 2>/dev/null || true
d="$(bash "$ROOT/scripts/ss-evolve" --apply --dry-run)"
chk "dryrun prints" 'printf "%s" "$d" | grep -q "dry-run"'
chk "dryrun nowrite" '[ ! -f "$SUPERSTACK_DIR/evolve-state" ]'

echo
[ "$fail" -eq 0 ] && echo "EVOLVE TESTS PASS" || echo "EVOLVE TESTS FAILED"
exit "$fail"
