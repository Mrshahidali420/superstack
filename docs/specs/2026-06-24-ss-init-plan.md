# /ss-init (per-project bootstrap) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/ss-init` — a bash script + PowerShell twin (and skill) that makes a project loop-ready: writes a default `.superstack/config`, ensures `.superstack/` is gitignored, and records a genesis ledger entry. Idempotent and non-destructive.

**Architecture:** Three independent create-if-missing actions (config / gitignore / ledger-genesis), each reporting its state; `--dry-run` plans without writing, `--force` resets only the config. The PowerShell twin mirrors the logic and stdout byte-for-byte.

**Tech Stack:** Bash; PowerShell 7 (`pwsh`); the existing `scripts/ledger` (+`.ps1`); bash test harness wired through `tests/run.sh`.

## Global Constraints

(Verbatim from the spec; every task implicitly includes these.)

- **Byte-identical ASCII stdout** across `scripts/ss-init` (bash) and `scripts/ss-init.ps1`. No Unicode.
- **Idempotent & non-destructive by default:** create only what's missing; never clobber `config` unless `--force`; never duplicate the gitignore line or add a second genesis entry.
- **CLI:** `ss-init [--force] [--dry-run]` (PowerShell `-Force` / `-DryRun`). Unknown flag → stderr usage, exit 1. No positional args. Exit 0 normally.
- **Runtime dir** = `${SUPERSTACK_DIR:-.superstack}`. User-facing messages use the **literal `.superstack/`** regardless of override (codebase display convention).
- **config body** (exact):
  ```
  # SuperStack project config (key=value). Delete a line to use the built-in default.
  mandatory_phases=review,secure
  evolve_threshold=3
  ```
- **gitignore:** operate on the git-root `.gitignore` (`git rev-parse --show-toplevel`); skip with `skipped (not a git repo)` when not in a repo; add the line `.superstack/` only if neither `.superstack/` nor `.superstack` is already present; never duplicate.
- **genesis:** if `dir/ledger.jsonl` is absent, call the sibling ledger `init note na "superstack loop initialized"` (bash → `ledger`, ps1 → `ledger.ps1`); skip if a ledger already exists.
- **`--force`** resets only `config`; **`--dry-run`** prints the plan and writes nothing.
- **Output strings** are exactly as in the spec §6 (per-state lines + footer).
- Commits: conventional-commit, no AI attribution. Ships in the next release (`[Unreleased]`); skills count → 24.

Reference siblings for style: `scripts/ss-report` (arg loop, sibling-`ledger` call), `scripts/ledger` (interface). Spec: `docs/specs/2026-06-24-ss-init-design.md`.

---

## File Structure

- `scripts/ss-init` — bash (Task 1)
- `scripts/ss-init.ps1` — PowerShell twin (Task 2)
- `tests/init.test.sh` — behavior tests (Task 1) + parity test (Task 2)
- `tests/run.sh` — wire as `[9/9]`, bump `[N/8]`→`[N/9]` (Task 1)
- `skills/init/SKILL.md` — the skill (Task 3)
- `README.md`, `CHANGELOG.md` — surface it (Task 4)

---

## Task 1: `scripts/ss-init` (bash) + tests + run.sh wiring

**Model:** sonnet.

**Files:**
- Create: `scripts/ss-init`
- Create: `tests/init.test.sh`
- Modify: `tests/run.sh`

**Interfaces:**
- Produces: `scripts/ss-init [--force] [--dry-run]` performing the three actions + the spec output.
- Consumes: the sibling `scripts/ledger` (`ledger <phase> <event> [status] [note]`).

