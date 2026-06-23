---
name: ss-build
description: Use to implement a planned task or feature. Executes via test-driven development (RED-GREEN-REFACTOR), one task per fresh-context subagent, making surgical and minimal changes that trace directly to the spec.
---

# Build

The third phase. Implement the plan with TDD discipline.

## The cycle (per task)

1. **RED** — write the failing test first. Run it. Watch it fail for the right reason.
2. **GREEN** — write the minimum code to pass. Run it. Watch it pass.
3. **REFACTOR** — clean up while tests stay green. Commit.

Any implementation code written before its test gets deleted and redone test-first.

## Rules

- **One task per fresh-context subagent.** Dispatch each task with the plan entry as
  its brief; the main thread stays a conductor. Independent tasks run as a parallel wave.
- **Simplicity first** — the minimum that passes the test, nothing speculative. If it
  ballooned, rewrite smaller. (Karpathy Law 2.)
- **Surgical** — every changed line traces to the task. Don't refactor adjacent code,
  don't reformat, don't fix unrelated things. Only remove orphans your change created.
  (Karpathy Law 3.)

## Gate

All tests green; the diff maps line-by-line to the plan/spec. Then `/ss-review`.

## Lineage

Superpowers `test-driven-development` + `subagent-driven-development` + GSD `execute` waves.
