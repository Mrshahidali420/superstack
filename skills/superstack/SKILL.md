---
name: superstack
description: Use at the start of any coding task to activate the SuperStack workflow. Establishes the one loop (Frame -> Plan -> Build -> Review -> QA -> Secure -> Ship -> Learn), Karpathy's four laws, and the /ss-* commands. This is the bootstrap that loads the methodology when SuperStack is installed as a plugin.
---

# SuperStack is active

Run **one loop** on every non-trivial task; scale it down for small ones.

```
FRAME -> PLAN -> BUILD -> REVIEW -> QA -> SECURE -> SHIP -> LEARN
```

Enter at the phase the work actually starts, and run the matching command. `/ss-help` lists
them all: `/ss-frame /ss-plan /ss-build /ss-review /ss-qa /ss-secure /ss-ship /ss-ralph /ss-learn`.

## Always-on laws (Karpathy)

1. **Think before coding** — surface assumptions and alternatives; ask when unclear.
2. **Simplicity first** — minimum code, nothing speculative.
3. **Surgical changes** — touch only what the request requires.
4. **Goal-driven execution** — turn tasks into verifiable goals and loop until they pass.

## Fast path

Scale the loop to the work: a typo is `Ship`; a small change is `Plan -> Build -> Ship`; a
bug is `QA -> Build -> Review -> Ship`. The full eight phases are for features, not one-liners.

The full operating system — gates, context engineering, and autonomy — is the canonical
reference in **CLAUDE.md** (and **docs/workflow.md**). Run **`/ss-help`** for the command index.
