#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SuperStack — Ralph autonomous loop.
# Spawns a fresh agent per iteration until every prd.json story passes, or max iterations.
# Each iteration's output is logged under runs/; a completed run is archived under archive/.
# Memory lives in git + prd.json + progress.md.
#
# Usage:   ./loop.sh [--dry-run] [max_iterations]
# Config (env): PRD_FILE, PROGRESS_FILE, PROMPT_FILE, AGENT_CMD, RUN_DIR, ARCHIVE_DIR
set -euo pipefail

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then DRY_RUN=1; shift; fi
MAX_ITERATIONS="${1:-10}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="${PRD_FILE:-prd.json}"
PROGRESS_FILE="${PROGRESS_FILE:-progress.md}"
PROMPT_FILE="${PROMPT_FILE:-$SCRIPT_DIR/prompt.md}"
AGENT_CMD="${AGENT_CMD:-claude -p --dangerously-skip-permissions}"
RUN_DIR="${RUN_DIR:-runs}"
ARCHIVE_DIR="${ARCHIVE_DIR:-archive}"

command -v jq >/dev/null 2>&1 || { echo "error: jq is required (brew install jq / apt install jq)"; exit 1; }
[ -f "$PRD_FILE" ]    || { echo "error: $PRD_FILE not found — run /ss-ralph to generate one"; exit 1; }
[ -f "$PROMPT_FILE" ] || { echo "error: prompt template $PROMPT_FILE not found"; exit 1; }

remaining()  { jq '[.stories[] | select(.passes == false)] | length' "$PRD_FILE"; }
next_story() { jq -r '[.stories[] | select(.passes==false)] | sort_by(.priority) | .[0] // empty | "#\(.id) \(.title)"' "$PRD_FILE"; }

archive_run() {
  local branch ts dest
  branch="$(jq -r '.branchName // "feature"' "$PRD_FILE")"
  branch="$(printf '%s' "$branch" | tr -c 'A-Za-z0-9._-' '-')"
  ts="$(date +%Y%m%d-%H%M%S)"
  dest="$ARCHIVE_DIR/${branch}-${ts}"
  mkdir -p "$dest"
  cp "$PRD_FILE" "$dest/" 2>/dev/null || true
  [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$dest/" 2>/dev/null || true
  echo "Archived completed run to $dest"
}

if [ "$DRY_RUN" = "1" ]; then
  echo "Dry run — $(remaining) story(ies) open."
  ns="$(next_story)"
  if [ -n "$ns" ]; then echo "next up: $ns"; else echo "nothing to do (all pass)"; fi
  exit 0
fi

iter=0
while [ "$iter" -lt "$MAX_ITERATIONS" ]; do
  left="$(remaining)"
  if [ "$left" -eq 0 ]; then
    echo "All stories pass. Completed in $iter iteration(s)."
    if [ "$iter" -gt 0 ]; then archive_run; fi
    exit 0
  fi
  iter=$((iter + 1))
  echo "---- iteration $iter/$MAX_ITERATIONS · $left remaining · next: $(next_story) ----"
  mkdir -p "$RUN_DIR"
  ts="$(date +%Y%m%d-%H%M%S)"
  {
    cat "$PROMPT_FILE"
    printf '\n\n## Current %s\n```json\n' "$PRD_FILE"; cat "$PRD_FILE"; printf '\n```\n'
    if [ -f "$PROGRESS_FILE" ]; then printf '\n## %s\n' "$PROGRESS_FILE"; cat "$PROGRESS_FILE"; fi
  } | $AGENT_CMD 2>&1 | tee "$RUN_DIR/iter-${iter}-${ts}.log" || { echo "error: agent run failed on iteration $iter (see $RUN_DIR)"; exit 1; }
done

echo "Reached max iterations ($MAX_ITERATIONS). $(remaining) story(ies) still open."
exit 1