- [ ] **Step 1: Write the failing tests** — create `tests/init.test.sh`

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/init.test.sh`
Expected: FAIL — `scripts/ss-init` does not exist yet.

- [ ] **Step 3: Write `scripts/ss-init`**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Bootstrap a project's SuperStack runtime (config, gitignore, genesis ledger entry). Idempotent.
# Usage: ss-init [--force] [--dry-run]
set -uo pipefail
dir="${SUPERSTACK_DIR:-.superstack}"
config="$dir/config"; ledger="$dir/ledger.jsonl"
force=0; dry=0
for a in "$@"; do
  case "$a" in
    --force) force=1;;
    --dry-run) dry=1;;
    *) echo "ss-init: unknown flag '$a' (usage: ss-init [--force] [--dry-run])" >&2; exit 1;;
  esac
done

CONFIG_BODY='# SuperStack project config (key=value). Delete a line to use the built-in default.
mandatory_phases=review,secure
evolve_threshold=3'

wrote=0

# config -------------------------------------------------------------
if [ ! -f "$config" ]; then
  if [ "$dry" -eq 1 ]; then cfg="[dry-run] would create .superstack/config"
  else mkdir -p "$dir"; printf '%s\n' "$CONFIG_BODY" > "$config"; cfg="created (.superstack/config)"; wrote=1; fi
elif [ "$force" -eq 1 ]; then
  if [ "$dry" -eq 1 ]; then cfg="[dry-run] would reset .superstack/config"
  else printf '%s\n' "$CONFIG_BODY" > "$config"; cfg="reset (.superstack/config)"; wrote=1; fi
else
  cfg="already present (use --force to reset)"
fi

# gitignore ----------------------------------------------------------
root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$root" ]; then
  gi="skipped (not a git repo)"
else
  gif="$root/.gitignore"
  if [ -f "$gif" ] && { grep -qxF '.superstack/' "$gif" || grep -qxF '.superstack' "$gif"; }; then
    gi="already ignored"
  elif [ "$dry" -eq 1 ]; then
    gi="[dry-run] would add .superstack/ to .gitignore"
  else
    # append, ensuring a separating newline if the file lacks a trailing one
    { [ -s "$gif" ] && [ -n "$(tail -c1 "$gif" 2>/dev/null)" ] && printf '\n'; printf '.superstack/\n'; } >> "$gif"
    gi="added .superstack/ to .gitignore"; wrote=1
  fi
fi

# ledger genesis -----------------------------------------------------
if [ ! -f "$ledger" ]; then
  if [ "$dry" -eq 1 ]; then lg="[dry-run] would write a genesis entry"
  else
    sib="$(cd "$(dirname "$0")" && pwd)/ledger"
    if [ -f "$sib" ]; then bash "$sib" init note na "superstack loop initialized" >/dev/null 2>&1; lg="created (genesis entry)"; wrote=1
    else lg="skipped (ledger script missing)"; fi
  fi
else
  lg="already present"
fi

# report -------------------------------------------------------------
printf 'ss-init: SuperStack project setup (.superstack/)\n'
printf '  %-10s %s\n' "config:" "$cfg"
printf '  %-10s %s\n' "gitignore:" "$gi"
printf '  %-10s %s\n' "ledger:" "$lg"
if [ "$dry" -eq 1 ]; then printf '%s\n' "[dry-run] no changes written."
elif [ "$wrote" -eq 1 ]; then printf '%s\n' "ready - run /ss-frame to start the loop (see CLAUDE.md)."
else printf '%s\n' "already initialized."
fi
exit 0
```

- [ ] **Step 4: Make it executable and run the tests**

Run: `chmod +x scripts/ss-init && bash tests/init.test.sh`
Expected: `INIT TESTS PASS`. If `config has comment` fails, check the heredoc body; if `genesis one entry` fails, confirm the sibling `ledger` is invoked and `SUPERSTACK_DIR` is inherited.

- [ ] **Step 5: Wire the suite into `tests/run.sh`**

In `tests/run.sh`: change the eight labels `[1/8]`…`[8/8]` to `[1/9]`…`[8/9]`. Then insert after the `[8/9] loop replay behavior` block (after its closing `fi`, before the final `echo`):

```bash
echo "[9/9] init behavior"
if bash "$ROOT/tests/init.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - init suite"; fail=1
fi
```

- [ ] **Step 6: Run the full suite + lint**

