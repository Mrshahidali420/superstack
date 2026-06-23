---
name: ss-respond
description: Use when you receive code-review feedback — from a human, /ss-review, or another model — before implementing it. Evaluate each point on its merits, verify it, push back on what's wrong or unclear, then apply only the valid ones.
---

# Respond — receiving code review

Feedback is input, not orders. Blindly implementing wrong suggestions adds bugs; performative
agreement wastes everyone's time.

## Steps

1. **Separate the points.** List each piece of feedback discretely.
2. **Verify each on its merits.** Is it actually correct? Reproduce or check before acting.
   (Evidence over claims.)
3. **Push back when warranted.** If a suggestion is wrong, risky, or unclear, say so with
   reasoning and ask — don't comply just to agree. (Karpathy Law 1.)
4. **Apply the valid ones surgically**, each change traceable to a specific comment.
5. **Reply** with what you changed, what you declined, and why.

## Gate

Every comment is resolved — applied, declined with a reason, or escalated. No silent drops.

## Lineage

Superpowers `receiving-code-review`.
