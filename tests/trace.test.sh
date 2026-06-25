#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavior + parity tests for scripts/ss-trace.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }

# Build a fixture repo: main + feat/demo with fixed-date commits + a seeded ledger + spec docs.
mkfix() {
  local d; d="$(mktemp -d)"
  ( cd "$d" && git init -q && git config user.email a@b.c && git config user.name t && git config core.autocrlf false
    mkdir -p docs/specs .superstack
    printf '# demo\n' > docs/specs/2026-06-25-demo-design.md
    printf '# demo\n' > docs/specs/2026-06-25-demo-plan.md
    printf '# d\n' > docs/specs/2026-06-25-DEMO-extra.md
    printf 'x\n' > f0; git add -A
    GIT_AUTHOR_DATE='2026-06-25T09:00:00Z' GIT_COMMITTER_DATE='2026-06-25T09:00:00Z' git commit -qm 'chore: init'
    git checkout -q -b feat/demo
    printf 'a\n' > f1; git add -A
    GIT_AUTHOR_DATE='2026-06-25T11:00:00Z' GIT_COMMITTER_DATE='2026-06-25T11:00:00Z' git commit -qm 'feat: add f1'
    printf 'b\n' > f2; git add -A
    GIT_AUTHOR_DATE='2026-06-25T12:00:00Z' GIT_COMMITTER_DATE='2026-06-25T12:00:00Z' git commit -qm 'feat: add f2'
    L=.superstack/ledger.jsonl
    printf '{"ts":"2026-06-25T10:30:00Z","change":"feat/demo","phase":"plan","event":"gate","status":"pass","note":""}\n' >> "$L"
    printf '{"ts":"2026-06-25T11:40:00Z","change":"feat/demo","phase":"review","event":"gate","status":"pass","note":"no critical/high"}\n' >> "$L"
    printf '{"ts":"2026-06-25T11:50:00Z","change":"feat/demo","phase":"secure","event":"skip","status":"skip","note":"no IO"}\n' >> "$L"
    printf '{"ts":"2026-06-25T12:30:00Z","change":"feat/demo","phase":"ship","event":"gate","status":"pass","note":""}\n' >> "$L"
    printf '{"ts":"2026-06-24T08:00:00Z","change":"gone","phase":"frame","event":"gate","status":"pass","note":""}\n' >> "$L" )
  printf '%s' "$d"
}
run() { ( cd "$1" && SUPERSTACK_DIR="$1/.superstack" bash "$ROOT/scripts/ss-trace" "${@:2}" ); }

D="$(mkfix)"
out="$(run "$D" feat/demo)"; rc=$?
chk "header"        'printf "%s" "$out" | grep -qF "ss-trace: provenance for feat/demo"'
chk "intent design" 'printf "%s" "$out" | grep -qF "  docs/specs/2026-06-25-demo-design.md"'
chk "intent plan"   'printf "%s" "$out" | grep -qF "  docs/specs/2026-06-25-demo-plan.md"'
chk "intent case-sensitive" '! printf "%s" "$out" | grep -qF "DEMO-extra"'
chk "gate plan"     'printf "%s" "$out" | grep -qE "^  06-25 10:30  plan +PASS"'
chk "skip rendered" 'printf "%s" "$out" | grep -qE "^  06-25 11:50  secure +SKIP +no IO"'
chk "commit f1 mark" 'printf "%s" "$out" | grep -qE "^  06-25 11:00  \* +[0-9a-f]+  feat: add f1"'
# interleave order: plan < f1 < review < secure < f2 < ship
chk "order"  'printf "%s" "$out" | awk "/ plan /{a=NR} / add f1\$/{b=NR} / review /{c=NR} / add f2\$/{d=NR} / ship /{e=NR} END{exit !(a<b && b<c && c<d && d<e)}"'
chk "footer" 'printf "%s" "$out" | grep -qE "^origin: feat/demo   gates: 4   commits: 2   files: 2   head: [0-9a-f]+$"'
chk "exit 0" '[ "$rc" -eq 0 ]'

# no matching docs -> placeholder (trace the 'gone' ledger-only change; slug 'gone' has no docs)
outg="$(run "$D" gone)"
chk "no docs"          'printf "%s" "$outg" | grep -qF "  (no spec/plan docs found)"'
chk "branch not found" 'printf "%s" "$outg" | grep -qF "  (branch '\''gone'\'' not found; git commits omitted)"'
chk "gone ledger row"  'printf "%s" "$outg" | grep -qE "^  06-24 08:00  frame +PASS"'
chk "gone footer"      'printf "%s" "$outg" | grep -qF "origin: gone   gates: 1   commits: 0   files: 0   head: n/a"'

# no trace + usage
outn="$(run "$D" nothing)"
chk "no trace" 'printf "%s" "$outn" | grep -qF "ss-trace: no trace for nothing"'
( run "$D" a b c ) >/dev/null 2>&1; chk "too many args exit 1" '[ "$?" -eq 1 ]'

# parity: read-only, compare bash vs ps1 on the full trace + the branch-not-found case
if command -v pwsh >/dev/null 2>&1; then
  if command -v cygpath >/dev/null 2>&1; then ps1arg="$(cygpath -w "$ROOT/scripts/ss-trace.ps1")"; else ps1arg="$ROOT/scripts/ss-trace.ps1"; fi
  P="$(mkfix)"
  for c in feat/demo gone; do
    pb="$(cd "$P" && SUPERSTACK_DIR="$P/.superstack" bash "$ROOT/scripts/ss-trace" "$c")"
    pp="$(cd "$P" && SUPERSTACK_DIR="$P/.superstack" pwsh -NoProfile -File "$ps1arg" -Change "$c" | tr -d '\r')"
    chk "ps1 parity [$c]" '[ "$pb" = "$pp" ]'
  done
else
  echo "  SKIP ps1 parity (pwsh not installed)"
fi

echo
[ "$fail" -eq 0 ] && echo "TRACE TESTS PASS" || echo "TRACE TESTS FAILED"
exit "$fail"
