#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavior + parity tests for ss-evolve --since and --explore (v0.4.0 follow-ups).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; export SUPERSTACK_DIR="$TMP/.superstack"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }

cd "$TMP"
git init -q .; git config user.email t@t; git config user.name t
printf 'init\n' > seed.txt; git add seed.txt; git commit -q -m init
mkdir -p "$SUPERSTACK_DIR"

# Seed ledger with explicit timestamps: 3 OLD secure skips (May), 3 NEW review gate fails (June).
cat > "$SUPERSTACK_DIR/ledger.jsonl" <<'JSONL'
{"ts":"2026-05-01T00:00:00Z","change":"x","phase":"secure","event":"skip","status":"skip","note":"no IO"}
{"ts":"2026-05-01T00:00:01Z","change":"x","phase":"secure","event":"skip","status":"skip","note":"no IO"}
{"ts":"2026-05-01T00:00:02Z","change":"x","phase":"secure","event":"skip","status":"skip","note":"no IO"}
{"ts":"2026-06-10T00:00:00Z","change":"x","phase":"review","event":"gate","status":"fail","note":""}
{"ts":"2026-06-10T00:00:01Z","change":"x","phase":"review","event":"gate","status":"fail","note":""}
{"ts":"2026-06-10T00:00:02Z","change":"x","phase":"review","event":"gate","status":"fail","note":""}
JSONL

# --- --since ---
all="$(bash "$ROOT/scripts/ss-evolve" --json)"
chk "baseline both findings" 'printf "%s" "$all" | jq -e ".[]|select(.id==\"skipped:secure\")" >/dev/null && printf "%s" "$all" | jq -e ".[]|select(.id==\"failing:review\")" >/dev/null'
js="$(bash "$ROOT/scripts/ss-evolve" --since 2026-06-01 --json)"
chk "since drops old" '! (printf "%s" "$js" | jq -e ".[]|select(.phase==\"secure\")" >/dev/null)'
chk "since keeps new" 'printf "%s" "$js" | jq -e ".[]|select(.id==\"failing:review\" and .count==3)" >/dev/null'
chk "since bad value errors" '! bash "$ROOT/scripts/ss-evolve" --since nonsense >/dev/null 2>&1'
chk "since missing value errors" '! bash "$ROOT/scripts/ss-evolve" --since >/dev/null 2>&1'

# --- parity: --since (read-only) ---
if command -v pwsh >/dev/null 2>&1; then
  if command -v cygpath >/dev/null 2>&1; then ps1arg="$(cygpath -w "$ROOT/scripts/ss-evolve.ps1")"; winsd="$(cygpath -w "$SUPERSTACK_DIR")"; else ps1arg="$ROOT/scripts/ss-evolve.ps1"; winsd="$SUPERSTACK_DIR"; fi
  sb="$(bash "$ROOT/scripts/ss-evolve" --since 2026-06-01)"
  sp="$(SUPERSTACK_DIR="$winsd" pwsh -NoProfile -File "$ps1arg" -Since 2026-06-01 | tr -d '\r')"
  chk "since parity" '[ "$sb" = "$sp" ]'
else
  echo "  SKIP since parity (pwsh not installed)"
fi

echo
[ "$fail" -eq 0 ] && echo "EVOLVE-FOLLOWUPS TESTS PASS" || echo "EVOLVE-FOLLOWUPS TESTS FAILED"
exit "$fail"
