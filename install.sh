#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SuperStack installer (macOS / Linux / Git Bash).
# Copies the /ss-* skills and agents into ~/.claude and points you at CLAUDE.md.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"

echo "SuperStack installer"
echo "  source: $SRC"
echo "  target: $CLAUDE_HOME"
mkdir -p "$CLAUDE_HOME/skills" "$CLAUDE_HOME/agents"

for d in "$SRC"/skills/*/; do
  [ -f "${d}SKILL.md" ] || continue
  name="ss-$(basename "$d")"
  rm -rf "$CLAUDE_HOME/skills/$name"
  cp -R "$d" "$CLAUDE_HOME/skills/$name"
  echo "  + skill  $name"
done

for f in "$SRC"/agents/*.md; do
  cp "$f" "$CLAUDE_HOME/agents/"
  echo "  + agent  $(basename "$f" .md)"
done

chmod +x "$SRC"/ralph/loop.sh 2>/dev/null || true

cat <<EOF

Done. The /ss-* skills and agents are installed.
Ralph loop: $SRC/ralph/loop.sh   (Windows: ralph/loop.ps1)

Adopt the operating system by merging CLAUDE.md into your config:
  global  -> $CLAUDE_HOME/CLAUDE.md
  project -> ./CLAUDE.md   (in any repo you work in)
Open $SRC/CLAUDE.md and append the sections you want.
EOF
