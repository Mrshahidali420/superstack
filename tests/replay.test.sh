#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavior + parity tests for scripts/ss-replay (loop replay).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; export SUPERSTACK_DIR="$TMP/.superstack"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }
mkdir -p "$SUPERSTACK_DIR"

# Two runs. feat/a = older; feat/b = latest. Fixed timestamps -> deterministic elapsed.
cat > "$SUPERSTACK_DIR/ledger.jsonl" <<'JSONL'
{"ts":"2026-06-20T10:00:00Z","change":"feat/a","phase":"frame","event":"enter","status":"na","note":""}
{"ts":"2026-06-20T10:03:00Z","change":"feat/a","phase":"plan","event":"gate","status":"pass","note":"spec ok"}
{"ts":"2026-06-21T09:00:00Z","change":"feat/b","phase":"frame","event":"enter","status":"na","note":""}
{"ts":"2026-06-21T09:29:00Z","change":"feat/b","phase":"build","event":"enter","status":"na","note":""}
{"ts":"2026-06-21T09:56:00Z","change":"feat/b","phase":"review","event":"gate","status":"fail","note":"2 findings"}
{"ts":"2026-06-21T10:08:00Z","change":"feat/b","phase":"review","event":"gate","status":"pass","note":"fixed"}
{"ts":"2026-06-21T10:10:00Z","change":"feat/b","phase":"ship","event":"gate","status":"pass","note":"CI green"}
{"ts":"2026-06-21T10:10:00Z","change":"feat/b","phase":"secure","event":"skip","status":"skip","note":"no IO"}
JSONL

out="$(bash "$ROOT/scripts/ss-replay")"
# default = latest run (feat/b), not feat/a
chk "default picks latest run" 'printf "%s" "$out" | grep -qF "loop replay: feat/b"'
chk "default excludes older run" '! (printf "%s" "$out" | grep -qF "spec ok")'
# elapsed column (minutes-only)
chk "elapsed +0m" 'printf "%s" "$out" | grep -qE "\+0m +frame +enter"'
chk "elapsed +29m" 'printf "%s" "$out" | grep -qE "\+29m +build +enter"'
chk "elapsed +68m" 'printf "%s" "$out" | grep -qE "\+68m +review +gate +PASS"'
# blank marker: enter rows must end at the event token (no stray retry-bit)
chk "frame enter blank marker" 'printf "%s" "$out" | grep -qE "\+0m +frame +enter *$"'
chk "build enter blank marker" 'printf "%s" "$out" | grep -qE "\+29m +build +enter *$"'
# markers
chk "marker FAIL" 'printf "%s" "$out" | grep -qE "review +gate +FAIL +2 findings"'
chk "marker SKIP" 'printf "%s" "$out" | grep -qE "secure +skip +SKIP +no IO"'
# retry tag on the recovered pass
chk "retry tag" 'printf "%s" "$out" | grep -qF "(retry) fixed"'
chk "no spurious retry" '[ "$(printf "%s" "$out" | grep -c "(retry)")" -eq 1 ]'
# footer stats
chk "footer" 'printf "%s" "$out" | grep -qF "phases: 5   gate-retries: 1   skips: 1   open-fails: 0   total: ~70m"'

# explicit change selects the older run
oa="$(bash "$ROOT/scripts/ss-replay" feat/a)"
chk "explicit change" 'printf "%s" "$oa" | grep -qF "loop replay: feat/a" && printf "%s" "$oa" | grep -qF "spec ok"'

# open-fails: a run whose last gate for a phase is a fail
cat > "$SUPERSTACK_DIR/ledger.jsonl" <<'JSONL'
{"ts":"2026-06-22T08:00:00Z","change":"feat/c","phase":"build","event":"enter","status":"na","note":""}
{"ts":"2026-06-22T08:05:00Z","change":"feat/c","phase":"review","event":"gate","status":"fail","note":"bug"}
JSONL
oc="$(bash "$ROOT/scripts/ss-replay" feat/c)"
chk "open-fails counts unrecovered fail" 'printf "%s" "$oc" | grep -qE "open-fails: 1"'

# no run
rm -f "$SUPERSTACK_DIR/ledger.jsonl"
chk "no run default" 'bash "$ROOT/scripts/ss-replay" | grep -qF "no run to replay"'
chk "no run explicit" 'bash "$ROOT/scripts/ss-replay" feat/x | grep -qF "no run found for feat/x"'

# --save writes a fenced markdown file under replays/ and reports the path on stderr
cp /dev/null "$SUPERSTACK_DIR/ledger.jsonl"
cat > "$SUPERSTACK_DIR/ledger.jsonl" <<'JSONL'
{"ts":"2026-06-23T07:00:00Z","change":"feat/d","phase":"frame","event":"enter","status":"na","note":""}
{"ts":"2026-06-23T07:05:00Z","change":"feat/d","phase":"ship","event":"gate","status":"pass","note":"done"}
JSONL
serr="$(bash "$ROOT/scripts/ss-replay" feat/d --save 2>&1 >/dev/null)"
chk "save writes file" '[ -f "$SUPERSTACK_DIR/replays/feat-d.md" ]'
chk "save is fenced" 'head -1 "$SUPERSTACK_DIR/replays/feat-d.md" | grep -qF "\`\`\`"'
chk "save reports path" 'printf "%s" "$serr" | grep -qF "saved -> .superstack/replays/feat-d.md"'

# parity: ps1 emits byte-identical output to bash (guarded for CI without pwsh)
if command -v pwsh >/dev/null 2>&1; then
  if command -v cygpath >/dev/null 2>&1; then ps1arg="$(cygpath -w "$ROOT/scripts/ss-replay.ps1")"; else ps1arg="$ROOT/scripts/ss-replay.ps1"; fi
  cat > "$SUPERSTACK_DIR/ledger.jsonl" <<'JSONL'
{"ts":"2026-06-21T09:00:00Z","change":"feat/b","phase":"frame","event":"enter","status":"na","note":""}
{"ts":"2026-06-21T09:29:00Z","change":"feat/b","phase":"build","event":"enter","status":"na","note":""}
{"ts":"2026-06-21T09:56:00Z","change":"feat/b","phase":"review","event":"gate","status":"fail","note":"2 findings"}
{"ts":"2026-06-21T10:08:00Z","change":"feat/b","phase":"review","event":"gate","status":"pass","note":"fixed"}
{"ts":"2026-06-21T10:10:00Z","change":"feat/b","phase":"ship","event":"gate","status":"pass","note":"CI green"}
{"ts":"2026-06-21T10:10:00Z","change":"feat/b","phase":"secure","event":"skip","status":"skip","note":"no IO"}
JSONL
  rb="$(bash "$ROOT/scripts/ss-replay" feat/b)"
  rp="$(pwsh -NoProfile -File "$ps1arg" feat/b | tr -d '\r')"
  chk "ps1 parity (explicit)" '[ "$rb" = "$rp" ]'
  db="$(bash "$ROOT/scripts/ss-replay")"
  dp="$(pwsh -NoProfile -File "$ps1arg" | tr -d '\r')"
  chk "ps1 parity (default latest)" '[ "$db" = "$dp" ]'
else
  echo "  SKIP ps1 parity (pwsh not installed)"
fi

echo
[ "$fail" -eq 0 ] && echo "REPLAY TESTS PASS" || echo "REPLAY TESTS FAILED"
exit "$fail"
