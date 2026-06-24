# ss-evolve follow-ups (`--since` + `--explore`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--since <window>` (time-windowed detection) and `--explore` (deterministic Tier-2 new-skill proposal scaffolding) to `scripts/ss-evolve` and its PowerShell twin, with byte-identical output and full test coverage.

**Architecture:** Both flags are added to the existing single-file bash script and its `.ps1` twin. `--since` pre-filters the ledger stream by a computed cutoff timestamp before the existing detection runs. `--explore` is a new action (mutually exclusive with `--apply`) that scaffolds a valid-frontmatter `.superstack/proposals/<name>/SKILL.md` stub, records the finding id in a separate `.superstack/explore-state`, and never commits. The `/ss-evolve` skill (markdown) then authors the stub body; a human promotes it.

**Tech Stack:** Bash + jq; PowerShell 7 (`pwsh`); bash test harness (`tests/*.test.sh`) wired through `tests/run.sh`.

## Global Constraints

Every task implicitly includes these (verbatim from the spec):

- **Byte-identical stdout** across `scripts/ss-evolve` (bash) and `scripts/ss-evolve.ps1` (PowerShell). ASCII only — no Unicode glyphs.
- **Portable bash patterns:** read the ledger via stdin redirect (`jq … < "$ledger"`), strip `\r` with `tr -d '\r'`; never rely on GNU-only `date -d` (compute relative cutoffs in jq).
- **Native flag style per platform:** bash uses `--since` / `--explore`; PowerShell uses `-Since` / `-Explore`. Output is identical regardless.
- **`--explore` NEVER runs `git add`/`git commit`.** Proposals are structural and require human promotion. `.superstack/` is already gitignored.
- **Tier independence:** `--apply` dedups via `.superstack/evolve-state`; `--explore` dedups via the separate `.superstack/explore-state`. Neither suppresses the other.
- **Proposal frontmatter must be valid:** `name:` equals the directory name; `description:` is 40–500 chars; exactly one H1.
- **Commits:** conventional-commit format, no AI attribution (repo sets `includeCoAuthoredBy=false`).
- **Target version:** v0.4.0.

Reference files (read before starting): `docs/specs/2026-06-24-ss-evolve-followups-design.md` (the spec), `scripts/ledger` (ledger schema, `ts` = `date -u +%Y-%m-%dT%H:%M:%SZ`).

---

## File Structure

- `scripts/ss-evolve` — bash: arg parser (→ while/shift), `--since` cutoff + filter (Task 1), `--explore` action (Task 2).
- `scripts/ss-evolve.ps1` — PowerShell twin of the above.
- `tests/evolve-followups.test.sh` — **new** test file for `--since` (Task 1) and `--explore` (Task 2).
- `tests/run.sh` — wire the new test file as `[7/7]` (Task 1).
- `skills/evolve/SKILL.md` — document `--since`, `--explore`, the promote flow (Task 3).
- `README.md`, `CHANGELOG.md` — surface the new flags + version (Task 4).

---

## Task 1: `--since <window>` time-windowed detection

**Model:** sonnet (shell logic + parity).

**Files:**
- Modify: `scripts/ss-evolve` (arg loop lines 8-17; jq pipeline line 25-34)
- Modify: `scripts/ss-evolve.ps1` (param line 4; findings block lines 16-26)
- Create: `tests/evolve-followups.test.sh`
- Modify: `tests/run.sh` (labels `[N/6]`→`[N/7]`, add `[7/7]`)

**Interfaces:**
- Produces: `scripts/ss-evolve --since <window>` and `scripts/ss-evolve.ps1 -Since <window>` where `<window>` ∈ {`Nd`, `Nh`, `YYYY-MM-DD`}; pre-filters the ledger by `.ts >= cutoff` before detection; composes with `--json`/`--new-only`/`--apply`/`--explore`/`--dry-run`. Invalid window → stderr message, exit 1.
- Consumes (Task 2 relies on): the bash arg loop is now a `while/shift` loop with an `explore` variable slot and a post-loop mutual-exclusion guard already in place.

- [ ] **Step 1: Write the failing tests** — create `tests/evolve-followups.test.sh`

