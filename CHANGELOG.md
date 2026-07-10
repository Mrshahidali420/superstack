# Changelog

All notable changes to SuperStack are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **`/ss-panel`** — the unified ledger dashboard promised on the roadmap: report + replay +
  trace for one run in a single view, as a thin composer (the change is resolved once and the
  existing legs run verbatim, so all three views agree). `--save` writes a fenced markdown
  panel to `.superstack/replays/panel-<change>.md`. bash + PowerShell twins, byte-parity
  tested; 18th suite in `tests/run.sh`. (32 skills.)

## [0.9.0] - 2026-07-10

### Added
- **Context routing doctrine** (Front 4 — the context all-rounder is complete) — `/ss-init` now
  installs a compact, marker-delimited routing block into the project's `CLAUDE.md` (single source:
  `templates/context-routing.md`; re-run replaces the block in place; `--no-routing` opts out),
  steering the agent to `munch_*` over `Read`/`Grep` and `ctx_*` over raw Bash. The `/ss-context`
  cockpit gains a third stack row: `routing doctrine  detected/not detected`.

## [0.8.0] - 2026-07-10

### Added
- **ss-munch** (Front 3) — symbol-level code retrieval: a second, parser-vendored MCP server
  (`munch_outline`, `munch_symbol`, `munch_search`) that returns one code symbol or a compact file
  outline instead of a whole file, parsed from a real tree-sitter AST (vendored web-tree-sitter 0.20.8 +
  Core 7 grammars, zero-install). Read-only. The `/ss-context` cockpit now reports
  `code exploration: detected (native)`.

## [0.7.0] - 2026-06-26

### Added
- **`/ss-stats`:** read-only cross-run loop analytics — a per-run table (phases, gate-fails, skips,
  span) plus a rollup (gate-fail rate, skips, and an improving/worsening/flat trend over the window).
  `--since`/`--limit`; the cross-run companion to `/ss-report`, distinct from `/ss-evolve`. bash +
  PowerShell. (27 skills.)
- **`/ss-trace`:** read-only change provenance — joins a change's spec/plan docs, its ledger gate/skip
  events, and its git commits into one chronological lineage with an origin footer (gates, commits,
  files, head SHA). `[<change>] [base]`; degrades gracefully for merged/deleted branches. The view
  that links the ledger to git + specs, distinct from `/ss-replay` and `/ss-report`. bash +
  PowerShell. (28 skills.)
- **`/ss-context`:** read-only standing-context budget cockpit — estimates the always-loaded footprint
  (CLAUDE.md, STATE.md/CONTEXT.md, skill descriptions) vs a token budget (OK/WARN/OVER), detects the
  rest of the context stack, and flags bloat with fixes. Runs automatically at session start (advisory
  only when over budget). Front 1 of the context all-rounder. bash + PowerShell. (29 skills.)
- **`/ss-ctx`:** transparent tool-output shrinker - an always-on `PostToolUse` hook replaces oversized
  clean Bash output with a head/tail summary and offloads the full text to `.superstack/ctx/`;
  `/ss-ctx list|show|search|prune` retrieves it. Zero runtime (bash hook + files). Front 2 of the
  context all-rounder (the runtime-output sandbox). bash + PowerShell. (30 skills.)
- **`ss-ctx` MCP server:** a dependency-free Node server (`mcp/server.mjs`, registered via `.mcp.json`)
  exposing `ctx_execute` / `ctx_batch_execute` (run a command, keep verbose output out of context),
  `ctx_search` / `ctx_show` (over the shared `.superstack/ctx/` store), and `ctx_fetch_and_index` (fetch
  a URL, store the text, return a preview). The proactive half of the runtime-output sandbox (Front 2).

## [0.6.0] - 2026-06-25

### Added
- **`/ss-doctor`:** read-only project health check — verifies `jq`, `git`, `.superstack/config`,
  gitignore, and the ledger, printing a `[OK]`/`[WARN]`/`[FAIL]` checklist with an actionable fix per
  problem; exits 0 (healthy/warnings) or 1 (problems) for CI. The verify leg paired with `/ss-init`.
  bash + PowerShell. (25 skills.)
- **`/ss-drift`:** read-only plan-vs-build drift detection — compares a plan's declared `**Files:**`
  against what the branch actually changed (`base...HEAD` + working tree), reporting unplanned changes
  (scope creep) and planned-but-untouched files; exits 1 on drift for CI. bash + PowerShell. (26 skills.)

## [0.5.0] - 2026-06-24

### Added
- **`/ss-init`:** per-project bootstrap — writes a default `.superstack/config`, ensures `.superstack/`
  is gitignored, and records a genesis ledger entry. Idempotent; `--dry-run` previews, `--force` resets
  the config. bash + PowerShell. (24 skills.)
