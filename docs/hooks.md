# Hooks

SuperStack ships two hooks (`hooks/hooks.json`), run through a cross-platform polyglot
launcher (`hooks/run-hook.cmd`) that locates `bash` on Windows or runs directly on Unix.

## SessionStart — always on

Matches `startup | clear | compact`. On a new session, after `/clear`, and after compaction,
it injects the `superstack` bootstrap (the loop, the laws, the command index) as session
context — so the loop is **active from the first message**, not merely available as a skill.
This is the one hook that's genuinely necessary; it mirrors how Superpowers activates.

If no `bash` is found on Windows, the launcher no-ops silently — the plugin still works, just
without context injection.

## Guard — opt-in, off by default

A `PreToolUse` hook (`Bash | Write | Edit | MultiEdit`) backing `/ss-guard`. It is **inert
unless you opt in** via environment variables — zero effect otherwise:

| Env var | Effect |
|---------|--------|
| `SUPERSTACK_GUARD=1` | **careful** — blocks destructive shell commands (`rm -rf`, `git push --force`, `git reset --hard`, `DROP`/`TRUNCATE`, `mkfs`, `dd if=`). |
| `SUPERSTACK_FREEZE_DIR=<dir>` | **freeze** — blocks edits to files outside `<dir>`. |

A blocked call exits non-zero and the reason is shown to the agent, which then asks you. The
matcher is heuristic (a safety net, not a sandbox). To remove the overhead entirely, delete the
`PreToolUse` block from `hooks/hooks.json`.

## What SuperStack deliberately does NOT ship

Format / lint / type-check on save, or a build check on Stop, are **stack-specific** — bundling
`pnpm eslint` (etc.) would break for everyone on a different stack. Add them to your own
`~/.claude/settings.json` instead. Examples:

```jsonc
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Write|Edit",
        "hooks": [{ "type": "command", "command": "<your formatter> \"$CLAUDE_PROJECT_DIR\"" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "<your build/test command>" }] }
    ]
  }
}
```

Keep them in the consuming project, where the toolchain is known — not in this portable framework.