```bash
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
  if command -v cygpath >/dev/null 2>&1; then ps1arg="$(cygpath -w "$ROOT/scripts/ss-evolve.ps1")"; else ps1arg="$ROOT/scripts/ss-evolve.ps1"; fi
  sb="$(bash "$ROOT/scripts/ss-evolve" --since 2026-06-01)"
  sp="$(pwsh -NoProfile -File "$ps1arg" -Since 2026-06-01 | tr -d '\r')"
  chk "since parity" '[ "$sb" = "$sp" ]'
else
  echo "  SKIP since parity (pwsh not installed)"
fi

echo
[ "$fail" -eq 0 ] && echo "EVOLVE-FOLLOWUPS TESTS PASS" || echo "EVOLVE-FOLLOWUPS TESTS FAILED"
exit "$fail"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/evolve-followups.test.sh`
Expected: FAIL — `--since` is an unknown flag today, so `since drops old` / `since keeps new` fail (and `--since nonsense` currently errors for the wrong reason but may pass; the keeps/drops checks are the real RED).

- [ ] **Step 3: Rewrite the bash arg parser to a while/shift loop with `--since` + `--explore` slots**

In `scripts/ss-evolve`, replace lines 8-17 (the `json=0…done` block) with:

```bash
json=0; newonly=0; apply=0; dry=0; explore=0; since=""
usage="ss-evolve [--since <window>] [--json] [--new-only] [--apply|--explore] [--dry-run]"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json) json=1;;
    --new-only) newonly=1;;
    --apply) apply=1;;
    --explore) explore=1;;
    --dry-run) dry=1;;
    --since) shift; since="${1:-}"; [ -n "$since" ] || { echo "ss-evolve: --since needs a value (Nd|Nh|YYYY-MM-DD)" >&2; exit 1; };;
    --since=*) since="${1#--since=}";;
    *) echo "ss-evolve: unknown flag '$1' (usage: $usage)" >&2; exit 1;;
  esac
  shift
done
[ "$apply" -eq 1 ] && [ "$explore" -eq 1 ] && { echo "ss-evolve: --apply and --explore are mutually exclusive" >&2; exit 1; }
```

- [ ] **Step 4: Add the `--since` cutoff computation** (bash)

In `scripts/ss-evolve`, immediately after the `threshold=…` block (current line 21), insert:

```bash
cutoff=""
if [ -n "$since" ]; then
  case "$since" in
    [0-9]*d) n="${since%d}"; case "$n" in *[!0-9]*) echo "ss-evolve: bad --since '$since' (want Nd, Nh, or YYYY-MM-DD)" >&2; exit 1;; esac
             cutoff="$(jq -rn --argjson off "$((n*86400))" 'now - $off | todate')";;
    [0-9]*h) n="${since%h}"; case "$n" in *[!0-9]*) echo "ss-evolve: bad --since '$since' (want Nd, Nh, or YYYY-MM-DD)" >&2; exit 1;; esac
             cutoff="$(jq -rn --argjson off "$((n*3600))" 'now - $off | todate')";;
    [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) cutoff="${since}T00:00:00Z";;
    *) echo "ss-evolve: bad --since '$since' (want Nd, Nh, or YYYY-MM-DD)" >&2; exit 1;;
  esac
fi
```

- [ ] **Step 5: Wire the cutoff into the jq detection pipeline** (bash)

In `scripts/ss-evolve`, change the `jq -rn` invocation (current line 25) to pass `--arg cutoff` and filter inputs. Replace:

```bash
  findings="$(jq -rn --argjson th "$threshold" '
    [inputs] as $all
```

with:

```bash
  findings="$(jq -rn --argjson th "$threshold" --arg cutoff "$cutoff" '
    [inputs | select($cutoff=="" or .ts >= $cutoff)] as $all
```

(Leave the rest of the pipeline and the `< "$ledger" | tr -d '\r'` tail unchanged.)

- [ ] **Step 6: Run the bash-only checks to verify they pass**

Run: `bash tests/evolve-followups.test.sh`
Expected: the four `since *` checks PASS; parity SKIPs or fails (ps1 not yet updated). If `pwsh` is present, `since parity` will FAIL until Step 7.

