---
name: ss-ralph
description: Use to run a well-specified body of work unattended. Converts an approved spec into a prd.json of small stories and runs the autonomous loop until every story passes its checks, with memory persisted in git and files rather than the model's context.
---

# Ralph — autonomous driver

The autonomy wrapper around the loop. For when the spec is crisp and you want to walk away.

## Steps

1. **Convert the approved spec into `prd.json`** — a list of small stories, each with a
   title, acceptance criteria, a priority, and `passes: false`. Right-size every story to
   one context window (a column + migration, one component, one server action). Split
   anything bigger.
2. **Run the loop:** `ralph/loop.sh [max_iterations]` (or `loop.ps1` on Windows).
   Each iteration is a **fresh agent** that:
   - picks the highest-priority story where `passes` is false,
   - implements just that story,
   - runs the quality checks (typecheck, tests),
   - commits if they pass and sets `passes: true`,
   - appends what it learned to the progress log,
   - repeats until all stories pass or the cap is hit.
3. **Memory between iterations is git history + `prd.json` + the progress log** — never
   the model's context. That is what keeps quality up across a long run.

## Requirements

Real feedback loops (typecheck / tests / CI) must exist, or broken code compounds across
iterations. Keep CI green.

## Lineage

The Ralph pattern (Geoffrey Huntley); implementations by snarktank and iannuttall.
