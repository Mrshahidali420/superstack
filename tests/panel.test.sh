#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavior + parity tests for scripts/ss-panel (unified ledger dashboard).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; export SUPERSTACK_DIR="$TMP/.superstack"
CWD="$(mktemp -d)"   # clean cwd: ss-trace must not pick up this repo's specs/commits
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }
mkdir -p "$SUPERSTACK_DIR"
( cd "$CWD" && git init -q . )   # trace expects a repo; an empty one keeps it deterministic

# Two runs. feat/a = older; feat/b = latest.
cat > "$SUPERSTACK_DIR/ledger.jsonl" <<'JSONL'
{"ts":"2026-06-20T10:00:00Z","change":"feat/a","phase":"frame","event":"enter","status":"na","note":""}
{"ts":"2026-06-20T10:03:00Z","change":"feat/a","phase":"plan","event":"gate","status":"pass","note":"spec ok"}
{"ts":"2026-06-21T09:00:00Z","change":"feat/b","phase":"frame","event":"enter","status":"na","note":""}
{"ts":"2026-06-21T09:56:00Z","change":"feat/b","phase":"review","event":"gate","status":"fail","note":"2 findings"}
{"ts":"2026-06-21T10:08:00Z","change":"feat/b","phase":"ship","event":"gate","status":"pass","note":"CI green"}
JSONL

run() { ( cd "$CWD" && bash "$ROOT/scripts/ss-panel" "$@" ); }

out="$(run)"
chk "banner default latest"  'printf "%s" "$out" | grep -qF "ss-panel: feat/b - report + replay + trace"'
chk "report leg present"     'printf "%s" "$out" | grep -qF "### SuperStack run: feat/b"'
chk "replay leg present"     'printf "%s" "$out" | grep -qF "loop replay: feat/b"'
chk "trace leg present"      'printf "%s" "$out" | grep -qF "ss-trace: provenance for feat/b"'
r1="$(printf '%s\n' "$out" | grep -nF '### SuperStack run:' | cut -d: -f1 | head -1)"
r2="$(printf '%s\n' "$out" | grep -nF 'loop replay:' | cut -d: -f1 | head -1)"
r3="$(printf '%s\n' "$out" | grep -nF 'ss-trace: provenance' | cut -d: -f1 | head -1)"
chk "legs in reading order"  '[ -n "$r1" ] && [ -n "$r2" ] && [ -n "$r3" ] && [ "$r1" -lt "$r2" ] && [ "$r2" -lt "$r3" ]'

outa="$(run feat/a)"
chk "explicit change honored"  'printf "%s" "$outa" | grep -qF "ss-panel: feat/a" && printf "%s" "$outa" | grep -qF "spec ok"'
chk "explicit excludes latest" '! printf "%s" "$outa" | grep -qF "CI green"'

# --save mirrors the replay convention (fenced, panel- prefix, / -> -)
fence='```'   # kept in a variable: backticks must never reach chk's eval
( run --save ) >/dev/null 2>&1
first="$(head -1 "$SUPERSTACK_DIR/replays/panel-feat-b.md" 2>/dev/null)"
chk "save writes panel file" '[ -f "$SUPERSTACK_DIR/replays/panel-feat-b.md" ] && grep -qF "ss-panel: feat/b" "$SUPERSTACK_DIR/replays/panel-feat-b.md" && [ "$first" = "$fence" ]'

# usage / missing ledger
( run --bogus ) >/dev/null 2>&1; chk "unknown flag exit 1" '[ "$?" -eq 1 ]'
( SUPERSTACK_DIR="$TMP/none" run ) >/dev/null 2>&1; chk "no ledger exit 1" '[ "$?" -eq 1 ]'

# parity: ps1 twin emits byte-identical panels
if command -v pwsh >/dev/null 2>&1; then
  if command -v cygpath >/dev/null 2>&1; then ps1arg="$(cygpath -w "$ROOT/scripts/ss-panel.ps1")"; else ps1arg="$ROOT/scripts/ss-panel.ps1"; fi
  pp="$(cd "$CWD" && pwsh -NoProfile -File "$ps1arg" | tr -d '\r')"
  chk "ps1 parity (default)"  '[ "$out" = "$pp" ]'
  ppa="$(cd "$CWD" && pwsh -NoProfile -File "$ps1arg" feat/a | tr -d '\r')"
  chk "ps1 parity (explicit)" '[ "$outa" = "$ppa" ]'
else
  echo "  SKIP ps1 parity (pwsh not installed)"
fi

echo
[ "$fail" -eq 0 ] && echo "PANEL TESTS PASS" || echo "PANEL TESTS FAILED"
exit "$fail"