- [ ] **Step 7: Add `-Since` + cutoff + filter to the PowerShell twin**

In `scripts/ss-evolve.ps1`:

(a) Replace the `param(...)` line 4 with:

```powershell
param([switch]$Json, [switch]$NewOnly, [switch]$Apply, [switch]$DryRun, [switch]$Explore, [string]$Since)
```

(b) Immediately after `$ErrorActionPreference = 'Stop'` (line 5), add the mutual-exclusion guard:

```powershell
if ($Apply -and $Explore) { Write-Error 'ss-evolve: --apply and --explore are mutually exclusive'; exit 1 }
```

(c) After the `$threshold` block (current lines 10-14), add the cutoff computation:

```powershell
$cutoff = ''
if ($Since) {
  if ($Since -match '^([0-9]+)d$') { $cutoff = [DateTime]::UtcNow.AddDays(-[int]$Matches[1]).ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture) }
  elseif ($Since -match '^([0-9]+)h$') { $cutoff = [DateTime]::UtcNow.AddHours(-[int]$Matches[1]).ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture) }
  elseif ($Since -match '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') { $cutoff = "$($Since)T00:00:00Z" }
  else { Write-Error "ss-evolve: bad -Since '$Since' (want Nd, Nh, or YYYY-MM-DD)"; exit 1 }
}
```

(d) Filter `$all` by the cutoff. Change the line that builds `$all` (current line 18) so the next line filters it. After:

```powershell
  $all = @(Get-Content $ledger | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
```

add:

```powershell
  if ($cutoff) { $all = @($all | Where-Object { [string]::CompareOrdinal($_.ts, $cutoff) -ge 0 }) }
```

(`CompareOrdinal` guarantees the same bytewise ordering jq uses, independent of locale.)

- [ ] **Step 8: Wire the new test into `tests/run.sh`**

In `tests/run.sh`: change each of the six labels `[1/6]`…`[6/6]` to `[1/7]`…`[6/7]` (the `echo "[N/6] …"` lines). Then insert a new block after the `[6/7] evolve detection + apply` block (after current line 52, before the final `echo`):

```bash
echo "[7/7] evolve follow-ups: --since + --explore"
if bash "$ROOT/tests/evolve-followups.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - evolve follow-ups suite"; fail=1
fi
```

- [ ] **Step 9: Run the full suite to verify everything passes**

Run: `bash tests/run.sh`
Expected: `[1/7]`…`[7/7]` all PASS (parity SKIPs only if `pwsh` is absent), ending `ALL TESTS PASS`. Also run `bash tests/evolve.test.sh` directly to confirm the arg-parser rewrite didn't regress the existing evolve behavior — expect `EVOLVE TESTS PASS`.

- [ ] **Step 10: Commit**

```bash
git add scripts/ss-evolve scripts/ss-evolve.ps1 tests/evolve-followups.test.sh tests/run.sh
git commit -m "feat(evolve): add --since time-windowed detection"
```

---

## Task 2: `--explore` Tier-2 structural proposals

**Model:** sonnet (shell logic + file scaffolding + parity).

**Files:**
- Modify: `scripts/ss-evolve` (add `estate`, `seen_explore`, `proposal_name`, `write_proposal`, `explore_one`; explore branch in the dispatch loop; explore tail output)
- Modify: `scripts/ss-evolve.ps1` (add `$estate`, `SeenExplore`, the `if ($Explore) { … }` branch)
- Modify: `tests/evolve-followups.test.sh` (append `--explore` cases before the final summary)

**Interfaces:**
- Consumes (from Task 1): the bash `while/shift` arg loop with the `explore` variable and the `--apply`/`--explore` mutual-exclusion guard; the ps1 `-Explore` switch and its guard.
- Produces: `scripts/ss-evolve --explore` (and `-Explore`) scaffolds `.superstack/proposals/ss-<phase>-<typeword>/SKILL.md` (`failing→gate`, `skipped→skip`), records the id in `.superstack/explore-state`, prints `proposed <name> -> <path> (review, then promote to skills/)`; `--explore --dry-run` prints `[dry-run] proposed <name> -> <path>` and writes nothing; `--explore --json` emits `[{id,name,path,type,phase,count,reason}]`; empty → `nothing new to explore` (human) or `[]` (json). Never commits.

