# ss-evolve follow-ups: `--since` + `--explore` (v0.4.0)

- **Date:** 2026-06-24
- **Status:** Approved (design)
- **Target version:** v0.4.0 (minor, backward-compatible)
- **Builds on:** [2026-06-23-ss-evolve-design.md](2026-06-23-ss-evolve-design.md)

## 1. Context

`/ss-evolve` shipped in v0.3.0. It reads `.superstack/ledger.jsonl`, detects two
recurring patterns — `skipped-phase` and `failing-gate` — at or above
`evolve_threshold` (default 3), and offers a **Tier-1** action (`--apply`): append
a templated note to `CONTEXT.md` and make one `chore(evolve): document <id>`
commit. New-skill **proposals** exist only as an idea in the skill layer; there is
no explicit, testable mechanism that produces them, and there is no way to scope
the analysis to a time window.

This spec adds two flags to `scripts/ss-evolve` (and its `.ps1` twin):

- `--since <window>` — restrict detection to a recent slice of the ledger.
- `--explore` — a **Tier-2** action: deterministically scaffold a *draft* new-skill
  proposal under `.superstack/proposals/`, which the `/ss-evolve` skill then
  fleshes out and a human promotes by hand.

## 2. Goals / Non-goals

**Goals**
- Time-windowed detection that composes with every existing mode.
- A real, testable, parity-covered path that turns a recurring finding into a
  *structural* proposal (a draft skill), without ever auto-adopting it.
- Preserve the existing safety invariant: nothing structural lands automatically.

**Non-goals (deferred)**
- `--pr` / framework-level upstream PR drafting — its own design pass later.
- A separate `explore_threshold` config key — reuse `evolve_threshold` for now;
  trivial to add later if the single threshold proves too eager.
- Broadening detection beyond the existing `skipped` / `failing` signals.

## 3. Ledger facts this design relies on

- Schema (one JSON object per line): `{ts, change, phase, event, status, note}`
  (`scripts/ledger`).
- `ts` is written as `date -u +%Y-%m-%dT%H:%M:%SZ`, i.e. zero-padded UTC ISO-8601
  with a `Z` suffix (`scripts/ledger:11`). **Therefore lexicographic string
  comparison on `ts` is equivalent to chronological comparison** — the basis for
  `--since`.
- Findings have shape `{id, type, phase, count, reason}` with
  `id = "<type>:<phase>"` (e.g. `skipped:secure`, `failing:review`).

## 4. Feature: `--since <window>`

### 4.1 Accepted syntax
| Form | Meaning |
|------|---------|
| `Nd` | last N days (e.g. `7d`) |
| `Nh` | last N hours (e.g. `24h`) |
| `YYYY-MM-DD` | inclusive from `00:00:00Z` on that date (e.g. `2026-06-01`) |

Anything else → usage error on stderr, exit 1.

### 4.2 Mechanic (portable, parity-safe)
1. Resolve `<window>` to a **cutoff ISO timestamp** string `%Y-%m-%dT%H:%M:%SZ`:
   - `Nd` / `Nh`: compute the offset **in jq**, not platform `date` —
     `jq -n --argjson off <secs> 'now - $off | todate'` (where `secs = N*86400`
     for days, `N*3600` for hours). This avoids the GNU (`date -d`) vs BSD
     (`date -v`) divergence; jq is already a hard dependency. PowerShell:
     `[DateTime]::UtcNow.AddDays(-N)` / `.AddHours(-N)` then
     `.ToString("yyyy-MM-ddTHH:mm:ssZ")`.
   - `YYYY-MM-DD`: no computation — `"<date>T00:00:00Z"`.
2. Filter the input stream with **lexicographic** `.ts >= cutoff` *before* detection.
   - bash/jq: add `select(.ts >= $cutoff)` to the `[inputs]` pipeline, passing
     `--arg cutoff "<cutoff>"`.
   - PowerShell: `Where-Object { $_.ts -ge $cutoff }` on the parsed objects.
3. `--since` composes with `--json`, `--new-only`, `--apply`, `--explore`,
   `--dry-run` — it only narrows the candidate ledger rows.

