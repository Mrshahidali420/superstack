#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Lint + quality-check SuperStack skills, agents, and JSON manifests.
# Checks: frontmatter (name ss-*/superstack + description), trigger-style descriptions,
# a single H1, resolvable [[wikilinks]], loop completeness, and valid JSON.
# Exits non-zero on any problem.
#
# Usage: scripts/lint-skills.sh [root]   (default: the repo this script lives in)
set -uo pipefail
shopt -s nullglob

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
errors=0
err() { echo "FAIL: $*"; errors=$((errors + 1)); }

frontmatter() { awk 'NR==1 && $0!="---"{exit} NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$1"; }
field() { printf '%s\n' "$1" | grep -m1 "^$2:" | sed "s/^$2:[[:space:]]*//" | tr -d '\r'; }
# Count H1 (`# `) lines that are NOT inside ``` fenced blocks.
count_h1() { awk '/^```/{f=!f;next} !f && /^# /{c++} END{print c+0}' "$1"; }

skills=("$ROOT"/skills/*/SKILL.md)
[ ${#skills[@]} -gt 0 ] || err "no skills found under $ROOT/skills"

# Pass 1: collect skill names (for wikilink resolution).
declare -A NAMES=()
for s in "${skills[@]}"; do
  n="$(field "$(frontmatter "$s")" name)"
  [ -n "$n" ] && NAMES["$n"]=1
done

# Pass 2: validate each skill.
for s in "${skills[@]}"; do
  rel="${s#"$ROOT"/}"
  [ "$(head -n1 "$s" | tr -d '\r')" = "---" ] || { err "$rel: missing opening --- frontmatter"; continue; }
  fm="$(frontmatter "$s")"
  name="$(field "$fm" name)"
  desc="$(field "$fm" description)"

  case "$name" in
    ss-?*|superstack) : ;;
    *) err "$rel: name must be 'superstack' (bootstrap) or start with 'ss-' (got '${name:-<none>}')" ;;
  esac

  if [ -z "$desc" ]; then
    err "$rel: missing description"
  else
    case "$desc" in Use\ *) : ;; *) err "$rel: description should start with \"Use \" (trigger-focused)";; esac
    dlen=${#desc}
    [ "$dlen" -ge 40 ]  || err "$rel: description too short ($dlen chars; aim >= 40)"
    [ "$dlen" -le 500 ] || err "$rel: description too long ($dlen chars; aim <= 500)"
  fi

  h1="$(count_h1 "$s")"
  [ "$h1" -eq 1 ] || err "$rel: expected exactly one H1 heading (found $h1)"

  for link in $(grep -o '\[\[[a-z0-9-]\+\]\]' "$s" | sed 's/\[\[//; s/\]\]//'); do
    [ -n "${NAMES[$link]:-}" ] || err "$rel: broken [[${link}]] link (no skill named '$link')"
  done
done

# Loop completeness: the eight phase skills must all exist.
for phase in ss-frame ss-plan ss-build ss-review ss-qa ss-secure ss-ship ss-learn; do
  [ -n "${NAMES[$phase]:-}" ] || err "loop incomplete: missing phase skill '$phase'"
done

# Agents
for a in "$ROOT"/agents/*.md; do
  rel="${a#"$ROOT"/}"
  [ "$(head -n1 "$a" | tr -d '\r')" = "---" ] || { err "$rel: missing opening --- frontmatter"; continue; }
  fm="$(frontmatter "$a")"
  [ -n "$(field "$fm" name)" ]        || err "$rel: missing name"
  [ -n "$(field "$fm" description)" ] || err "$rel: missing description"
done

# JSON manifests
if command -v jq >/dev/null 2>&1; then
  for j in "$ROOT"/.claude-plugin/plugin.json "$ROOT"/.claude-plugin/marketplace.json "$ROOT"/ralph/prd.example.json "$ROOT"/hooks/hooks.json; do
    [ -e "$j" ] || continue
    jq empty "$j" 2>/dev/null || err "${j#"$ROOT"/}: invalid JSON"
  done
else
  echo "note: jq not found - skipping JSON validation"
fi

if [ "$errors" -eq 0 ]; then
  echo "OK: ${#skills[@]} skill(s), agents, and manifests valid"
  exit 0
fi
echo "$errors problem(s) found"
exit 1