Run: `bash tests/run.sh && bash scripts/lint-skills.sh .`
Expected: `[1/9]`…`[9/9]` PASS, `ALL TESTS PASS`; lint clean.

- [ ] **Step 7: Commit**

```bash
git add scripts/ss-init tests/init.test.sh tests/run.sh
git commit -m "feat(init): add ss-init project bootstrap (bash)"
```

---

## Task 2: `scripts/ss-init.ps1` (PowerShell twin) + parity test

**Model:** sonnet.

**Files:**
- Create: `scripts/ss-init.ps1`
- Modify: `tests/init.test.sh` (append a parity block before the summary)

**Interfaces:**
- Consumes: the bash `scripts/ss-init` behavior + output from Task 1 (must match byte-for-byte).
- Produces: `scripts/ss-init.ps1 [-Force] [-DryRun]` with byte-identical stdout.

- [ ] **Step 1: Append the failing parity test** to `tests/init.test.sh`, immediately before the final `echo`/summary:

```bash
# parity: ps1 emits byte-identical output to bash for --dry-run on a fresh repo
if command -v pwsh >/dev/null 2>&1; then
  if command -v cygpath >/dev/null 2>&1; then ps1arg="$(cygpath -w "$ROOT/scripts/ss-init.ps1")"; else ps1arg="$ROOT/scripts/ss-init.ps1"; fi
  T4="$(newrepo)"; export SUPERSTACK_DIR="$T4/.superstack"
  pb="$(cd "$T4" && bash "$ROOT/scripts/ss-init" --dry-run)"
  pp="$(cd "$T4" && pwsh -NoProfile -File "$ps1arg" -DryRun | tr -d '\r')"
  chk "ps1 parity (dry-run)" '[ "$pb" = "$pp" ]'
else
  echo "  SKIP ps1 parity (pwsh not installed)"
fi
```

- [ ] **Step 2: Run the tests to confirm the parity check fails**

Run: `bash tests/init.test.sh`
Expected: behavior checks PASS; `ps1 parity (dry-run)` FAIL (ps1 missing) — or SKIP if no `pwsh`.

- [ ] **Step 3: Write `scripts/ss-init.ps1`**

```powershell
#!/usr/bin/env pwsh
# SPDX-License-Identifier: MIT
# Bootstrap a project's SuperStack runtime (config, gitignore, genesis ledger entry). Idempotent.
# Usage: ss-init.ps1 [-Force] [-DryRun]
param([switch]$Force, [switch]$DryRun)
$ErrorActionPreference = 'Stop'
$dir = if ($env:SUPERSTACK_DIR) { $env:SUPERSTACK_DIR } else { '.superstack' }
if ($dir -match '^/[a-zA-Z]/') { try { $dir = (& cygpath -w $dir 2>$null).Trim() } catch {} }
$config = Join-Path $dir 'config'
$ledger = Join-Path $dir 'ledger.jsonl'

$body = @(
  '# SuperStack project config (key=value). Delete a line to use the built-in default.'
  'mandatory_phases=review,secure'
  'evolve_threshold=3'
) -join "`n"

$wrote = $false

# config
if (-not (Test-Path $config)) {
  if ($DryRun) { $cfg = '[dry-run] would create .superstack/config' }
  else { New-Item -ItemType Directory -Force -Path $dir | Out-Null; Set-Content -Path $config -Value $body -Encoding utf8; $cfg = 'created (.superstack/config)'; $wrote = $true }
} elseif ($Force) {
  if ($DryRun) { $cfg = '[dry-run] would reset .superstack/config' }
  else { Set-Content -Path $config -Value $body -Encoding utf8; $cfg = 'reset (.superstack/config)'; $wrote = $true }
} else {
  $cfg = 'already present (use --force to reset)'
}

