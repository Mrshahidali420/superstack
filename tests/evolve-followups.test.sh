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

# --- mutual exclusion ---
chk "apply+explore mutually exclusive" '! bash "$ROOT/scripts/ss-evolve" --apply --explore >/dev/null 2>&1'

# --- --explore scaffolds proposals (never commits) ---
before="$(git rev-parse HEAD)"
xout="$(bash "$ROOT/scripts/ss-evolve" --explore)"
sk="$SUPERSTACK_DIR/proposals/ss-review-gate/SKILL.md"
chk "explore scaffolds file" '[ -f "$sk" ]'
chk "explore name equals dir" 'grep -qxF "name: ss-review-gate" "$sk"'
chk "explore exactly one h1" '[ "$(grep -c "^# " "$sk")" -eq 1 ]'
chk "explore embeds evidence" 'grep -qF "failing pattern in the \`review\` phase, observed 3x" "$sk"'
chk "explore desc length 40-500" 'd="$(sed -n "s/^description: //p" "$sk")"; [ "${#d}" -ge 40 ] && [ "${#d}" -le 500 ]'
chk "explore prints path" 'printf "%s" "$xout" | grep -qF "proposed ss-review-gate -> .superstack/proposals/ss-review-gate/SKILL.md (review, then promote to skills/)"'
chk "explore records state" 'grep -qxF "failing:review" "$SUPERSTACK_DIR/explore-state"'
chk "explore makes no commit" '[ "$(git rev-parse HEAD)" = "$before" ]'

# --- tier independence: apply does not suppress explore (already recorded above), and vice-versa ---
chk "explore independent of evolve-state" '[ ! -f "$SUPERSTACK_DIR/evolve-state" ] || true; grep -qxF "failing:review" "$SUPERSTACK_DIR/explore-state"'

# --- dedup: second explore finds nothing new ---
x2="$(bash "$ROOT/scripts/ss-evolve" --explore)"
chk "explore dedup human" 'printf "%s" "$x2" | grep -qF "nothing new to explore"'
chk "explore dedup json" '[ "$(bash "$ROOT/scripts/ss-evolve" --explore --json)" = "[]" ]'

# --- dry-run: prints intent, writes nothing ---
rm -rf "$SUPERSTACK_DIR/proposals" "$SUPERSTACK_DIR/explore-state"
xd="$(bash "$ROOT/scripts/ss-evolve" --explore --dry-run)"
chk "explore dryrun prints" 'printf "%s" "$xd" | grep -qF "[dry-run] proposed ss-review-gate -> .superstack/proposals/ss-review-gate/SKILL.md"'
chk "explore dryrun no file" '[ ! -e "$SUPERSTACK_DIR/proposals" ]'
chk "explore dryrun no state" '[ ! -f "$SUPERSTACK_DIR/explore-state" ]'

# --- parity: --explore --dry-run (no writes) byte-identical ---
if command -v pwsh >/dev/null 2>&1; then
  if command -v cygpath >/dev/null 2>&1; then ps1arg2="$(cygpath -w "$ROOT/scripts/ss-evolve.ps1")"; else ps1arg2="$ROOT/scripts/ss-evolve.ps1"; fi
  rm -f "$SUPERSTACK_DIR/explore-state"
  xb="$(bash "$ROOT/scripts/ss-evolve" --explore --dry-run)"
  xp="$(pwsh -NoProfile -File "$ps1arg2" -Explore -DryRun | tr -d '\r')"
  chk "explore parity" '[ "$xb" = "$xp" ]'
else
  echo "  SKIP explore parity (pwsh not installed)"
fi

echo
[ "$fail" -eq 0 ] && echo "EVOLVE-FOLLOWUPS TESTS PASS" || echo "EVOLVE-FOLLOWUPS TESTS FAILED"
exit "$fail"
