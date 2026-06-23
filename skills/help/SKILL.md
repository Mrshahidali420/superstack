---
name: ss-help
description: Use when you want the SuperStack command index — lists the loop, every /ss-* command, and where to enter. Run this to see what SuperStack can do or to remember a command.
---

# Help — the SuperStack index

The loop, end to end:

```
FRAME → PLAN → BUILD → REVIEW → QA → SECURE → SHIP → LEARN
        (context engineering underneath · /ss-ralph for autonomy)
```

## Commands

| Command | Phase | Does |
|---------|-------|------|
| `/ss-frame` | Frame | Interrogate intent, push back, write a spec you sign off on |
| `/ss-plan` | Plan | Break the spec into small, individually verifiable tasks |
| `/ss-build` | Build | TDD execution, one task per fresh subagent |
| `/ss-review` | Review | Staff-eng review, severity-graded, auto-fix the trivial |
| `/ss-qa` | QA | Run the app, find and fix bugs, add regression tests |
| `/ss-secure` | Secure | OWASP + STRIDE pass + secret scan |
| `/ss-ship` | Ship | Coverage gate, conventional commit, PR, optional deploy |
| `/ss-ralph` | Autonomy | Run the loop unattended until a PRD is fully done |
| `/ss-learn` | Learn | Persist learnings so the next session starts smart |
| `/ss-help` | — | This index |

## Supporting skills

Cross-cutting and periodic — pull them in at any phase:

| Command | Use when |
|---------|----------|
| `/ss-debug` | Something's broken — root-cause it before fixing |
| `/ss-guard` | Risky work — warn before destructive commands; freeze edits to a dir |
| `/ss-respond` | You received code-review feedback — verify before applying |
| `/ss-worktree` | Isolate risky or parallel work in its own git worktree |
| `/ss-pause` · `/ss-resume` | Hand off / pick up work across sessions |
| `/ss-retro` | End of a sprint — reflect and turn lessons into changes |
| `/ss-docs` | After shipping — bring docs back in line with the code |

## Where to enter

- "What should we build?" → **`/ss-frame`**
- "Implement this spec." → **`/ss-plan`**
- "This is broken." → **`/ss-qa`** (reproduce → fix → regression test)
- "Refactor X." → **`/ss-plan`** with "tests green before and after" as the goal
- "Run this unattended." → **`/ss-ralph`**

## Fast path

Scale the loop to the work — a typo is just `Ship`; a small change is
`Plan → Build → Ship`. The full eight phases are for features, not one-liners.

Full reference: `CLAUDE.md` · `docs/workflow.md` · `docs/philosophy.md`.
