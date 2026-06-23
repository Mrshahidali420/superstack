# The SuperStack Loop

One loop runs on every non-trivial task. Each phase has a **gate** it must clear before
the next begins, and you can **re-enter** the loop wherever the work actually starts.

```
        ┌───────────────────────  context engineering  ───────────────────────┐
        │      fresh-context subagents  ·  STATE.md  ·  CONTEXT.md             │
        └─────────────────────────────────────────────────────────────────────┘

   FRAME ──▶ PLAN ──▶ BUILD ──▶ REVIEW ──▶ QA ──▶ SECURE ──▶ SHIP ──▶ LEARN
    spec     tasks     TDD       bugs      app    OWASP       PR       memory
                         ▲                                      │
                         └──────────  /ss-ralph (autonomous) ───┘
```

## Phases and gates

| Phase | Command | Gate |
|-------|---------|------|
| Frame | `/ss-frame` | A written spec the human approved |
| Plan | `/ss-plan` | Every task is verifiable and fits one context window |
| Build | `/ss-build` | Tests green; the diff traces line-by-line to the spec |
| Review | `/ss-review` | No CRITICAL or HIGH issues open |
| QA | `/ss-qa` | Core flows pass; every fix has a regression test |
| Secure | `/ss-secure` | No CRITICAL findings; no secrets in the diff |
| Ship | `/ss-ship` | CI green; PR opened (or merged + verified) |
| Learn | `/ss-learn` | A cold session could resume from the artifacts |

## Where to enter

- **"What should we build?"** → start at **Frame**.
- **"Implement this spec."** → start at **Plan**.
- **"This is broken."** → start at **QA** (reproduce → fix → regression test), then Review.
- **"Refactor X."** → start at **Plan**, with "tests green before and after" as the goal.
- **"Run this unattended."** → **Ralph** wraps Build → Ship for a whole `prd.json`.

## Why the gates matter

Gates are how the loop stays honest. A phase is not "done" because the agent says so — it
is done when its gate's check has been run and the output observed. This is the
*evidence over claims* rule made structural: no phase advances on a promise.

## Context engineering runs underneath every phase

- Heavy work (research, planning, each build task) runs in a **fresh-context subagent** so
  the main thread never fills up and degrades.
- Durable state lives in **`STATE.md`** (done / next) and **`CONTEXT.md`** (decisions,
  conventions, gotchas) — not in the chat. They survive compaction and new sessions.
- Tasks are **right-sized to one context window**. If a task won't fit, it gets split
  before Build starts.

This is what lets the loop run for hours — or fully autonomously under Ralph — without the
quality decay that kills long single-context sessions.