- [ ] **Step 1: Append the failing `--explore` tests** to `tests/evolve-followups.test.sh`

Insert the following block **before** the final `echo` / summary lines (i.e. before `echo` then `[ "$fail" -eq 0 ] && …`):

```bash
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
```

- [ ] **Step 2: Run the tests to verify the `--explore` cases fail**

Run: `bash tests/evolve-followups.test.sh`
Expected: FAIL — `--explore` is unknown today, so the scaffold/state/dry-run checks fail. (`apply+explore mutually exclusive` already passes from Task 1.)

- [ ] **Step 3: Add the bash explore helpers**

In `scripts/ss-evolve`, after the `seen() { … }` line (current line 37) add:

```bash
estate="$dir/explore-state"
seen_explore() { [ -f "$estate" ] && grep -qxF "$1" "$estate"; }

proposal_name() { # type phase -> ss-<phase>-<typeword>, sanitized to [a-z0-9-]
  local tw; case "$1" in failing) tw=gate;; skipped) tw=skip;; *) tw="$1";; esac
  printf 'ss-%s-%s' "$2" "$tw" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-' | tr -s '-' | sed 's/^-//; s/-$//'
}

write_proposal() { # name type phase count reason
  local name="$1" t="$2" p="$3" c="$4" r="$5" pdir
  pdir="$dir/proposals/$name"; mkdir -p "$pdir"
  local desc="Draft proposal from a recurring $t pattern in the $p phase (seen ${c}x). Codify the fix as a reusable skill or close the underlying process gap. Authored by ss-evolve --explore; review and complete before adopting."
  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$desc"
    printf -- '---\n'
    printf '# %s\n\n' "$name"
    printf -- '<!-- DRAFT PROPOSAL - scaffolded by ss-evolve --explore.\n'
    printf '     Review, complete the body, then promote to skills/ to adopt. -->\n\n'
    printf -- '## Evidence\n'
    printf -- '- %s pattern in the `%s` phase, observed %sx%s\n' "$t" "$p" "$c" "${r:+; usual reason: \"$r\"}"
    printf -- '- Source: `.superstack/ledger.jsonl`\n\n'
    printf -- '## Proposed behavior\n'
    printf -- '<!-- TODO: the /ss-evolve skill (or a human) authors the skill body here. -->\n'
  } > "$pdir/SKILL.md"
}

explore_one() { # type phase count reason
  local t="$1" p="$2" c="$3" r="$4" id="$1:$2" name disp
  name="$(proposal_name "$t" "$p")"; disp=".superstack/proposals/$name/SKILL.md"
  if [ "$dry" -eq 0 ]; then write_proposal "$name" "$t" "$p" "$c" "$r"; mkdir -p "$dir"; printf '%s\n' "$id" >> "$estate"; fi
  if [ "$json" -eq 1 ]; then
    items="${items:+$items,}$(jq -cn --arg id "$id" --arg name "$name" --arg path "$disp" --arg t "$t" --arg p "$p" --argjson c "$c" --arg r "$r" '{id:$id,name:$name,path:$path,type:$t,phase:$p,count:$c,reason:$r}')"
  elif [ "$dry" -eq 1 ]; then
    echo "[dry-run] proposed $name -> $disp"
  else
    echo "proposed $name -> $disp (review, then promote to skills/)"
  fi
}
```

- [ ] **Step 4: Add the explore branch to the bash dispatch loop**

In `scripts/ss-evolve`, change the per-finding dispatch (current lines 57-68). Replace:

```bash
while IFS=$'\t' read -r t p c r; do
  [ -n "$t" ] || continue
  id="$t:$p"
  { [ "$newonly" -eq 1 ] || [ "$apply" -eq 1 ]; } && seen "$id" && continue
  n=$((n + 1))
  if [ "$apply" -eq 1 ]; then
    apply_one "$t" "$p" "$c" "$r"
  elif [ "$json" -eq 1 ]; then
    items="${items:+$items,}$(jq -cn --arg id "$id" --arg t "$t" --arg p "$p" --argjson c "$c" --arg r "$r" '{id:$id,type:$t,phase:$p,count:$c,reason:$r}')"
  else
    printf -- '- [%s] %s (x%s)%s\n' "$t" "$p" "$c" "${r:+ - reason: \"$r\"}"
  fi
done <<EOF
```

