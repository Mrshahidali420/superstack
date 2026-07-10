# Front 4 — context all-rounder integration — Design

Status: APPROVED 2026-07-10 (install mode: /ss-init default-on with `--no-routing` opt-out)

## Problem

Fronts 1–3 shipped the tools, but nothing routes the agent to them. The cockpit
(`/ss-context`) audits standing context; `ss-ctx` sandboxes runtime output; `ss-munch`
reads code by symbol. Yet a fresh session still defaults to `Read`/`Grep`/`Bash` —
the capabilities sit connected but unused unless the agent happens to read a skill
description at the right moment. The stack needs a **standing routing doctrine** (so
the right tool is the default, not the exception) and the cockpit should report
whether that doctrine is installed — closing the loop: measure (F1), sandbox (F2),
retrieve (F3), **route (F4)**.

## Approach — a marker-delimited doctrine block, installed by /ss-init, detected by the cockpit

Three pieces, smallest-possible footprint:

### 1. The doctrine (canonical text, ~120 tokens standing cost)

A compact block, marker-delimited so it can be idempotently replaced/removed and
mechanically detected:

```markdown
<!-- superstack:context-routing -->
## Context routing (SuperStack)

Keep raw bulk out of the context window; retrieve on demand:

- **Explore code by symbol, not by file.** Prefer `munch_outline` (file shape) and
  `munch_symbol` (one function/class) over `Read`; `munch_search` over `Grep` for
  symbol names. `Read` stays correct for files you are about to Edit.
- **Run verbose commands in the sandbox.** Prefer `ctx_execute` / `ctx_batch_execute`
  over Bash when output may exceed ~20 lines (builds, suites, logs); retrieve detail
  later via `ctx_search` / `ctx_show`. Bash stays right for git and short commands.
- **Fetch pages via `ctx_fetch_and_index` + `ctx_search`** — never raw HTML into context.

If a tool is not connected, fall back to the defaults — never block.
<!-- /superstack:context-routing -->
```

Canonical copy lives in the repo `CLAUDE.md` (Context Engineering section) — dogfooded.
Advisory, not enforced: no PreToolUse blocking (deferred; see Out of scope).

### 2. `/ss-init` installs it (bash + ps1 twins)

- **Single source:** the block lives once in `templates/context-routing.md`; both init
  twins read it (no drifting copies in two scripts + CLAUDE.md). The repo's own
  CLAUDE.md gets the block by running `/ss-init` on the repo (dogfood), not by hand.
- On run: append the block to the project's `CLAUDE.md` (create the file if absent),
  or **replace between markers** if already present (idempotent re-run; upgrades the
  doctrine text after a plugin update).
- **Build amendment (gating):** the draft gated the install on `ss-ctx`/`ss-munch`
  appearing in the *project's* `.mcp.json` — but in real installs the servers ship via
  the *plugin's* manifest and never appear there, which would make default-on a
  permanent no-op. The gate is `--no-routing` only; the doctrine's final
  "fall back if not connected" line covers absent servers.
- `--no-routing` opts out; removal = delete between markers (documented, not a flag).
- No writes outside the project dir; never touches `~/.claude/CLAUDE.md`.

### 3. Cockpit row 3 (bash + ps1 twins, byte-parity)

```
  routing doctrine   detected      CLAUDE.md (superstack:context-routing)
  routing doctrine   not detected  run /ss-init to install the routing block
```

Detection: literal case-sensitive match of `<!-- superstack:context-routing -->` in
`./CLAUDE.md` (same grep/Select-String -CaseSensitive discipline as rows 1–2).

## Components / files

- Create: `templates/context-routing.md` (the single-source doctrine block)
- Modify: `CLAUDE.md` (block installed by running /ss-init on the repo — dogfood)
- Modify: `skills/init/SKILL.md`, `scripts/ss-init`, `scripts/ss-init.ps1` (install step)
- Modify: `scripts/ss-context`, `scripts/ss-context.ps1` (row 3)
- Modify: `tests/init.test.sh` (append / idempotent-replace / no-CLAUDE.md / opt-out)
- Modify: `tests/context.test.sh` (row-3 detected/not-detected fixtures + parity loop)
- Modify: `README.md` (all-rounder section: four fronts complete), `CHANGELOG.md`

## Testing

- init: block appended when servers registered; re-run replaces between markers
  byte-stably; `--no-routing` leaves CLAUDE.md untouched; CLAUDE.md created if absent.
- context: row-3 detection both ways; fixtures added to the bash/ps1 parity loop;
  mixed-case marker must NOT match (parity gotcha regression).
- Full suite stays green ([17/17] + new cases).

## Out of scope (deferred)

- **Enforcement hooks** (PreToolUse blocking of Read/Bash, context-mode style) — start
  advisory; revisit if routing adherence proves weak.
- Global `~/.claude/CLAUDE.md` injection — never automatic.
- Doctrine localization per-project (custom thresholds) — YAGNI until asked.

## Decided defaults (open to review)

- Marker pair: `<!-- superstack:context-routing -->` / `<!-- /superstack:context-routing -->`.
- Cockpit row label: `routing doctrine` (18-col field as rows 1–2).
- Doctrine budget: ≤ ~120 tokens; the cockpit's own byte-count already prices it.
- `/ss-init` installs by default with `--no-routing` opt-out (fork flagged at sign-off).
