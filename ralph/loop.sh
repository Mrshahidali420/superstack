#!/usr/bin/env bash
# SuperStack — Ralph autonomous loop.
# Spawns a fresh agent per iteration until every prd.json story passes,
# or until max iterations is reached. Memory lives in git + prd.json + progress.md.
#
# Usage:   ./loop.sh [max_iterations]
# Config (env):
#   PRD_FILE       path to the PRD json            (default: prd.json)
#   PROGRESS_FILE  append-only progress log         (default: progress.md)
#   PROMPT_FILE    per-iteration prompt template    (default: <script dir>/prompt.md)
#   AGENT_CMD      command that reads the prompt on stdin and runs one agent turn
#                  (default: claude -p --dangerously-skip-permissions)
set -euo pipefail

MAX_ITERATIONS="${1:-10}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="${PRD_FILE:-prd.json}"
PROGRESS_FILE="${PROGRESS_FILE:-progress.md}"
PROMPT_FILE="${PROMPT_FILE:-$SCRIPT_DIR/prompt.md}"
AGENT_CMD="${AGENT_CMD:-claude -p --dangerously-skip-permissions}"

command -v jq >/dev/null 2>&1 || { echo "error: jq is required (brew install jq / apt install jq)"; exit 1; }
[ -f "$PRD_FILE" ]    || { echo "error: $PRD_FILE not found — run /ss-ralph to generate one"; exit 1; }
[ -f "$PROMPT_FILE" ] || { echo "error: prompt template $PROMPT_FILE not found"; exit 1; }

remaining() { jq '[.stories[] | select(.passes == false)] | length' "$PRD_FILE"; }

iter=0
while [ "$iter" -lt "$MAX_ITERATIONS" ]; do
  left="$(remaining)"
  if [ "$left" -eq 0 ]; then
    echo "All stories pass. Completed in $iter iteration(s)."
    exit 0
  fi
  iter=$((iter + 1))
  echo "---- iteration $iter/$MAX_ITERATIONS · $left story(ies) remaining ----"

  # A fresh agent each time. Its only memory is the PRD, the progress log, and git.
  {
    cat "$PROMPT_FILE"
    printf '\n\n## Current %s\n```json\n' "$PRD_FILE"; cat "$PRD_FILE"; printf '\n```\n'
    if [ -f "$PROGRESS_FILE" ]; then printf '\n## %s\n' "$PROGRESS_FILE"; cat "$PROGRESS_FILE"; fi
  } | $AGENT_CMD || { echo "error: agent run failed on iteration $iter"; exit 1; }
done

echo "Reached max iterations ($MAX_ITERATIONS). $(remaining) story(ies) still open."
exit 1
