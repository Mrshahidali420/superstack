---
name: ss-frame
description: Use at the very start of any new feature, product idea, or non-trivial build — BEFORE planning or writing code. Interrogates intent, surfaces assumptions, explores alternatives, and produces a short spec the human signs off on.
---

# Frame

The first phase of the SuperStack loop. Do **not** jump to code. Tease out what the
human is actually trying to do, then write it down.

## Steps

1. **Don't start building.** When you see a build request, step back and ask what
   they're really trying to accomplish and for whom.
2. **Surface assumptions and interpretations.** If the request has more than one
   reasonable reading, present them — don't silently pick one. (Karpathy Law 1.)
3. **Push back when warranted.** If a simpler shape, a narrower wedge, or a different
   framing is better, say so. Often the stated feature isn't the real need.
4. **Explore 2–3 approaches** with rough effort/risk for each. Recommend one.
5. **Write a short spec** — problem, scope (and non-goals), the chosen approach,
   success criteria. Show it in chunks small enough to actually read.
6. **Get explicit sign-off**, then save to `specs/<slug>.md`.

## Gate

A written spec the human has approved. That spec is the input to `/ss-plan`.

## Lineage

Superpowers `brainstorming` + gstack `/office-hours` + Karpathy "think before coding".