with:

```bash
while IFS=$'\t' read -r t p c r; do
  [ -n "$t" ] || continue
  id="$t:$p"
  if [ "$explore" -eq 1 ]; then
    seen_explore "$id" && continue
    n=$((n + 1)); explore_one "$t" "$p" "$c" "$r"; continue
  fi
  { [ "$newonly" -eq 1 ] || [ "$apply" -eq 1 ]; } && seen "$id" && continue
  n=$((n + 1))
  if [ "$apply" -eq 1 ]; then
    apply_one "$t" "$p" "$c" "$r"
  elif [ "$json" -eq 1 ]; then
    items="${items:+$items,}$(jq -cn --arg id "$id" --arg t "$t" --arg p "$p" --argjson c "$c" --arg r "$r" '{id:$id,type:$t,phase:$p,count:$c,reason:$r}')"
  else
    printf -- '- [%s] %s (x%s)%s\n' "$t" "$p" "$c" "${r:+ - reason: \"$r\"}"
  fi
done <<EOF
```

- [ ] **Step 5: Add the explore tail output to bash**

In `scripts/ss-evolve`, change the tail (current lines 73-76). Replace:

```bash
if [ "$apply" -eq 0 ] && [ "$json" -eq 1 ]; then printf '[%s]\n' "$items"
elif [ "$apply" -eq 0 ] && [ "$n" -eq 0 ]; then echo "ss-evolve: no patterns at or above threshold $threshold"
elif [ "$apply" -eq 1 ] && [ "$n" -eq 0 ]; then echo "ss-evolve: nothing new to apply"
fi
```

with:

```bash
if [ "$explore" -eq 1 ] && [ "$json" -eq 1 ]; then printf '[%s]\n' "$items"
elif [ "$explore" -eq 1 ] && [ "$n" -eq 0 ]; then echo "ss-evolve: nothing new to explore"
elif [ "$apply" -eq 0 ] && [ "$explore" -eq 0 ] && [ "$json" -eq 1 ]; then printf '[%s]\n' "$items"
elif [ "$apply" -eq 0 ] && [ "$explore" -eq 0 ] && [ "$n" -eq 0 ]; then echo "ss-evolve: no patterns at or above threshold $threshold"
elif [ "$apply" -eq 1 ] && [ "$n" -eq 0 ]; then echo "ss-evolve: nothing new to apply"
fi
```

- [ ] **Step 6: Run the bash-only `--explore` checks to verify they pass**

Run: `bash tests/evolve-followups.test.sh`
Expected: all `explore *` bash checks PASS; `explore parity` FAILs or SKIPs (ps1 not yet updated).

- [ ] **Step 7: Add the explore branch to the PowerShell twin**

In `scripts/ss-evolve.ps1`:

(a) After the `$ledger = …; $config = …; $state = …` line (current line 8), add:

```powershell
$estate = Join-Path $dir 'explore-state'
function SeenExplore([string]$id) { (Test-Path $estate) -and (Select-String -Path $estate -Pattern ([regex]::Escape($id)) -SimpleMatch -Quiet) }
```

(b) Insert a new `if ($Explore) { … }` branch **before** the existing `if ($Apply) {` (current line 32), and change that existing `if ($Apply)` to `elseif ($Apply)`:

