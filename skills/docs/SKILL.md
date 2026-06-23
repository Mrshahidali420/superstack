---
name: ss-docs
description: Use after shipping a feature, or when docs have drifted, to bring documentation back in line with the code. Updates or generates docs across the four Diataxis types and flags coverage gaps.
---

# Docs — keep documentation true

## Steps

1. **Diff against the docs.** Cross-reference what changed in code against README, ARCHITECTURE,
   CONTRIBUTING, CLAUDE.md, and any guides.
2. **Update what drifted** — stale examples, renamed flags, changed behavior.
3. **Fill gaps by Diataxis type:** tutorial (learning), how-to (task), reference (facts),
   explanation (why). Note which types are missing.
4. **Verify examples actually run** — a doc example that errors is worse than no example.

## Gate

Docs match the shipped behavior; remaining coverage gaps are listed (or filled).

## Lineage

gstack `/document-release` + `/document-generate` (Diataxis framework).
