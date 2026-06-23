#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SuperStack installer. Installs the /ss-* skills (and agents, for Claude Code) into one or
# more coding-agent homes.
#
# Usage:
#   ./install.sh                # Claude Code (default)
#   ./install.sh --host codex   # one agent: claude|codex|cursor|opencode|factory|kiro
#   ./install.sh --all          # every detected agent (installs where the agent's home exists)
#
# Override the install root with SUPERSTACK_INSTALL_HOME (used for testing).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="${SUPERSTACK_INSTALL_HOME:-$HOME}"
HOSTS="claude codex cursor opencode factory kiro"

# Each agent's skills dir, relative to the install root (per the agent's documented convention).
skills_rel() {
  case "$1" in
    claude)   echo ".claude/skills" ;;
    codex)    echo ".codex/skills" ;;
    cursor)   echo ".cursor/skills" ;;
    opencode) echo ".config/opencode/skills" ;;
    factory)  echo ".factory/skills" ;;
    kiro)     echo ".kiro/skills" ;;
    *)        return 1 ;;
  esac
}

skill_count() { local n=0 d; for d in "$SRC"/skills/*/; do [ -f "${d}SKILL.md" ] && n=$((n + 1)); done; echo "$n"; }

install_host() {
  local host="$1" rel dir name d
  rel="$(skills_rel "$host")" || { echo "  unknown host: $host (skipped)"; return 0; }
  dir="$BASE/$rel"
  mkdir -p "$dir"
  for d in "$SRC"/skills/*/; do
    [ -f "${d}SKILL.md" ] || continue
    name="ss-$(basename "$d")"
    rm -rf "$dir/$name"
    cp -R "$d" "$dir/$name"
  done
  echo "  $host: $(skill_count) skills -> $dir"
  if [ "$host" = "claude" ]; then
    mkdir -p "$BASE/.claude/agents"
    cp "$SRC"/agents/*.md "$BASE/.claude/agents/"
    echo "  claude: agents -> $BASE/.claude/agents"
  fi
}

mode="claude"
case "${1:-}" in
  "")      mode="claude" ;;
  --all)   mode="all" ;;
  --host)  mode="${2:-}"; [ -n "$mode" ] || { echo "usage: install.sh --host <name>"; exit 1; } ;;
  *)       echo "usage: install.sh [--host <name>|--all]"; exit 1 ;;
esac

echo "SuperStack installer (source: $SRC, base: $BASE)"
if [ "$mode" = "all" ]; then
  for h in $HOSTS; do
    marker="$BASE/$(dirname "$(skills_rel "$h")")"
    if [ "$h" = "claude" ] || [ -d "$marker" ]; then
      install_host "$h"
    fi
  done
else
  install_host "$mode"
fi

chmod +x "$SRC"/ralph/loop.sh 2>/dev/null || true
cat <<EOF

Done. To adopt the operating system, merge CLAUDE.md into your config:
  global  -> $BASE/.claude/CLAUDE.md      project -> ./CLAUDE.md
Non-Claude skill paths follow each agent's documented convention — verify if your agent differs.
EOF
