# Credits & Attribution

SuperStack is an **original distillation**. It re-implements the *ideas* of the
projects below in its own words and structure — it does **not** copy or
redistribute their files. Each of these is excellent and worth installing on its
own; SuperStack exists to merge their best ideas into one de-conflicted loop.

If you want any original in full, install it directly from its source.

| Project | Author | License | What SuperStack borrows | Source |
|---|---|---|---|---|
| **Superpowers** | Jesse Vincent (obra) / Prime Radiant | MIT | Auto-triggering skills, spec-first brainstorming, true RED-GREEN-REFACTOR TDD, subagent-driven development, "skills are mandatory, not suggestions" | https://github.com/obra/superpowers |
| **GSD Core** | TÂCHES / Open GSD | MIT | The phase loop, context-rot mitigation, fresh-context subagents, durable `STATE.md` / `CONTEXT.md` artifacts, parallel execution waves | https://github.com/open-gsd/gsd-core |
| **gstack** | Garry Tan | MIT | Role-based review gates, real-browser QA-and-fix, `/cso` security audits (OWASP + STRIDE), ship/deploy automation, learnings that compound | https://github.com/garrytan/gstack |
| **Ralph** | Pattern by Geoffrey Huntley | MIT | The autonomous loop: fresh context per iteration, memory in git + `prd.json` + progress log, one small story at a time, stop-when-done | https://github.com/snarktank/ralph · https://github.com/iannuttall/ralph · https://ghuntley.com/ralph/ |
| **Karpathy Guidelines** | Andrej Karpathy (observations); skills packaged by forrestchang | MIT | The four anti-mistake laws: think before coding, simplicity first, surgical changes, goal-driven execution | https://github.com/forrestchang/andrej-karpathy-skills |

## A note on honesty

SuperStack does not claim to replace these projects, and it does not vendor their
code. Several of them ship native tooling SuperStack deliberately does **not**
re-implement (e.g. gstack's Playwright browse server and prompt-injection
classifier). Where you need that depth, run the original alongside SuperStack —
the `/ss-*` command namespace is chosen specifically so they coexist.

All upstream projects are MIT licensed; so is SuperStack (see `LICENSE`).
