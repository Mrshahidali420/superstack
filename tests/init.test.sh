#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavior + parity tests for scripts/ss-init.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }
newrepo() { local t; t="$(mktemp -d)"; ( cd "$t" && git init -q . && git config user.email t@t && git config user.name t ); printf '%s' "$t"; }

# --- fresh init ---
T="$(newrepo)"; export SUPERSTACK_DIR="$T/.superstack"
out="$(cd "$T" && bash "$ROOT/scripts/ss-init")"
chk "fresh config created"   'printf "%s" "$out" | grep -qE "config: +created"'
chk "fresh gitignore added"  'printf "%s" "$out" | grep -qF "gitignore: added .superstack/ to .gitignore"'
chk "fresh ledger genesis"   'printf "%s" "$out" | grep -qE "ledger: +created \(genesis entry\)"'
chk "fresh footer ready"     'printf "%s" "$out" | grep -qF "ready - run /ss-frame"'
chk "config content"         'grep -qxF "mandatory_phases=review,secure" "$SUPERSTACK_DIR/config" && grep -qxF "evolve_threshold=3" "$SUPERSTACK_DIR/config"'
chk "config has comment"     'grep -qF "# SuperStack project config" "$SUPERSTACK_DIR/config"'
chk "gitignore once"         '[ "$(grep -cxF ".superstack/" "$T/.gitignore")" -eq 1 ]'
chk "genesis one entry"      '[ "$(wc -l < "$SUPERSTACK_DIR/ledger.jsonl" | tr -d " ")" -eq 1 ] && grep -q "\"phase\":\"init\"" "$SUPERSTACK_DIR/ledger.jsonl" && grep -q "superstack loop initialized" "$SUPERSTACK_DIR/ledger.jsonl"'

# --- idempotent re-run ---
csum1="$(cksum < "$SUPERSTACK_DIR/config")"
out2="$(cd "$T" && bash "$ROOT/scripts/ss-init")"
chk "rerun config present"   'printf "%s" "$out2" | grep -qF "already present (use --force to reset)"'
chk "rerun gitignore present" 'printf "%s" "$out2" | grep -qF "gitignore: already ignored"'
chk "rerun ledger present"   'printf "%s" "$out2" | grep -qE "ledger: +already present"'
chk "rerun footer"           'printf "%s" "$out2" | grep -qF "already initialized."'
chk "rerun config unchanged" '[ "$(cksum < "$SUPERSTACK_DIR/config")" = "$csum1" ]'
chk "rerun gitignore not dup" '[ "$(grep -cxF ".superstack/" "$T/.gitignore")" -eq 1 ]'
chk "rerun ledger not dup"   '[ "$(wc -l < "$SUPERSTACK_DIR/ledger.jsonl" | tr -d " ")" -eq 1 ]'

# --- --force resets config only ---
printf 'mandatory_phases=qa\n' > "$SUPERSTACK_DIR/config"
outf="$(cd "$T" && bash "$ROOT/scripts/ss-init" --force)"
chk "force resets config"    'printf "%s" "$outf" | grep -qE "config: +reset" && grep -qxF "mandatory_phases=review,secure" "$SUPERSTACK_DIR/config"'
chk "force no gitignore dup"  '[ "$(grep -cxF ".superstack/" "$T/.gitignore")" -eq 1 ]'
chk "force no ledger dup"    '[ "$(wc -l < "$SUPERSTACK_DIR/ledger.jsonl" | tr -d " ")" -eq 1 ]'

# --- --dry-run on a fresh project writes nothing ---
T2="$(newrepo)"; export SUPERSTACK_DIR="$T2/.superstack"
outd="$(cd "$T2" && bash "$ROOT/scripts/ss-init" --dry-run)"
chk "dryrun plan"            'printf "%s" "$outd" | grep -qF "[dry-run] would create .superstack/config" && printf "%s" "$outd" | grep -qF "[dry-run] no changes written."'
chk "dryrun no config"       '[ ! -f "$SUPERSTACK_DIR/config" ]'
chk "dryrun no ledger"       '[ ! -f "$SUPERSTACK_DIR/ledger.jsonl" ]'
chk "dryrun no gitignore"    '[ ! -f "$T2/.gitignore" ]'

# --- not a git repo: gitignore skipped, config still made ---
T3="$(mktemp -d)"; export SUPERSTACK_DIR="$T3/.superstack"
outg="$(cd "$T3" && bash "$ROOT/scripts/ss-init")"
chk "non-git gitignore skip" 'printf "%s" "$outg" | grep -qF "gitignore: skipped (not a git repo)"'
chk "non-git config made"    '[ -f "$SUPERSTACK_DIR/config" ]'

echo
[ "$fail" -eq 0 ] && echo "INIT TESTS PASS" || echo "INIT TESTS FAILED"
exit "$fail"
