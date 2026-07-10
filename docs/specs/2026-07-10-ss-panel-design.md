# /ss-panel — unified ledger dashboard — Design + plan

Status: direction pre-approved (README roadmap: "a unified dashboard over the ledger —
report + replay + trace in one view"). Composition decisions below are build-level.

## Problem

Understanding one change today takes three commands read in the right order:
`/ss-report` (the shareable summary), `/ss-replay` (the chronological story),
`/ss-trace` (spec → gates → commits provenance). Each resolves its own default
change, so the three views can even disagree about *which run* they show.

## Approach — a thin composer, zero new analysis

`ss-panel [change] [--save]` (bash + ps1 twins, read-only, exit 2 without jq):

1. Resolve the change **once** (same rule as replay: last ledger entry's `.change`;
   explicit argument wins) and pass it to every leg — one run, three consistent views.
2. Run the sibling scripts in reading order — **report → replay → trace** — verbatim,
   separated by the house 54-dash separator, under a one-line banner:
   `ss-panel: <change> - report + replay + trace`.
3. A leg that exits nonzero prints `  (ss-<leg> unavailable - exit N)` and the panel
   moves on (e.g. trace outside a git repo). Panel itself exits 0 once composed.
4. `--save` mirrors the replay convention: fenced output to
   `.superstack/replays/panel-<change with / -> ->.md`.

No new analysis, no duplicated jq — the legs stay the single source of each view.
`ss-stats` stays out: it is cross-run, the panel is one change (the README definition).

## Components / files

- Create: `scripts/ss-panel`, `scripts/ss-panel.ps1`, `tests/panel.test.sh`,
  `skills/panel/SKILL.md`
- Modify: `tests/run.sh` (18th suite), `README.md` (32 skills; What's new; roadmap),
  `CHANGELOG.md`

## Testing (RED first)

Fixture: two-run ledger (feat/a older, feat/b latest — replay's fixture shape), run
from a clean temp cwd so trace finds no stray specs/commits. Checks: banner shows
default change feat/b; explicit feat/a honored across legs; three leg headers present
**in order**; `--save` writes the fenced panel file; unknown flag exits 1; missing
ledger exits 1; bash/ps1 full-output byte parity.

## Tasks

1. Spec (this doc) + `feat/ss-panel` branch + ledger frame/plan entries (dogfood).
2. `tests/panel.test.sh` (RED) → `scripts/ss-panel` (GREEN) → `ss-panel.ps1`
   (parity GREEN) → wire `tests/run.sh`.
3. `skills/panel/SKILL.md` + README + CHANGELOG + lint + full suite + ff-merge.

## Decided defaults (open to review)

- Section order report → replay → trace (summary, then story, then provenance).
- Banner wording `ss-panel: <change> - report + replay + trace`.
- Save filename prefix `panel-` in the existing `replays/` dir (no new dir).
- jq required up front (exit 2, matching trace/stats) rather than per-leg skips.