```powershell
if ($Explore) {
  $eactive = @($findings | Where-Object { -not (SeenExplore $_.id) })
  $items = @()
  foreach ($f in $eactive) {
    $tw = if ($f.type -eq 'failing') { 'gate' } elseif ($f.type -eq 'skipped') { 'skip' } else { $f.type }
    $name = ((("ss-$($f.phase)-$tw").ToLower() -replace '[^a-z0-9-]','-') -replace '-+','-').Trim('-')
    $disp = ".superstack/proposals/$name/SKILL.md"
    if (-not $DryRun) {
      $pdir = Join-Path (Join-Path $dir 'proposals') $name
      New-Item -ItemType Directory -Force -Path $pdir | Out-Null
      $rc = if ($f.reason) { "; usual reason: ""$($f.reason)""" } else { '' }
      $desc = "Draft proposal from a recurring $($f.type) pattern in the $($f.phase) phase (seen $($f.count)x). Codify the fix as a reusable skill or close the underlying process gap. Authored by ss-evolve --explore; review and complete before adopting."
      $lines = @(
        '---'
        "name: $name"
        "description: $desc"
        '---'
        "# $name"
        ''
        '<!-- DRAFT PROPOSAL - scaffolded by ss-evolve --explore.'
        '     Review, complete the body, then promote to skills/ to adopt. -->'
        ''
        '## Evidence'
        "- $($f.type) pattern in the ``$($f.phase)`` phase, observed $($f.count)x$rc"
        '- Source: `.superstack/ledger.jsonl`'
        ''
        '## Proposed behavior'
        '<!-- TODO: the /ss-evolve skill (or a human) authors the skill body here. -->'
      )
      Set-Content -Path (Join-Path $pdir 'SKILL.md') -Value ($lines -join "`n") -Encoding utf8
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
      Add-Content $estate $f.id
    }
    if ($Json) {
      $items += [pscustomobject]@{ id = $f.id; name = $name; path = $disp; type = $f.type; phase = $f.phase; count = $f.count; reason = $f.reason }
    } elseif ($DryRun) {
      Write-Output "[dry-run] proposed $name -> $disp"
    } else {
      Write-Output "proposed $name -> $disp (review, then promote to skills/)"
    }
  }
  if ($Json) { Write-Output (@($items) | ConvertTo-Json -Compress -AsArray) }
  elseif ($eactive.Count -eq 0) { Write-Output "ss-evolve: nothing new to explore" }
}
elseif ($Apply) {
```

(The body of the former `if ($Apply)` block is unchanged; only its keyword becomes `elseif`.)

- [ ] **Step 8: Run the full follow-ups suite to verify parity passes**

Run: `bash tests/evolve-followups.test.sh`
Expected: all checks PASS including `explore parity` (or SKIP if `pwsh` absent), ending `EVOLVE-FOLLOWUPS TESTS PASS`.

- [ ] **Step 9: Run the whole suite to confirm no regressions**

Run: `bash tests/run.sh`
Expected: `[1/7]`…`[7/7]` PASS, `ALL TESTS PASS`.

- [ ] **Step 10: Commit**

```bash
git add scripts/ss-evolve scripts/ss-evolve.ps1 tests/evolve-followups.test.sh
git commit -m "feat(evolve): add --explore structural skill proposals"
```

---

## Task 3: Document `--since` + `--explore` in the skill

**Model:** haiku (pure markdown).

**Files:**
- Modify: `skills/evolve/SKILL.md`

**Interfaces:**
- Consumes: the script behavior produced by Tasks 1-2 (the `--explore` scaffolder, the `--since` window).
- Produces: updated skill instructions; no code depends on this.

- [ ] **Step 1: Update the steps + note to cover the new flags**

In `skills/evolve/SKILL.md`, replace the `## Steps` item 2 "**A new skill is warranted**" bullet (current lines 18-21) with:

```markdown
   - **A new skill is warranted** (a recurring multi-step fix worth codifying): run
     `scripts/ss-evolve --explore` to deterministically scaffold a valid stub at
     `.superstack/proposals/<name>/SKILL.md` (frontmatter + ledger evidence + a `<!-- TODO -->`
     body). Then author the `## Proposed behavior` body in that stub — a real, tailored skill
     per writing conventions (name `ss-*`, a `Use ...` description 40-500 chars, exactly one H1).
     Do NOT commit it - announce its path for the human to move into `skills/`.
```

Then add, after the existing step 4 (current line 26), a new step:

```markdown
5. Scope to a recent window when the ledger is long: `scripts/ss-evolve --since 7d` (also `24h`
   or an absolute `YYYY-MM-DD`) filters detection to that slice. Composes with `--json`,
   `--new-only`, `--apply`, and `--explore`.
```

- [ ] **Step 2: Update the `## Note` to describe the two deterministic tiers**

In `skills/evolve/SKILL.md`, replace the `## Note` paragraph (current lines 30-32) with:

```markdown
New skills are never auto-committed - they steer future agents, so they always go to
`.superstack/proposals/` for your review. Only documentation and config insights auto-apply.
Two deterministic, no-LLM script paths back this: `scripts/ss-evolve --apply` writes templated
`CONTEXT.md` entries (Tier 1, auto-commit), and `scripts/ss-evolve --explore` scaffolds proposal
stubs into `.superstack/proposals/` (Tier 2, never committed). They dedup independently
(`evolve-state` vs `explore-state`), so the same finding can be both documented and proposed.
```

- [ ] **Step 3: Verify the skill still lints clean**

Run: `bash scripts/lint-skills.sh .`
Expected: PASS (no `ss-` frontmatter errors; the skill keeps exactly one H1 and a 40-500 char description).

- [ ] **Step 4: Commit**

```bash
git add skills/evolve/SKILL.md
git commit -m "docs(evolve): document --since and --explore in the skill"
```

---

## Task 4: Surface the flags in README + CHANGELOG

**Model:** haiku (pure markdown).

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: the shipped behavior from Tasks 1-3.
- Produces: user-facing docs; nothing depends on this.

- [ ] **Step 1: Update the CHANGELOG**

Read `CHANGELOG.md`. Convert the current top `## [Unreleased]` heading to `## [0.4.0] - 2026-06-24` (keep any existing Unreleased "Changed" notes under a fresh `## [Unreleased]` above it if present), and add an `### Added` group:

```markdown
### Added
- `ss-evolve --since <window>` (`Nd` / `Nh` / `YYYY-MM-DD`) restricts detection to a recent
  slice of the ledger; composes with every other flag.
- `ss-evolve --explore` scaffolds a draft new-skill proposal into `.superstack/proposals/<name>/`
  (Tier 2) — never committed; the `/ss-evolve` skill authors the body and a human promotes it.
  Dedups independently of `--apply` via `.superstack/explore-state`.
```

Update the link-reference block at the bottom: add a `[0.4.0]` compare link mirroring the existing `[0.3.0]` entry's pattern (`…/compare/v0.3.0...v0.4.0`) and point `[Unreleased]` at `…/compare/v0.4.0...HEAD`.

- [ ] **Step 2: Surface the flags in README**

Read `README.md`. In the section that lists the proof/autonomy commands (the `/ss-evolve` row / "Under the hood" area), add a one-line note that `/ss-evolve` now supports `--since <window>` (time-windowed detection) and `--explore` (deterministic draft-skill proposals into `.superstack/proposals/`, never auto-committed). Match the surrounding table/prose style exactly; do not restructure the section.

- [ ] **Step 3: Verify markdown is intact**

Run: `bash tests/run.sh`
Expected: `ALL TESTS PASS` (docs don't affect tests, but confirm nothing else regressed).

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: surface ss-evolve --since and --explore in README + CHANGELOG"
```

---

## Self-Review (completed by plan author)

- **Spec coverage:** `--since` syntax + portable cutoff + lexicographic filter (Task 1, Steps 3-5,7) · `--explore` scaffold/name/state/never-commit/dry-run/json (Task 2) · mutual exclusion (Task 1 Step 3 guard, tested Task 2 Step 1) · Tier independence via `explore-state` (Task 2 Steps 3,7; tested) · parity (Tasks 1-2 parity checks) · description 40-500 bound (Task 2 Step 1 test) · docs + version (Tasks 3-4). All spec sections map to a task.
- **Placeholder scan:** the only `TODO` text is the intentional `<!-- TODO -->` inside the scaffolded proposal body (spec-mandated content), not a plan gap.
- **Type/name consistency:** `estate`/`explore-state`, `proposal_name`→`ss-<phase>-<typeword>`, `explore_one`/`write_proposal`, and the `failing→gate`/`skipped→skip` mapping are identical across bash and ps1 and across tasks. The display path `.superstack/proposals/<name>/SKILL.md` is used verbatim in both twins and in the tests.

---

## Execution Handoff

Recommended: **subagent-driven** — fresh implementer per task (Tasks 1-2 on sonnet, Tasks 3-4 on haiku), two-stage review between tasks, opus whole-branch review at the end.