- **`/ss-replay`:** replays a loop run from the ledger as a chronological ASCII timeline
  (elapsed time, phase, event, `PASS`/`FAIL`/`SKIP`, `(retry)` tags) with a footer of story
  stats; `--save` writes a shareable fenced Markdown file to `.superstack/replays/`. The "story"
  leg of the proof trio (audit=gate, report=stats, replay=story). bash + PowerShell. (24 skills.)

## [0.4.0] - 2026-06-24

### Added
- `ss-evolve --since <window>` (`Nd` / `Nh` / `YYYY-MM-DD`) restricts detection to a recent
  slice of the ledger; composes with every other flag.
- `ss-evolve --explore` scaffolds a draft new-skill proposal into `.superstack/proposals/<name>/`
  (Tier 2) — never committed; the `/ss-evolve` skill authors the body and a human promotes it.
  Dedups independently of `--apply` via `.superstack/explore-state`.

### Changed
- Repositioned the README, `CLAUDE.md`, and the plugin/marketplace description around SuperStack
  as its own framework — added why-it's-better, a capability comparison, use cases, and benefits;
  reframed credits as inspiration rather than a "distillation."

## [0.3.0] - 2026-06-24

### Added
- **`/ss-report`:** a shareable Markdown run summary (phases, timing, change size) generated from
  the loop ledger + git; bash + PowerShell. (21 skills total.)
- **`/ss-evolve`:** detects recurring ledger patterns (skipped phases, failing gates) and
  auto-applies low-risk `CONTEXT.md`/config fixes (revertable `chore(evolve):` commits), routing
  new-skill drafts to `.superstack/proposals/` for review; bash + PowerShell. (22 skills total.)

## [0.2.0] - 2026-06-23

### Added
- **Loop Ledger:** `.superstack/ledger.jsonl` + `ledger` helper, `ss-audit` proof-of-process gate
  with PR attestation, and an opt-in enforcement hook (`SUPERSTACK_AUDIT=1`).
- Eight supporting skills: `/ss-debug`, `/ss-guard`, `/ss-respond`, `/ss-worktree`,
  `/ss-pause`, `/ss-resume`, `/ss-retro`, `/ss-docs`, plus `/ss-audit` (20 skills total).
- Cross-agent install: `install.sh --host <agent>|--all` and `install.ps1 -Agent|-All`
  for Codex, Cursor, OpenCode, Factory, and Kiro (Claude Code remains the default).
- Ralph loop: `--dry-run` preview, per-iteration run logs (`runs/`), and archive-on-completion (`archive/`).
- Hooks: a **SessionStart** bootstrap hook (cross-platform polyglot launcher) that activates the
  loop, and an **opt-in guard** `PreToolUse` hook (`SUPERSTACK_GUARD` / `SUPERSTACK_FREEZE_DIR`,
  off by default). Linter now validates `hooks/hooks.json`; self-test covers hook behavior.
- `CHANGELOG.md` (this file); `/ss-ship` now bumps it as part of shipping.
- CI runs the linter on `v*` and `superstack--v*` tags, not just branch pushes.
- `SPDX-License-Identifier: MIT` headers on the shell and PowerShell scripts.

### Changed
- Linter upgraded from a structural check to a quality check: trigger-style descriptions,
  a single H1, resolvable `[[wikilinks]]`, and loop completeness.

## [0.1.0] - 2026-06-23

### Added
- The SuperStack loop: Frame → Plan → Build → Review → QA → Secure → Ship → Learn.
- 11 skills including the `superstack` bootstrap (auto-loads on install) and `/ss-help`.
- 4 subagents: `ss-planner`, `ss-code-reviewer`, `ss-security-reviewer`, `ss-qa-runner`.
- Ralph autonomous loop (`ralph/loop.sh` + `loop.ps1`), example PRD, and prompt template.
- Karpathy's four laws in `CLAUDE.md`; context-engineering `STATE.md` / `CONTEXT.md` templates.
- Cross-platform installers and Claude Code plugin + marketplace manifests.
- Skill-frontmatter linter (`scripts/lint-skills.sh`), self-test, and CI.

[Unreleased]: https://github.com/Mrshahidali420/superstack/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/Mrshahidali420/superstack/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/Mrshahidali420/superstack/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/Mrshahidali420/superstack/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/Mrshahidali420/superstack/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/Mrshahidali420/superstack/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/Mrshahidali420/superstack/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Mrshahidali420/superstack/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Mrshahidali420/superstack/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Mrshahidali420/superstack/releases/tag/v0.1.0