### 4.3 Determinism note
Relative windows (`Nd`/`Nh`) depend on the current clock, so **parity and
detection tests use absolute `--since YYYY-MM-DD`** against a seeded ledger. The
relative→cutoff arithmetic is unit-checked separately (given a fixed "now", `7d`
yields the expected cutoff string) but never asserted against a live clock.

## 5. Feature: `--explore` (Tier-2 structural proposals)

### 5.1 Division of labor
- **Script (`scripts/ss-evolve --explore`)** — deterministic. For each qualifying
  *new* finding it scaffolds a valid, self-contained proposal stub and records it.
  It authors **no judgment-bearing body** and **never commits**.
- **Skill (`skills/evolve/SKILL.md`)** — judgment. It runs the script, then authors
  the real proposal body per stub, presents the set for review, and hands the user
  the promote command. It does not commit either.

### 5.2 Qualifying findings
Reuse existing detection and `evolve_threshold`. A finding qualifies for `--explore`
if it meets threshold **and** its id is not already in `.superstack/explore-state`
(when `--new-only` or `--explore` filtering applies — `--explore` always filters by
explore-state so re-runs are idempotent).

### 5.3 Proposal name derivation (deterministic)
`ss-<phase>-<typeword>` where `typeword` maps `failing → gate`, `skipped → skip`;
lowercased and sanitized to `[a-z0-9-]` (collapse runs of non-matching chars to a
single `-`, trim leading/trailing `-`). Examples:
- `failing:review` → `ss-review-gate`
- `skipped:secure` → `ss-secure-skip`

### 5.4 Scaffold written by the script
Path: `.superstack/proposals/<name>/SKILL.md`. The stub is written only when the
finding's id is **not** in `.superstack/explore-state`; recorded findings are
skipped entirely (so in normal use a stub is written exactly once, then recorded).

Exact template (ASCII only; `<...>` substituted):

```
---
name: <name>
description: Draft proposal from a recurring <type> pattern in the <phase> phase (seen <count>x). Codify the fix as a reusable skill or close the underlying process gap. Authored by ss-evolve --explore; review and complete before adopting.
---
# <name>

<!-- DRAFT PROPOSAL - scaffolded by ss-evolve --explore.
     Review, complete the body, then promote to skills/ to adopt. -->

## Evidence
- <type> pattern in the `<phase>` phase, observed <count>x[ ; usual reason: "<reason>"]
- Source: `.superstack/ledger.jsonl`

## Proposed behavior
<!-- TODO: the /ss-evolve skill (or a human) authors the skill body here. -->
```

- The `description` line is engineered to land within the **40–500 char**
  frontmatter window for the shortest realistic substitution and stays under 500
  for the longest. Implementer adds a test asserting both bounds.
- The `[ ; usual reason: "<reason>"]` clause is included only when `reason` is
  non-empty (mirrors the existing `--apply` template behavior).
- Exactly one H1 (`# <name>`); `name:` equals the directory name.

### 5.5 State + dedup
- New file: `.superstack/explore-state`, newline-delimited finding ids, identical
  format to `.superstack/evolve-state`.
- **Separate namespace from `--apply`.** A finding may be both documented (Tier 1,
  recorded in `evolve-state`) and proposed (Tier 2, recorded in `explore-state`)
  independently; neither suppresses the other.
- After scaffolding a proposal, append its id to `explore-state`. Re-running
  `--explore` then skips it (idempotent).

### 5.6 Never commit
`scripts/ss-evolve --explore` performs **no `git add` / `git commit`**.
`.superstack/` is already in `.gitignore`, so proposals are untracked by default.
Adoption is a deliberate human act: `mv .superstack/proposals/<name> skills/<name>`
then commit.

### 5.7 `--explore --dry-run`
Print intent, write nothing, record nothing, create no directories.

### 5.8 Skill-layer behavior (`skills/evolve/SKILL.md`)
Add an explore path:
1. Run `scripts/ss-evolve --explore` (scaffolds stubs for new findings).
2. For each scaffolded stub, author the `## Proposed behavior` body — a tailored,
   real skill description for closing that finding's gap, per writing-skills
   conventions. Keep frontmatter valid.
