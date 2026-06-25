---
name: ss-ctx
description: Use to keep verbose tool output out of your context window - an always-on PostToolUse hook transparently replaces oversized Bash output with a head/tail summary and offloads the full text to .superstack/ctx/, and /ss-ctx list|show|search|prune retrieves it on demand. Front 2 of SuperStack's context all-rounder (the runtime-output sandbox).
---

# Ctx - keep verbose tool output out of context

Tool results are 49-73% of the tokens in agentic sessions, and verbose `Bash` output (test runs, build
logs, `git log`) is the worst offender. `ss-ctx` is an **always-on** `PostToolUse` hook: when a clean
Bash result is large, it saves the full output to `.superstack/ctx/<id>.txt` and lets you (the agent)
see only a head + tail + a marker. Nothing is lost - the marker tells you the id, and `/ss-ctx show <id>`
returns the full text. It is the runtime-output sandbox rebuilt natively, with zero runtime - just a
bash hook + files. Front 2 of the context all-rounder; the cockpit ([[ss-context]]) reports it as
`runtime sandbox: detected (native)`.

## Steps

1. It runs automatically. When you see a `[ss-ctx] truncated - ... retrieve: /ss-ctx show <id>` marker
   in a Bash result, the full output is on disk under that `<id>`.
2. `scripts/ss-ctx show <id>` (PowerShell: `scripts/ss-ctx.ps1 show <id>`) prints the full saved output.
3. `scripts/ss-ctx search <term>` greps across all saved outputs; `scripts/ss-ctx list` shows recent
   ones (`<bytes> <id>`, newest first); `scripts/ss-ctx prune [--keep N]` trims the store.

## Note

- Only **clean, successful, large** Bash stdout is shrunk - never errors, never interrupted runs, never
  `Read`/`Edit` output (you need those verbatim). The threshold is generous (8000 bytes) so normal
  output passes through untouched.
- Tune or disable via env: `SS_CTX_DISABLE=1` (off), `SS_CTX_THRESHOLD` (bytes), `SS_CTX_HEAD`/
  `SS_CTX_TAIL` (lines kept).
- If you need the whole result inline, retrieve it (`/ss-ctx show <id>`) or re-run the command more
  narrowly - don't fight the summary.
- The store holds raw command output (could include secrets in logs); it shares the `.superstack/`
  trust boundary. `ss-ctx prune` clears it.

## Lineage

Original to SuperStack - Front 2 of the context all-rounder (the runtime-output sandbox, the
context-mode capability rebuilt natively via the `updatedToolOutput` hook primitive). Complements
[[ss-context]] (the standing-context cockpit, Front 1). A later cycle adds an MCP server for sandboxed
execution + FTS5 search over the same store.