# gitignore
$root = (git rev-parse --show-toplevel 2>$null)
if (-not $root) {
  $gi = 'skipped (not a git repo)'
} else {
  $gif = Join-Path $root '.gitignore'
  $ignored = (Test-Path $gif) -and (@(Get-Content $gif) | Where-Object { $_ -eq '.superstack/' -or $_ -eq '.superstack' }).Count -gt 0
  if ($ignored) { $gi = 'already ignored' }
  elseif ($DryRun) { $gi = '[dry-run] would add .superstack/ to .gitignore' }
  else {
    $pre = if ((Test-Path $gif) -and (Get-Item $gif).Length -gt 0 -and -not ((Get-Content -Raw $gif).EndsWith("`n"))) { "`n" } else { '' }
    Add-Content -Path $gif -Value ($pre + '.superstack/')
    $gi = 'added .superstack/ to .gitignore'; $wrote = $true
  }
}

# ledger genesis
if (-not (Test-Path $ledger)) {
  if ($DryRun) { $lg = '[dry-run] would write a genesis entry' }
  else {
    $sib = Join-Path $PSScriptRoot 'ledger.ps1'
    if (Test-Path $sib) { & $sib init note na 'superstack loop initialized' *>$null; $lg = 'created (genesis entry)'; $wrote = $true }
    else { $lg = 'skipped (ledger script missing)' }
  }
} else { $lg = 'already present' }

# report
$lines = @(
  'ss-init: SuperStack project setup (.superstack/)'
  ('  {0,-10} {1}' -f 'config:', $cfg)
  ('  {0,-10} {1}' -f 'gitignore:', $gi)
  ('  {0,-10} {1}' -f 'ledger:', $lg)
)
if ($DryRun) { $lines += '[dry-run] no changes written.' }
elseif ($wrote) { $lines += 'ready - run /ss-frame to start the loop (see CLAUDE.md).' }
else { $lines += 'already initialized.' }
Write-Output ($lines -join "`n")
```

Parity notes for the implementer:
- `'  {0,-10} {1}'` mirrors bash `printf '  %-10s %s\n'` — `config:`/`ledger:` (7) pad to 10, `gitignore:` (10) doesn't, then one separator space before the value. No trailing padding (value is last) → no rstrip needed.
- Verify `scripts/ledger.ps1`'s param order accepts positional `init note na '<note>'` (phase, event, status, note). If its params are named, pass them positionally in that order.
- The parity test uses `--dry-run` so neither twin mutates state; both see the same fresh repo and print the identical plan. (`git rev-parse --show-toplevel` may return different path *formats* across bash/pwsh, but the gitignore line is the literal `[dry-run] would add .superstack/ to .gitignore`, so stdout is identical.)

- [ ] **Step 4: Run the tests to verify parity passes**

Run: `bash tests/init.test.sh`
Expected: all PASS including `ps1 parity (dry-run)` (or SKIP if no `pwsh`) → `INIT TESTS PASS`. If parity fails, diff `bash scripts/ss-init --dry-run` vs `pwsh -NoProfile -File scripts/ss-init.ps1 -DryRun | tr -d '\r'` (run both from the same fresh git tmp dir) and reconcile.

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run.sh`
Expected: `[1/9]`…`[9/9]` PASS, `ALL TESTS PASS`.

- [ ] **Step 6: Commit**

```bash
git add scripts/ss-init.ps1 tests/init.test.sh
git commit -m "feat(init): PowerShell parity for ss-init"
```

---

## Task 3: `skills/init/SKILL.md`

**Model:** haiku (pure markdown).

**Files:**
- Create: `skills/init/SKILL.md`

**Interfaces:** documents Task 1–2 behavior; nothing depends on it.

- [ ] **Step 1: Write the skill**