3. Present the completed proposals to the user with the exact promote command and a
   reminder that proposals are gitignored and never auto-adopted.
4. Do not commit; the human promotes.

## 6. CLI surface (after this change)

```
ss-evolve [--since <window>] [--json] [--new-only] [--apply | --explore] [--dry-run]
```

- `--apply` and `--explore` are the two mutually-distinct *actions*; if both are
  passed, error on stderr, exit 1 (keeps each run single-purpose and testable).
- `--since` / `--json` / `--new-only` / `--dry-run` modify either action or the
  default report.
- Default (no action): human-readable findings list (unchanged).

## 7. Output formats

### 7.1 `--explore` human output
Per scaffolded finding:
```
proposed <name> -> .superstack/proposals/<name>/SKILL.md (review, then promote to skills/)
```
Dry-run:
```
[dry-run] proposed <name> -> .superstack/proposals/<name>/SKILL.md
```
Nothing new:
```
ss-evolve: nothing new to explore
```

### 7.2 `--explore --json`
Compact array, one object per scaffolded finding:
```json
[{"id":"failing:review","name":"ss-review-gate","path":".superstack/proposals/ss-review-gate/SKILL.md","type":"failing","phase":"review","count":"4","reason":""}]
```
Dry-run `--json` reports what *would* be written with the same shape (no files).

### 7.3 Parity
Both flags produce **byte-identical** output across `scripts/ss-evolve` and
`scripts/ss-evolve.ps1`: ASCII only, `jq … < "$ledger"` stdin redirect on bash,
`tr -d '\r'` normalization, PowerShell `ConvertFrom-Json` + `Write-Output`.

## 8. Test plan

Extend `tests/evolve.test.sh` (or add `tests/explore.test.sh` wired into
`tests/run.sh`). All ledger seeds use fixed timestamps / absolute dates.

1. **`--since` filtering** — seed rows straddling a date; `--since 2026-06-01`
   includes only rows `>=` cutoff; below-cutoff rows excluded; composes with
   detection (a pattern that only meets threshold within the window).
2. **`--since` cutoff arithmetic** — given a fixed reference, `7d`/`24h` map to the
   expected cutoff string (no live-clock assertion).
3. **`--explore` scaffold** — writes `.superstack/proposals/<name>/SKILL.md`;
   assert: directory + file exist; `name:` equals dir; exactly one H1; description
   length within `[40, 500]`; evidence block contains type/phase/count.
4. **Never committed** — after `--explore`, `git status` shows the proposal
   untracked/ignored and no new commit was created.
5. **explore-state dedup** — second `--explore` run scaffolds nothing new;
   `--explore --json` returns `[]`.
6. **Tier independence** — `--apply` then `--explore` on the same finding both
   fire; `evolve-state` and `explore-state` each hold the id.
7. **`--explore --dry-run`** — prints intent; no file, dir, state, or commit created.
8. **Mutual exclusion** — `--apply --explore` errors, exit 1.
9. **Parity** — bash vs `pwsh` byte-identical for `--since` and `--explore`
   (skipped when `pwsh` absent, same guard as existing tests).

## 9. Docs / version impact
- `skills/evolve/SKILL.md` — document `--since`, `--explore`, the Tier-2 promote flow.
- `README.md` — commands / under-the-hood note for `--since` and `--explore`.
- `CHANGELOG.md` — `[Unreleased]` → `[0.4.0]` with both flags.
- `.claude-plugin/plugin.json` + `marketplace.json` — version bump at release time.

## 10. Risks
- **Description length bounds** — the template must satisfy 40–500 chars across all
  substitutions; covered by an explicit test (§8.3).
- **`ts` format drift** — `--since` assumes the `scripts/ledger` `ts` format; if that
  ever changes, lexicographic comparison breaks. The dependency is documented here
  and the implementer asserts the format in a test seed.
- **Proposal name collisions** — two findings mapping to the same `<name>` is
  impossible given `id = type:phase` is unique and the name is a 1:1 function of it.
```
