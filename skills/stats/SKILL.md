---
name: ss-stats
description: Use periodically (or before a retro) to see how the loop is trending across runs - a read-only dashboard of the per-run table (phases, gate-fails, skips, span) plus a rollup (gate-fail rate, skips, and an improving/worsening/flat trend). Distinct from /ss-report (one run) and /ss-evolve (acts on patterns).
---

# Stats - is the loop getting better?

Read-only cross-run analytics. It groups the ledger into runs (one per `change`/branch) and shows the
recent ones as a table plus a trend rollup. The point is **direction** - is your process improving? -
not absolute scores (after the DORA guidance that trend beats any single number).

## Steps

1. Run `scripts/ss-stats` (PowerShell: `scripts/ss-stats.ps1`). Optional:
   - `--since <Nd|Nh|YYYY-MM-DD>` - restrict to a recent window.
   - `--limit N` - cap the table to the N most recent runs (default 10; the rollup still spans the window).
2. Read the table (most recent run first): `change` / `date` / `phases` / `fails` (gate-fails) /
   `skips` / `span`.
3. Read the rollup: `gate-fail rate` (cadence shown beside quality, never alone), total `skips`, and
   `trend` - `improving` / `worsening` / `flat` (older half vs newer half; `n/a` under 4 runs).

## Note

`/ss-stats` is read-only and never a gate - a "bad" trend is a signal to reflect, not a failure. It
does NOT flag per-phase recurring patterns or propose fixes; that is [[ss-evolve]]. Feed its output
into a periodic [[ss-retro]].

## Lineage

Original to SuperStack - the cross-run companion to [[ss-report]] (one run), applying DORA-style
trend thinking (gate-fail rate as the change-failure-rate analog) to the loop ledger.
