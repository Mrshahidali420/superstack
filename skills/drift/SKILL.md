---
name: ss-drift
description: Use during Review or Ship to confirm the build stayed within its approved plan - it compares the plan's declared files against what the branch actually changed and reports unplanned changes (scope creep) and planned-but-untouched files. Read-only; exits non-zero on drift for CI.
---

# Drift - did the build match the plan?

Read-only check. Point it at the plan you executed; it compares the files the plan declared against
what the branch actually changed (vs a base, default `main`) and reports the divergence both ways.

## Steps

1. Run `scripts/ss-drift <plan-file> [base]` (PowerShell: `scripts/ss-drift.ps1 <plan-file> [base]`).
   `base` defaults to `main`; pass it explicitly if the branch forked from elsewhere.
2. Read the report:
   - **unplanned changes** (`+`) - files the branch changed that the plan never named. This is the
     scope-creep signal; either fold them into the plan or revert them.
   - **planned but untouched** (`-`) - declared files the branch hasn't changed yet (incomplete, or
     the plan over-declared). Advisory - a mid-build branch legitimately has these.
3. Act on the verdict: `CLEAN` (exit 0) or `DRIFT` (exit 1 - safe to use as a Review/Ship/CI gate).

## Note

`/ss-drift` is read-only and file-scoped: it reasons about the plan's `**Files:**` blocks vs `git diff`,
ignores `docs/specs/` (the plan/spec docs themselves), and does not check phase order (the loop allows
legitimate re-entry). It is the build-vs-plan companion to [[ss-audit]]'s phase-gate proof.

## Lineage

Original to SuperStack - drift detection (desired-vs-actual, after Terraform's model) applied to
"did the implementation stay within the approved plan."
