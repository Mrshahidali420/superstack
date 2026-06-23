---
name: ss-plan
description: Use after a spec is approved and before building. Decomposes the work into small, ordered, individually verifiable tasks — each with the files it touches and a concrete success check — and confirms the plan fits a fresh context window.
---

# Plan

The second phase. Turn an approved spec into a task list a junior engineer could
execute without judgment.

## Steps

1. **Read the spec and the relevant code.** If the codebase is large, do this in a
   subagent and return only the map you need — keep the main thread lean.
2. **Decompose into small tasks.** Each task should fit in one context window. For
   every task, write down: the files it touches, the exact change, and a concrete
   **success check** (a test to write, a command to run, an output to observe).
3. **Order by dependency.** Mark which tasks are independent so they can run as a
   parallel wave during Build.
4. **Wire a feedback loop into every requirement** — map a test or check to each, so
   Build always has something that can confirm the task is done. (Karpathy Law 4.)
5. **Write `PLAN.md`.** Re-read it: could an enthusiastic junior with no context
   follow it exactly? If not, tighten it.

## Gate

Every task is individually verifiable and fits one context window.

Record the outcome: `ledger plan gate pass` — or `ledger plan skip skip "<reason>"` if you deliberately skipped this phase.

## Lineage

Superpowers `writing-plans` + GSD `plan` phase + gstack `/plan-eng-review`.
