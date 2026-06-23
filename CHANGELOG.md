# Changelog

All notable changes to SuperStack are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Eight supporting skills: `/ss-debug`, `/ss-guard`, `/ss-respond`, `/ss-worktree`,
  `/ss-pause`, `/ss-resume`, `/ss-retro`, `/ss-docs` (19 skills total).
- Cross-agent install: `install.sh --host <agent>|--all` and `install.ps1 -Agent|-All`
  for Codex, Cursor, OpenCode, Factory, and Kiro (Claude Code remains the default).
- Ralph loop: `--dry-run` preview, per-iteration run logs (`runs/`), and archive-on-completion (`archive/`).
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

[Unreleased]: https://github.com/Mrshahidali420/superstack/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Mrshahidali420/superstack/releases/tag/v0.1.0
