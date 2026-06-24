#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavior + parity tests for scripts/ss-doctor.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }
newrepo() { local t; t="$(mktemp -d)"; ( cd "$t" && git init -q . && git config user.email t@t && git config user.name t ); printf '%s' "$t"; }

# --- healthy: ss-init then ss-doctor ---
T="$(newrepo)"; export SUPERSTACK_DIR="$T/.superstack"
( cd "$T" && bash "$ROOT/scripts/ss-init" >/dev/null )
out="$(cd "$T" && bash "$ROOT/scripts/ss-doctor")"; rc=$?
chk "healthy config OK"   'printf "%s" "$out" | grep -qE "\[OK\] +config"'
chk "healthy ledger OK"   'printf "%s" "$out" | grep -qE "\[OK\] +ledger +1 entries"'
chk "healthy gitignore OK" 'printf "%s" "$out" | grep -qE "\[OK\] +gitignore"'
chk "healthy verdict"     'printf "%s" "$out" | grep -qF "verdict: HEALTHY"'
chk "healthy exit 0"      '[ "$rc" -eq 0 ]'
chk "healthy no warn/fail" '! printf "%s" "$out" | grep -qE "\[WARN\]|\[FAIL\]"'

# --- not initialized ---
T2="$(newrepo)"; export SUPERSTACK_DIR="$T2/.superstack"
out2="$(cd "$T2" && bash "$ROOT/scripts/ss-doctor")"; rc2=$?
chk "uninit config WARN"   'printf "%s" "$out2" | grep -qE "\[WARN\] +config +\.superstack/config missing"'
chk "uninit ledger WARN"   'printf "%s" "$out2" | grep -qE "\[WARN\] +ledger +no ledger yet"'
chk "uninit gitignore WARN" 'printf "%s" "$out2" | grep -qE "\[WARN\] +gitignore +\.superstack/ not gitignored"'
chk "uninit verdict"       'printf "%s" "$out2" | grep -qF "verdict: WARNINGS"'
chk "uninit exit 0"        '[ "$rc2" -eq 0 ]'

# --- corrupt ledger -> FAIL, exit 1 ---
T3="$(newrepo)"; export SUPERSTACK_DIR="$T3/.superstack"
mkdir -p "$SUPERSTACK_DIR"
printf '%s\n' '{"ts":"2026-06-24T00:00:00Z","change":"main","phase":"frame","event":"enter","status":"na","note":""}' > "$SUPERSTACK_DIR/ledger.jsonl"
printf '%s\n' '{"ts":"2026-06-24T00:01:00Z" TRUNCATED' >> "$SUPERSTACK_DIR/ledger.jsonl"
out3="$(cd "$T3" && bash "$ROOT/scripts/ss-doctor")"; rc3=$?
chk "corrupt ledger FAIL" 'printf "%s" "$out3" | grep -qE "\[FAIL\] +ledger +1 of 2 lines malformed"'
chk "corrupt verdict"     'printf "%s" "$out3" | grep -qF "verdict: PROBLEMS"'
chk "corrupt exit 1"      '[ "$rc3" -eq 1 ]'

# --- invalid config ---
T4="$(newrepo)"; export SUPERSTACK_DIR="$T4/.superstack"
mkdir -p "$SUPERSTACK_DIR"
printf 'mandatory_phases=review,bogus\nevolve_threshold=3\n' > "$SUPERSTACK_DIR/config"
out4="$(cd "$T4" && bash "$ROOT/scripts/ss-doctor")"
chk "invalid phase WARN" 'printf "%s" "$out4" | grep -qE "\[WARN\] +config +unknown phase .bogus. in mandatory_phases"'
printf 'mandatory_phases=review,secure\nevolve_threshold=x\n' > "$SUPERSTACK_DIR/config"
out4b="$(cd "$T4" && bash "$ROOT/scripts/ss-doctor")"
chk "invalid threshold WARN" 'printf "%s" "$out4b" | grep -qE "evolve_threshold .x. not a positive integer"'

# --- jq-free resilience: curated PATH without jq (guarded by symlink capability) ---
probe="$(mktemp -d)"
if ln -s "$(command -v awk)" "$probe/awk" 2>/dev/null; then
  bindir="$(mktemp -d)"
  for b in bash git grep awk tr cut tail sed cat env; do
    src="$(command -v "$b" 2>/dev/null)"; [ -n "$src" ] && ln -s "$src" "$bindir/$b" 2>/dev/null
  done
  bashbin="$(command -v bash)"
  T5="$(newrepo)"; export SUPERSTACK_DIR="$T5/.superstack"
  ( cd "$T5" && bash "$ROOT/scripts/ss-init" >/dev/null )   # seed with full PATH (jq present)
  out5="$(cd "$T5" && PATH="$bindir" "$bashbin" "$ROOT/scripts/ss-doctor")"; rc5=$?
  chk "jq-missing FAIL"        'printf "%s" "$out5" | grep -qE "\[FAIL\] +jq +not found"'
  chk "jq-missing ledger OK"   'printf "%s" "$out5" | grep -qE "\[OK\] +ledger"'
  chk "jq-missing exit 1"      '[ "$rc5" -eq 1 ]'
else
  echo "  SKIP jq-free resilience (symlinks unavailable)"
fi

# --- non-git dir ---
T6="$(mktemp -d)"; export SUPERSTACK_DIR="$T6/.superstack"
out6="$(cd "$T6" && bash "$ROOT/scripts/ss-doctor")"
chk "non-git git WARN"      'printf "%s" "$out6" | grep -qE "\[WARN\] +git +not a git repo"'
chk "non-git gitignore na"  'printf "%s" "$out6" | grep -qE "\[OK\] +gitignore +n/a"'

echo
[ "$fail" -eq 0 ] && echo "DOCTOR TESTS PASS" || echo "DOCTOR TESTS FAILED"
exit "$fail"
