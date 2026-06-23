---
name: ss-review
description: Use after writing or modifying code and before shipping. Runs a staff-engineer code review against the diff, grades findings by severity, auto-fixes the trivial ones, and can request a cross-model second opinion.
---

# Review

The fourth phase. Find the bugs that pass CI but blow up in production.

## Steps

1. **Diff against the base branch** to see exactly what changed.
2. **Review for:**
   - Correctness — logic errors, edge cases, off-by-ones, race conditions.
   - Security — injection, auth gaps, unsafe input handling (deep pass is `/ss-secure`).
   - Error handling — failures handled explicitly, no silently swallowed errors.
   - Complexity — anything overcomplicated for what it does.
   - Dead code and orphans introduced by the change.
   - Tests — new behavior has coverage.
3. **Grade each finding:** `CRITICAL` / `HIGH` / `MEDIUM` / `LOW`.
4. **Auto-fix** the obvious LOW/MEDIUM issues. **Surface** CRITICAL/HIGH for a decision.
5. **Optional second opinion** — ask a different model/agent to review the same diff and
   cross-compare; findings both agree on are high-confidence.

## Gate

No CRITICAL or HIGH issues left open. Then `/ss-qa`.

## Lineage

Superpowers `requesting-code-review` + gstack `/review` and `/codex` second opinion.
