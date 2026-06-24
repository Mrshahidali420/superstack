# Changelog

All notable changes to SuperStack are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **`/ss-doctor`:** read-only project health check — verifies `jq`, `git`, `.superstack/config`,
  gitignore, and the ledger, printing a `[OK]`/`[WARN]`/`[FAIL]` checklist with an actionable fix per
  problem; exits 0 (healthy/warnings) or 1 (problems) for CI. The verify leg paired with `/ss-init`.
  bash + PowerShell. (25 skills.)

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

[Unreleased]: https://github.com/Mrshahidali420/superstack/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/Mrshahidali420/superstack/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Mrshahidali420/superstack/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Mrshahidali420/superstack/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Mrshahidali420/superstack/releases/tag/v0.1.0
