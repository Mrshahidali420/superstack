# Philosophy

SuperStack is a merge, not an invention. Four frameworks each got one thing very right;
SuperStack takes that one thing from each and drops the rest, so you run a single coherent
loop instead of four overlapping ones.

## What each contributed

- **Superpowers** → *discipline that triggers automatically.* The agent doesn't wait to be
  told to plan or test; the process is the default, and skills are mandatory, not optional.
- **GSD** → *context engineering.* Treat the context window as a scarce resource. Push heavy
  work into fresh subagents, persist durable state to files, and beat the quality decay that
  ruins long sessions.
- **gstack** → *the back half of shipping.* Review, QA against a running app, security audit,
  and release are first-class phases with their own gates — not an afterthought you bolt on.
- **Ralph** → *autonomy with a stop condition.* A fresh agent per iteration, memory in git
  and files, one small story at a time, until a PRD is provably complete.

## And Karpathy's four laws sit on top

Four guardrails keep every phase from drifting into the common LLM failure modes — think
before coding, simplicity first, surgical changes, goal-driven execution. They are stated
canonically in **[`CLAUDE.md`](../CLAUDE.md)**; the point here is that they apply to *every*
phase, not just Build.

## The core bet

The leverage in AI-assisted development is **structured process**, not custom tooling. A
clear loop with honest gates lets one person direct an agent — or ten agents — the way a
lead directs a team: check the decisions that matter, let the rest run.

## When to use SuperStack vs. the originals

- Use **SuperStack** when you want one opinionated loop and minimal collisions.
- Reach for an **original** when you need its native depth — gstack's browser server and
  injection defense, GSD's full CLI and milestone tooling, Superpowers' eval harness. The
  `/ss-*` namespace is chosen so SuperStack and an original can run side by side.

SuperStack is small on purpose. If a phase ever feels like ceremony for a trivial change,
skip it — Law 2 applies to the process itself.
