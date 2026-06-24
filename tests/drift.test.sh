#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavior + parity tests for scripts/ss-drift.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }

# mkbase: a git repo with a plan (declaring scripts/a, scripts/b, tests/c) committed. Echoes the dir.
mkbase() {
  local t; t="$(mktemp -d)"
  ( cd "$t" && git init -q . && git config user.email t@t && git config user.name t
    mkdir -p docs/specs
    cat > docs/specs/p-plan.md <<'PLAN'
# P Plan
### Task 1: X
**Files:**
- Create: `scripts/a`
- Create: `scripts/b`
- Modify: `tests/c:10-20` (with annotation)

**Interfaces:**
- Consumes: `scripts/ignore-me`
PLAN
    git add -A && git commit -qm base )
  printf '%s' "$t"
}

# --- drift detected ---
T="$(mkbase)"; base="$(cd "$T" && git rev-parse HEAD)"
( cd "$T" && mkdir -p scripts tests && printf 'a\n'>scripts/a; printf 'b\n'>scripts/b; printf 'd\n'>scripts/d && git add -A && git commit -qm work )
out="$(cd "$T" && bash "$ROOT/scripts/ss-drift" docs/specs/p-plan.md "$base")"; rc=$?
chk "drift counts"        'printf "%s" "$out" | grep -qE "declared: 3   changed: 3   unplanned: 1   untouched: 1"'
chk "drift unplanned d"   'printf "%s" "$out" | grep -qF "  + scripts/d"'
chk "drift untouched c"   'printf "%s" "$out" | grep -qF "  - tests/c"'    # also proves :10-20 + annotation stripped
chk "interfaces ignored"  '! printf "%s" "$out" | grep -qF "scripts/ignore-me"'
chk "drift verdict"       'printf "%s" "$out" | grep -qF "verdict: DRIFT"'
chk "drift exit 1"        '[ "$rc" -eq 1 ]'

# --- clean: HEAD changes exactly the declared set ---
T2="$(mkbase)"; base2="$(cd "$T2" && git rev-parse HEAD)"
( cd "$T2" && mkdir -p scripts tests && printf 'a\n'>scripts/a; printf 'b\n'>scripts/b; printf 'c\n'>tests/c && git add -A && git commit -qm work )
out2="$(cd "$T2" && bash "$ROOT/scripts/ss-drift" docs/specs/p-plan.md "$base2")"; rc2=$?
chk "clean counts"   'printf "%s" "$out2" | grep -qE "declared: 3   changed: 3   unplanned: 0   untouched: 0"'
chk "clean verdict"  'printf "%s" "$out2" | grep -qF "verdict: CLEAN"'
chk "clean exit 0"   '[ "$rc2" -eq 0 ]'
chk "clean no lists" '! printf "%s" "$out2" | grep -qF "unplanned changes"'

# --- docs/specs excluded + uncommitted unplanned counted ---
T3="$(mkbase)"; base3="$(cd "$T3" && git rev-parse HEAD)"
( cd "$T3" && mkdir -p scripts && printf 'a\n'>scripts/a && git add -A && git commit -qm work
  printf '\n<!-- edit -->\n' >> docs/specs/p-plan.md
  printf 'x\n' > scripts/uncommitted-extra )
out3="$(cd "$T3" && bash "$ROOT/scripts/ss-drift" docs/specs/p-plan.md "$base3")"
chk "docs/specs excluded"      '! printf "%s" "$out3" | grep -qF "docs/specs/p-plan.md"'
chk "uncommitted unplanned"    'printf "%s" "$out3" | grep -qF "  + scripts/uncommitted-extra"'

# --- bad inputs -> exit 2 ---
T4="$(mkbase)"
( cd "$T4" && bash "$ROOT/scripts/ss-drift" docs/specs/NOPE.md ) >/dev/null 2>&1; rc4=$?
chk "missing plan exit 2" '[ "$rc4" -eq 2 ]'
( cd "$T4" && bash "$ROOT/scripts/ss-drift" docs/specs/p-plan.md no-such-ref ) >/dev/null 2>&1; rc4b=$?
chk "bad base exit 2" '[ "$rc4b" -eq 2 ]'
T4c="$(mktemp -d)"; printf '**Files:**\n- Create: `x`\n' > "$T4c/p.md"
( cd "$T4c" && bash "$ROOT/scripts/ss-drift" p.md ) >/dev/null 2>&1; rc4c=$?
chk "not-a-git exit 2" '[ "$rc4c" -eq 2 ]'

# parity: read-only, so compare a real run on a drift fixture with multi-item lists
if command -v pwsh >/dev/null 2>&1; then
  if command -v cygpath >/dev/null 2>&1; then ps1arg="$(cygpath -w "$ROOT/scripts/ss-drift.ps1")"; else ps1arg="$ROOT/scripts/ss-drift.ps1"; fi
  T5="$(mkbase)"; base5="$(cd "$T5" && git rev-parse HEAD)"
  ( cd "$T5" && mkdir -p scripts tests && printf 'a\n'>scripts/a; printf 'b\n'>scripts/b; printf 'd\n'>scripts/d; printf 'r\n'>README-extra && git add -A && git commit -qm work )
  pb="$(cd "$T5" && bash "$ROOT/scripts/ss-drift" docs/specs/p-plan.md "$base5")"
  pp="$(cd "$T5" && pwsh -NoProfile -File "$ps1arg" docs/specs/p-plan.md "$base5" | tr -d '\r')"
  chk "ps1 parity (drift)" '[ "$pb" = "$pp" ]'
else
  echo "  SKIP ps1 parity (pwsh not installed)"
fi

echo
[ "$fail" -eq 0 ] && echo "DRIFT TESTS PASS" || echo "DRIFT TESTS FAILED"
exit "$fail"
