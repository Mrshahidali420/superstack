---
name: ss-debug
description: Use when something is broken, failing, or behaving unexpectedly — before proposing a fix. Enforces systematic root-cause investigation: reproduce, hypothesize, find the actual cause, then fix and verify instead of guessing.
---

# Debug — systematic root cause

The Iron Law: **no fix without an understood cause.** Guessing burns iterations and adds risk.

## Steps

1. **Reproduce it reliably.** Write a failing test or a minimal repro before touching code.
2. **Form one hypothesis** — state what you think is wrong and why, in a sentence.
3. **Find the actual cause** — trace the data flow, read the real error, check the boundary.
   Don't pattern-match a fix onto a symptom.
4. **Fix the cause, surgically** (Karpathy Law 3), then confirm the repro now passes.
5. **Stop after 3 failed fixes.** Three misses means the hypothesis is wrong — step back,
   gather more evidence, or ask. Don't keep flailing.

## Gate

The failing repro passes and you can state the root cause in one sentence. Then `/ss-review`.

## Lineage

Superpowers `systematic-debugging` (root-cause-tracing, condition-based-waiting) + gstack `/investigate`.
