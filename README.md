<div align="center">

# SuperStack

**An operating system for coding agents — one disciplined, *verifiable* loop.**

Frame → Plan → Build → Review → QA → Secure → Ship → Learn

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-7c3aed.svg)](https://github.com/Mrshahidali420/superstack) [![status v0.6.0](https://img.shields.io/badge/release-v0.6.0-brightgreen.svg)](https://github.com/Mrshahidali420/superstack/releases) ![skills 29](https://img.shields.io/badge/skills-29-7c3aed.svg)

Built for Claude Code; portable to any skill-aware agent.

</div>

---

## What is SuperStack?

Coding agents are powerful but undisciplined. Left alone they skip review, invent a plan halfway through, lose the thread across sessions, and announce **"done"** with nothing to back it up.

SuperStack is an opinionated framework that turns your agent into a disciplined engineering team. It runs **one mandatory, gated loop** on every non-trivial task, **records what it actually did**, and can **prove the loop ran** before anything ships.

It is its own framework — its own loop, its own gates, its own proof-of-process ledger and self-evolution, its own code. It's informed by years of great open-source thinking on agent workflows (see [Credits](#credits--inspiration)), but everything in the `/ss-*` toolkit is SuperStack's own design.

---

## Why SuperStack

- **One gated loop, not a grab-bag of commands.** Eight phases, each with a **gate** it must clear before the next begins. The skills are mandatory workflows, not polite suggestions — so quality isn't left to whether the agent "felt like" reviewing.
- **Proof of process.** Most agent setups can't tell you whether the agent *actually* followed the process. SuperStack records every gate to a **Loop Ledger**, `/ss-audit` verifies the mandatory phases ran, and `/ss-ship` attaches a `Framed ✓ Planned ✓ Built ✓ Reviewed ✓ Secured ✓` attestation to the PR. Trust, but verify.
- **It improves itself.** `/ss-evolve` mines *your own* usage — recurring skips, gates that keep failing — and auto-applies low-risk fixes (revertable commits) or drafts new skills for your review. The framework gets sharper the more you use it.
- **Always-on guardrails.** Karpathy's four anti-mistake laws run on *every* task: think before coding, simplicity first, surgical changes, goal-driven execution.
- **Context-rot resistant.** Fresh-context subagents plus durable `STATE.md` / `CONTEXT.md` keep output quality high on long, multi-session work — a cold session can pick up exactly where you left off.
- **Autonomy when you want it.** `/ss-ralph` runs the entire loop unattended against a PRD until it's done.
- **Plays nice with everything.** Every command is namespaced `/ss-*` and works across Claude Code, Codex, Cursor, OpenCode, Factory, and Kiro — it coexists with whatever you already run, no collisions.

---

## How it compares

The real alternatives to SuperStack are *ad-hoc prompting*, a *single one-shot workflow command*, or *stacking several overlapping frameworks* and hoping they don't fight. Here's the difference:

| Capability | Raw prompting | A single workflow command | **SuperStack** |
|---|:---:|:---:|:---:|
| Enforced multi-phase process | ✗ | partial | ✅ one gated loop |
| **Verifiable proof the process ran** | ✗ | ✗ | ✅ ledger + `/ss-audit` |
| **Self-improves from your usage** | ✗ | ✗ | ✅ `/ss-evolve` |
| Durable cross-session memory | ✗ | varies | ✅ `STATE.md` / `CONTEXT.md` |
| Unattended autonomous runs | ✗ | varies | ✅ `/ss-ralph` |
| Always-on mistake guardrails | ✗ | ✗ | ✅ Karpathy's 4 laws |
| Cross-agent & collision-free | n/a | varies | ✅ `/ss-*`, 6 agents |
| Shareable "how it was built" report | ✗ | ✗ | ✅ `/ss-report` |

SuperStack's bet: a *coherent, verifiable* process beats a pile of clever-but-unaccountable commands.

---

## Use cases

- **Ship a feature you can trust** — the full loop: spec → TDD → review → QA → security, with the proof attached to the PR.
- **Fix a bug the right way** — start at QA: reproduce → fix → add a regression test, so it can't silently come back.
- **Refactor without fear** — Plan → Build with the test suite green before *and* after.
- **Long or multi-session work** — context engineering + the ledger keep a brand-new session resumable and on-track.
- **Unattended grind** — point `/ss-ralph` at a PRD and let it work through the backlog with real feedback loops (typecheck, tests, CI).
- **Process you can audit** — every change carries a verifiable record of *how* it was built, not just *what* changed.

---

## Benefits

- **Fewer "looked done, actually broke" moments** — gates and evidence replace optimistic claims.
- **Less context rot** on big tasks — the heavy lifting happens in fresh subagent contexts.
- **A process that tightens itself** over time, from your real usage.
- **No lock-in** — MIT licensed, cross-agent, namespaced. Adopt it incrementally; fork it freely.

---

## The loop

```
        ┌─────────────────────  context engineering  ─────────────────────┐
        │     fresh-context subagents  ·  STATE.md  ·  CONTEXT.md          │
        └─────────────────────────────────────────────────────────────────┘

   FRAME ──▶ PLAN ──▶ BUILD ──▶ REVIEW ──▶ QA ──▶ SECURE ──▶ SHIP ──▶ LEARN
    spec     tasks     TDD       bugs      app    OWASP       PR       memory
                         ▲                                      │
                         └──────────  /ss-ralph (autonomous) ───┘

   every phase records its gate to the Loop Ledger → /ss-audit verifies it before /ss-ship
```

Each phase has a **gate** it must clear before the next begins. Re-enter anywhere: a bug report starts at **QA**, a refactor at **Plan**, "what should we build?" at **Frame**. Trivial one-liners skip the ceremony — the loop scales to the work.

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

Installs the `/ss-*` skills and agents into `~/.claude/` by default. Pass `--host codex|cursor|opencode|factory|kiro` (or `-Agent` on Windows), or `--all`, to target other agents. Then merge `CLAUDE.md` into your global or project config to adopt the loop.

Then run `/ss-init` once in your project to set up `.superstack/`, and `/ss-frame` to start the loop.

---

## Commands

**The loop**

| Command | Phase | Does |
|---------|-------|------|
| `/ss-frame` | Frame | Interrogate intent, push back, write a spec you sign off on |
| `/ss-plan` | Plan | Break the spec into small, individually verifiable tasks |
| `/ss-build` | Build | TDD execution, one task per fresh subagent |
| `/ss-review` | Review | Staff-eng review, severity-graded, auto-fix the trivial |
| `/ss-qa` | QA | Run the app, find and fix bugs, add regression tests |
| `/ss-secure` | Secure | OWASP + STRIDE pass + secret scan |
| `/ss-ship` | Ship | Coverage gate, conventional commit, PR, attestation, optional deploy |
| `/ss-learn` | Learn | Persist learnings so the next session starts smart |

**Proof, autonomy & insight**

| Command | Does |
|---------|------|
| `/ss-audit` | Verify the mandatory phases actually ran (reads the Loop Ledger) |
| `/ss-report` | Generate a shareable Markdown summary of how a change was built |
| `/ss-replay` | Replay a run as a chronological timeline (the story leg); `--save` for a shareable Markdown file |
| `/ss-evolve` | Learn from your ledger; auto-apply low-risk fixes, draft new skills for review. Now supports `--since <window>` (time-windowed detection) and `--explore` (deterministic draft-skill proposals into `.superstack/proposals/`, never auto-committed). |
| `/ss-ralph` | Run the loop unattended until a PRD is fully done |

**Supporting skills:** `/ss-debug` `/ss-guard` `/ss-respond` `/ss-worktree` `/ss-pause` `/ss-resume` `/ss-retro` `/ss-docs` `/ss-init` `/ss-doctor` `/ss-drift` `/ss-stats` `/ss-trace` `/ss-context` — run `/ss-help` for the full index (**29 skills, 4 review agents, 2 hooks**).

---

## Under the hood

- **Loop Ledger + `/ss-audit`** — every phase records its gate to `.superstack/ledger.jsonl`; the audit checks the mandatory phases (default `review,secure`) each passed or carry an explicit skip-with-reason. An **opt-in** `PreToolUse` hook (`SUPERSTACK_AUDIT=1`) can block a push when the loop is incomplete. See [`docs/ledger.md`](docs/ledger.md).
- **`/ss-report`** — turns the ledger + git into a copy-pasteable run summary (phases, timing, change size) for a PR or status update. Read-only.
- **`/ss-evolve`** — detects recurring patterns in the ledger and auto-applies low-risk `CONTEXT.md` insights as revertable `chore(evolve):` commits, routing brand-new skill drafts to `.superstack/proposals/` for your review (never auto-committed).
- **Hooks** — a **SessionStart** hook activates the loop from the first message (and after `/clear` / compaction); an **opt-in guard** (`SUPERSTACK_GUARD=1`, `SUPERSTACK_FREEZE_DIR=<dir>`) blocks destructive commands / edits outside a directory. Stack-specific format/lint/test hooks are intentionally not bundled — see [`docs/hooks.md`](docs/hooks.md).
- **Autonomy** — `/ss-ralph` converts a spec to a `prd.json` and runs a fresh agent per iteration, with `--dry-run`, per-iteration logs, and archive-on-completion.

Everything ships **bash + PowerShell** twins and is covered by a self-test (`tests/run.sh`) and CI.

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
/ss-ship    → conventional commit, PR opened with a process attestation, CI green
/ss-report  → "built in 22m · 4 phases · 12 tests added · 2 bugs caught at review"
```

---

## Focused, not bloated

SuperStack is deliberately lean. It does not bundle a headless-browser server, a full standalone CLI, or an eval harness. Where you need that depth, the `/ss-*` namespace is chosen so you can run a specialized tool **alongside** SuperStack without collision — use the right tool for the job, keep the loop as your spine.

---

## Credits & inspiration

SuperStack is original work, but it stands on the shoulders of excellent MIT-licensed projects that shaped how the community thinks about agent workflows — and on Andrej Karpathy's notes on LLM coding pitfalls. See [`CREDITS.md`](CREDITS.md) for the full acknowledgment. If any of them fit your needs better, use them — and if you want a verifiable, self-improving loop as your backbone, that's what SuperStack is here for.

---

<div align="center">

[Changelog](CHANGELOG.md) · [Releases](https://github.com/Mrshahidali420/superstack/releases)

MIT licensed. Fork it, make it yours. Built by [@Mrshahidali420](https://github.com/Mrshahidali420).

</div>