```markdown
---
name: ss-init
description: Use once in a new project (after installing SuperStack) to make the loop ready - it writes a default .superstack/config, ensures .superstack/ is gitignored, and records a genesis ledger entry. Idempotent and safe to re-run.
---

# Init - bootstrap a project for the loop

Per-project setup. Run it once after the plugin is installed; it makes the loop work in this repo.
(`install.sh` is the global, per-agent install; `/ss-init` is the per-project runtime setup.)

## Steps

1. Run `scripts/ss-init` (PowerShell: `scripts/ss-init.ps1`). It is idempotent - safe to run again;
   it only creates what is missing.
2. It performs three create-if-missing actions and reports each:
   - **config** - writes `.superstack/config` with the tunable defaults (`mandatory_phases`,
     `evolve_threshold`). Use `--force` to reset an edited config back to defaults.
   - **gitignore** - adds `.superstack/` to the project's `.gitignore` once, so the runtime dir is
     not committed. Skipped outside a git repo.
   - **ledger** - writes a genesis entry so the ledger exists and the toolchain is proven.
3. Preview without writing using `--dry-run`. When it reports `ready`, start the loop with `/ss-frame`.

## Note

`/ss-init` never installs skills (that is `install.sh`) and never verifies your setup (that is
[[ss-doctor]]). It only prepares this project's `.superstack/` runtime.

## Lineage

Original to SuperStack - the per-project counterpart to the global `install.sh`.
```

- [ ] **Step 2: Verify it lints**

Run: `bash scripts/lint-skills.sh .`
Expected: PASS (name `ss-init`, description 40–500 chars, exactly one H1).

- [ ] **Step 3: Commit**

```bash
git add skills/init/SKILL.md
git commit -m "docs(init): add /ss-init skill"
```

---

## Task 4: README + CHANGELOG

**Model:** haiku (pure markdown).

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update the CHANGELOG**

Read `CHANGELOG.md`. Under the top `## [Unreleased]` heading's `### Added` group (create the group if absent — `/ss-replay` may already have an entry there; add to it), add:

```markdown
- **`/ss-init`:** per-project bootstrap — writes a default `.superstack/config`, ensures `.superstack/`
  is gitignored, and records a genesis ledger entry. Idempotent; `--dry-run` previews, `--force` resets
  the config. bash + PowerShell. (24 skills.)
```

Do NOT rename `[Unreleased]` to a version. Don't disturb existing entries.

- [ ] **Step 2: Surface it in the README**

Read `README.md`. Two edits, surgical:
1. In the **Install** section, add a one-line quickstart after the install commands: *"Then run `/ss-init` once in your project to set up `.superstack/`, and `/ss-frame` to start the loop."*
2. Add `/ss-init` to the commands surface (near the supporting/setup skills) with: *"Bootstrap a project for the loop — config, gitignore, genesis ledger entry (idempotent)."*
3. Bump the skills count: badge `skills-23` → `skills-24` and any "23 skills" prose → **24**.

Match surrounding style; don't restructure.

- [ ] **Step 3: Verify nothing regressed**

Run: `bash tests/run.sh`
Expected: `ALL TESTS PASS`.

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: surface /ss-init in README + CHANGELOG"
```

---

## Self-Review (completed by plan author)

- **Spec coverage:** `--force`/`--dry-run` CLI (T1 arg loop) · config create/skip/reset (T1) · gitignore add-once/skip-non-git (T1) · genesis create-if-missing via sibling ledger (T1) · idempotency + non-destructive (T1 + tests) · exact output strings (T1, spec §6) · byte-identical twins (T2 parity) · tests→`run.sh [9/9]` (T1–T2) · skill (T3) · README 24 + quickstart + CHANGELOG (T4). All spec sections map to a task.
- **Placeholder scan:** none — every code/test/doc block is complete.
- **Type/name consistency:** `--force`/`-Force`, `--dry-run`/`-DryRun`, `$cfg`/`$gi`/`$lg`, the `CONFIG_BODY`/`$body` text, the literal output strings, the `%-10s` ≡ `{0,-10}` format, and the genesis note `"superstack loop initialized"` are identical across bash, PowerShell, and the tests.

---

## Execution Handoff

Recommended: **subagent-driven** — Task 1 (bash) and Task 2 (PowerShell parity) on sonnet, Tasks 3–4 (markdown) on haiku; per-task spec+quality review, opus whole-branch review at the end.
