<div align="center">

# SuperStack

**One disciplined loop for your coding agent.**

Frame → Plan → Build → Review → QA → Secure → Ship → Learn.

A distillation of [Superpowers](https://github.com/obra/superpowers), [GSD](https://github.com/open-gsd/gsd-core), [gstack](https://github.com/garrytan/gstack), and [Ralph](https://github.com/snarktank/ralph) — with [Karpathy's](https://github.com/forrestchang/andrej-karpathy-skills) anti-mistake laws baked in.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-7c3aed.svg)](https://github.com/Mrshahidali420/superstack) ![status v0.1](https://img.shields.io/badge/status-v0.1-orange.svg)

Built for Claude Code today; portable to other skill-aware agents.

</div>

---

## Why this exists

There are four great workflow frameworks for coding agents, and they overlap and
collide. Run more than one and you get duplicate `/review`, `/learn`, and `/ship`
commands, two planning flows fighting in your context, and token bloat from a dozen
auto-triggering skills.

SuperStack is the opinionated merge: **one loop**, taking the single best idea from
each, namespaced `/ss-*` so it never collides with what you already have.

| From | SuperStack takes |
|------|------------------|
| **Superpowers** | Spec-first discipline, true RED-GREEN-REFACTOR TDD, mandatory (not optional) skills |
| **GSD** | The phase loop, context-rot mitigation, durable `STATE.md` / `CONTEXT.md` |
| **gstack** | Review / QA / security / ship gates that act like a real eng team |
| **Ralph** | An autonomous loop for unattended, spec-driven runs |
| **Karpathy** | Four laws that stop the most common LLM coding mistakes |

This repo **re-implements the ideas in its own words** — it does not vendor or copy
upstream files. Each original is worth installing on its own; see [`CREDITS.md`](CREDITS.md).

---

## The loop

```
        ┌───────────────────────  context engineering  ───────────────────────┐
        │      fresh-context subagents  ·  STATE.md  ·  CONTEXT.md             │
        └─────────────────────────────────────────────────────────────────────┘

   FRAME ──▶ PLAN ──▶ BUILD ──▶ REVIEW ──▶ QA ──▶ SECURE ──▶ SHIP ──▶ LEARN
    spec     tasks     TDD       bugs      app    OWASP       PR       memory
                         ▲                                      │
                         └──────────  /ss-ralph (autonomous) ───┘
```

Each phase has a **gate** it must clear before the next begins. You can re-enter
anywhere: a bug report starts at QA, a refactor at Plan, "what should we build?" at Frame.

---

## Install

### Claude Code (recommended)

```
/plugin marketplace add Mrshahidali420/superstack
/plugin install superstack@superstack
```

### Manual (any agent, or to merge the CLAUDE.md)

```bash
# macOS / Linux
git clone https://github.com/Mrshahidali420/superstack ~/.superstack && ~/.superstack/install.sh
```

```powershell
# Windows
git clone https://github.com/Mrshahidali420/superstack "$HOME\.superstack"; & "$HOME\.superstack\install.ps1"
```

The installer targets Claude Code by default, copying the `/ss-*` skills and agents into
`~/.claude/`. Pass `--host codex|cursor|opencode|factory|kiro` (or `-Agent` on Windows), or
`--all`, to install for other agents. Then merge `CLAUDE.md` into your global or project config
to adopt the loop.

---

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

**Supporting skills:** `/ss-debug` `/ss-guard` `/ss-respond` `/ss-worktree` `/ss-pause` `/ss-resume` `/ss-retro` `/ss-docs` — run `/ss-help` for the full index.

---

## Karpathy's four laws (always on)

1. **Think before coding** — surface assumptions and alternatives; ask when unclear.
2. **Simplicity first** — minimum code, nothing speculative.
3. **Surgical changes** — touch only what the request requires.
4. **Goal-driven execution** — turn tasks into verifiable goals and loop until they pass.

Full operating system: [`CLAUDE.md`](CLAUDE.md) · design notes: [`docs/workflow.md`](docs/workflow.md).

---

## See it work

```
You:        Build me a URL-shortener API.
/ss-frame   Pushes back — "single-user or multi-tenant? custom slugs?"
            → writes specs/url-shortener.md; you approve.
/ss-plan    → 4 tasks, each with its own test, in PLAN.md
/ss-build   → TDD per task: failing test → minimal handler → green
/ss-review  → flags a missing slug-collision check; auto-fixes it
/ss-qa      → hits the running API, catches a 500 on duplicate slug,
              fixes it, adds a regression test
/ss-secure  → confirms input validation, no secrets in the diff
/ss-ship    → conventional commit, PR opened, CI green
```

## Hooks

SuperStack ships a **SessionStart** hook that activates the loop from the first message (and
after `/clear` or compaction), plus an **opt-in guard** (`PreToolUse`, off by default):

- `SUPERSTACK_GUARD=1` — block destructive shell commands (`rm -rf`, force-push, `DROP`…).
- `SUPERSTACK_FREEZE_DIR=<dir>` — block edits outside that directory.

Stack-specific hooks (format/lint/test on save) are intentionally **not** bundled — see
[`docs/hooks.md`](docs/hooks.md) for snippets to add to your own `settings.json`.

## What SuperStack is *not*

It does not re-implement gstack's Playwright browse server or its prompt-injection
classifier, GSD's full CLI, or Superpowers' eval harness. Where you need that depth,
run the original alongside — the `/ss-*` namespace is chosen so they coexist.

---

<div align="center">

MIT licensed. Fork it, make it yours. Built by [@Mrshahidali420](https://github.com/Mrshahidali420).

</div>
