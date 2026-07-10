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
chk "fresh routing installed" 'printf "%s" "$out" | grep -qE "routing: +installed \(CLAUDE.md\)"'
chk "routing markers present" 'grep -qF "<!-- superstack:context-routing -->" "$T/CLAUDE.md" && grep -qF "<!-- /superstack:context-routing -->" "$T/CLAUDE.md"'
chk "routing block == template" 'cmp -s "$T/CLAUDE.md" "$ROOT/templates/context-routing.md"'

# --- idempotent re-run ---
csum1="$(cksum < "$SUPERSTACK_DIR/config")"
clsum1="$(cksum < "$T/CLAUDE.md")"
out2="$(cd "$T" && bash "$ROOT/scripts/ss-init")"
chk "rerun config present"   'printf "%s" "$out2" | grep -qF "already present (use --force to reset)"'
chk "rerun gitignore present" 'printf "%s" "$out2" | grep -qF "gitignore: already ignored"'
chk "rerun ledger present"   'printf "%s" "$out2" | grep -qE "ledger: +already present"'
chk "rerun footer"           'printf "%s" "$out2" | grep -qF "already initialized."'
chk "rerun config unchanged" '[ "$(cksum < "$SUPERSTACK_DIR/config")" = "$csum1" ]'
chk "rerun gitignore not dup" '[ "$(grep -cxF ".superstack/" "$T/.gitignore")" -eq 1 ]'
chk "rerun ledger not dup"   '[ "$(wc -l < "$SUPERSTACK_DIR/ledger.jsonl" | tr -d " ")" -eq 1 ]'
chk "rerun routing current"  'printf "%s" "$out2" | grep -qE "routing: +already current"'
chk "rerun claude unchanged" '[ "$(cksum < "$T/CLAUDE.md")" = "$clsum1" ]'

# --- --force resets config only ---
printf 'mandatory_phases=qa\n' > "$SUPERSTACK_DIR/config"
outf="$(cd "$T" && bash "$ROOT/scripts/ss-init" --force)"
chk "force resets config"    'printf "%s" "$outf" | grep -qE "config: +reset" && grep -qxF "mandatory_phases=review,secure" "$SUPERSTACK_DIR/config"'
chk "force no gitignore dup"  '[ "$(grep -cxF ".superstack/" "$T/.gitignore")" -eq 1 ]'
chk "force no ledger dup"    '[ "$(wc -l < "$SUPERSTACK_DIR/ledger.jsonl" | tr -d " ")" -eq 1 ]'

# --- routing update path: corrupted block restored, surrounding text preserved ---
{ printf '# My project notes\n\n'; cat "$ROOT/templates/context-routing.md"; printf '\ntrailing text\n'; } > "$T/CLAUDE.md"
sed -i 's/Keep raw bulk/KEEP RAW BULK/' "$T/CLAUDE.md"
outu="$(cd "$T" && bash "$ROOT/scripts/ss-init")"
chk "update routing row"     'printf "%s" "$outu" | grep -qE "routing: +updated \(CLAUDE.md\)"'
chk "update restores block"  'grep -qF "Keep raw bulk" "$T/CLAUDE.md" && ! grep -qF "KEEP RAW BULK" "$T/CLAUDE.md"'
chk "update preserves text"  'grep -qF "# My project notes" "$T/CLAUDE.md" && grep -qF "trailing text" "$T/CLAUDE.md"'
chk "update markers once"    '[ "$(grep -cF "<!-- superstack:context-routing -->" "$T/CLAUDE.md")" -eq 1 ]'

# --- --no-routing opts out ---
T5="$(newrepo)"; export SUPERSTACK_DIR="$T5/.superstack"
outn="$(cd "$T5" && bash "$ROOT/scripts/ss-init" --no-routing)"
chk "no-routing row"         'printf "%s" "$outn" | grep -qE "routing: +skipped \(--no-routing\)"'
chk "no-routing no claude"   '[ ! -f "$T5/CLAUDE.md" ]'

# --- --dry-run on a fresh project writes nothing ---
T2="$(newrepo)"; export SUPERSTACK_DIR="$T2/.superstack"
outd="$(cd "$T2" && bash "$ROOT/scripts/ss-init" --dry-run)"
chk "dryrun plan"            'printf "%s" "$outd" | grep -qF "[dry-run] would create .superstack/config" && printf "%s" "$outd" | grep -qF "[dry-run] no changes written."'
chk "dryrun no config"       '[ ! -f "$SUPERSTACK_DIR/config" ]'
chk "dryrun no ledger"       '[ ! -f "$SUPERSTACK_DIR/ledger.jsonl" ]'
chk "dryrun no gitignore"    '[ ! -f "$T2/.gitignore" ]'
chk "dryrun routing plan"    'printf "%s" "$outd" | grep -qF "[dry-run] would install the routing block into CLAUDE.md"'
chk "dryrun no claude"       '[ ! -f "$T2/CLAUDE.md" ]'

# --- not a git repo: gitignore skipped, config still made ---
T3="$(mktemp -d)"; export SUPERSTACK_DIR="$T3/.superstack"
outg="$(cd "$T3" && bash "$ROOT/scripts/ss-init")"
chk "non-git gitignore skip" 'printf "%s" "$outg" | grep -qF "gitignore: skipped (not a git repo)"'
chk "non-git config made"    '[ -f "$SUPERSTACK_DIR/config" ]'

# parity: ps1 emits byte-identical output to bash for --dry-run on a fresh repo
if command -v pwsh >/dev/null 2>&1; then
  if command -v cygpath >/dev/null 2>&1; then ps1arg="$(cygpath -w "$ROOT/scripts/ss-init.ps1")"; else ps1arg="$ROOT/scripts/ss-init.ps1"; fi
  T4="$(newrepo)"; export SUPERSTACK_DIR="$T4/.superstack"
  pb="$(cd "$T4" && bash "$ROOT/scripts/ss-init" --dry-run)"
  pp="$(cd "$T4" && pwsh -NoProfile -File "$ps1arg" -DryRun | tr -d '\r')"
  chk "ps1 parity (dry-run)" '[ "$pb" = "$pp" ]'
  # real-run parity: reports byte-identical AND written CLAUDE.md byte-identical (LF discipline)
  T6="$(newrepo)"; T7="$(newrepo)"
  rb="$(cd "$T6" && SUPERSTACK_DIR="$T6/.superstack" bash "$ROOT/scripts/ss-init")"
  rp="$(cd "$T7" && SUPERSTACK_DIR="$T7/.superstack" pwsh -NoProfile -File "$ps1arg" | tr -d '\r')"
  chk "ps1 parity (real-run report)" '[ "$rb" = "$rp" ]'
  chk "ps1 parity (CLAUDE.md bytes)" 'cmp -s "$T6/CLAUDE.md" "$T7/CLAUDE.md"'
else
  echo "  SKIP ps1 parity (pwsh not installed)"
fi

echo
[ "$fail" -eq 0 ] && echo "INIT TESTS PASS" || echo "INIT TESTS FAILED"
exit "$fail"
