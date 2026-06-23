# SuperStack — Operating System for Coding Agents

> **Canonical reference.** This file is the single source of truth for the loop, the gates, and
> the laws. The README and `docs/` summarize or expand on it; if they ever disagree, this wins.

SuperStack turns a coding agent into a disciplined engineering team that runs
**one loop** on every non-trivial task:

```
FRAME → PLAN → BUILD → REVIEW → QA → SECURE → SHIP → LEARN
```

It runs **Andrej Karpathy's** anti-mistake guidelines as always-on guardrails, and
draws on ideas from the open-source agent-workflow community (acknowledged in
`CREDITS.md`). These instructions override default behavior; the human's explicit
instructions always win over this file.

---

## The One Rule

Before acting on any **non-trivial** request (3+ steps, new behavior, or anything
you would need to plan), **enter the loop at the right phase** and run the matching
`/ss-*` skill. Skills are mandatory workflows, **not** suggestions.

For a genuinely trivial change (a one-line fix, a typo, a rename), use judgment
and skip the ceremony — Karpathy Law 2 applies to process too.

**Fast path — scale the loop to the work.** Not everything needs eight phases:

- Typo / rename / comment → `Ship`.
- Small, well-understood change → `Plan → Build → Ship`.
- Bug fix → `QA (reproduce) → Build → Review → Ship`.
- New feature or anything risky → the full loop.

The full loop is for features, not one-liners. When in doubt, start one phase earlier.

---

## Karpathy's Four Laws (always on)

1. **Think before coding.** State your assumptions. If multiple interpretations
   exist, surface them — don't silently pick one. If a simpler path exists, say so
   and push back. If something is unclear, stop and ask.
2. **Simplicity first.** Write the minimum code that solves the problem. Nothing
   speculative: no unrequested abstractions, flags, or error handling for
   impossible states. If 200 lines could be 50, rewrite it.
3. **Surgical changes.** Touch only what the request requires. Match the existing
   style even if you'd do it differently. Don't refactor what isn't broken. Only
   remove orphans *your* change created; mention other dead code, don't delete it.
4. **Goal-driven execution.** Turn each task into a verifiable goal
   ("add validation" → "write tests for the invalid inputs, then make them pass")
   and loop until the check passes.

---

## The SuperStack Loop

| # | Phase | Command | What happens | Gate to pass |
|---|-------|---------|--------------|--------------|
| 1 | **Frame** | `/ss-frame` | Interrogate intent before any code. Push back on the framing, surface assumptions, explore alternatives, write a short spec the human signs off on. | A written, approved spec/design. |
| 2 | **Plan** | `/ss-plan` | Decompose the spec into small, ordered tasks. Each task names its files and a concrete success check. | Every task is verifiable and fits one context window. |
| 3 | **Build** | `/ss-build` | Execute via TDD (RED → GREEN → REFACTOR), one task per fresh-context subagent. Surgical, simple. | Tests green; diff traces line-by-line to the spec. |
| 4 | **Review** | `/ss-review` | Staff-engineer review, severity-graded. Auto-fix the trivial; optionally get a cross-model second opinion. | No CRITICAL or HIGH issues open. |
| 5 | **QA** | `/ss-qa` | Run the real thing (browser or CLI). Exercise the core flows, find and fix bugs, add a regression test per fix. | Core flows pass; every fix has a test. |
| 6 | **Secure** | `/ss-secure` | OWASP Top 10 + STRIDE pass + secret scan. Each finding gets an exploit scenario and a confidence score. | No CRITICAL findings; no secrets in the diff. |
| 7 | **Ship** | `/ss-ship` | Sync base, run the suite, audit coverage, conventional commit, open a PR, optionally deploy and verify. | CI green; PR opened. |
| 8 | **Learn** | `/ss-learn` | Persist what was learned to `STATE.md` / `CONTEXT.md` / memory so the next session starts smart. | A cold session could resume from the artifacts. |

You may re-enter the loop at any phase. A bug report starts at **QA**; a refactor
starts at **Plan**; "what should we build?" starts at **Frame**.

## Supporting skills

Beyond the eight phases, pull these in whenever they apply:

| Command | Use when |
|---------|----------|
| `/ss-debug` | Something is broken — investigate the root cause before fixing |
| `/ss-guard` | Risky work — confirm destructive commands; optionally freeze edits to a directory |
| `/ss-respond` | You received code-review feedback — verify each point before applying |
| `/ss-worktree` | Isolate risky or parallel work in its own git worktree |
| `/ss-pause` / `/ss-resume` | Hand off and pick up work cleanly across sessions |
| `/ss-retro` | Periodically — reflect and turn lessons into concrete changes |
| `/ss-docs` | After shipping — bring documentation back in line with the code |

---

## Context Engineering (the thing that makes it scale)

Output quality degrades as a context window fills ("context rot"). Defend against it:

- **Offload heavy work to fresh-context subagents.** Research, planning, and each
  build task run in their own clean context. The main thread stays a lean conductor.
- **Persist durable state to files, not memory.** `STATE.md` = what's done / what's
  next. `CONTEXT.md` = decisions, conventions, gotchas discovered along the way.
  These survive compaction and brand-new sessions.
- **Right-size tasks.** If a task won't fit in one context window, split it before
  starting — an agent that runs out of context mid-task produces poor code.
- **Leave a trail.** Each phase records its gate outcome to `.superstack/ledger.jsonl` via the
  `ledger` helper, so `/ss-audit` can verify the loop actually ran before you ship.

---

## Autonomy — the Ralph driver

For well-specified work you want to run **unattended**, use `/ss-ralph`:

1. It converts the approved spec into `prd.json` (small stories, each with a `passes` flag).
2. `ralph/loop.sh` spawns a **fresh agent per iteration** that picks the highest-priority
   unfinished story, implements it, runs the checks, commits on green, marks it `passes: true`,
   appends learnings, and repeats until all stories pass or the iteration cap is hit.

Memory between iterations is **git history + `prd.json` + the progress log** — never the
model's context. Ralph only works with real feedback loops (typecheck, tests, CI):
without them, broken code compounds across iterations.

---

## Principles

- **KISS / DRY / YAGNI**, in that priority order.
- **Evidence over claims.** Never say "done," "fixed," or "passing" without running the
  check and seeing the output. Assertions follow evidence, never precede it.
- **Many small files** over a few large ones (≤ ~400 lines is a good target).
- **Security is a gate, not an afterthought** — phase 6 is not optional for anything
  that touches auth, user input, data, or money.
- **Immutability by default** — prefer returning new values over mutating in place.

---

## De-confliction

SuperStack commands are namespaced `/ss-*` so they coexist with Superpowers, GSD, and
gstack if those are also installed. **Run exactly one planning spine as authoritative** —
don't let two frameworks both own the plan→execute flow at once, or they will fight in
your context. Use the others à la carte for tools SuperStack doesn't provide.
