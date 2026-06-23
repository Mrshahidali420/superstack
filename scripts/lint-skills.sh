#!/usr/bin/env bash
# Lint SuperStack skills, agents, and JSON manifests.
# Every skill/agent must have frontmatter with a name (skills: starting "ss-") and a
# description. JSON manifests must parse. Exits non-zero on any problem.
#
# Usage: scripts/lint-skills.sh [root]   (default: the repo this script lives in)
set -uo pipefail
shopt -s nullglob

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
errors=0
err() { echo "FAIL: $*"; errors=$((errors + 1)); }

# Extract the frontmatter block (between the first two --- lines).
frontmatter() { awk 'NR==1 && $0!="---"{exit} NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$1"; }
field() { printf '%s\n' "$1" | grep -m1 "^$2:" | sed "s/^$2:[[:space:]]*//" | tr -d '\r'; }

# --- Skills ---------------------------------------------------------------
skills=("$ROOT"/skills/*/SKILL.md)
[ ${#skills[@]} -gt 0 ] || err "no skills found under $ROOT/skills"
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
  [ -n "$desc" ] || err "$rel: missing description"
done

# --- Agents ---------------------------------------------------------------
for a in "$ROOT"/agents/*.md; do
  rel="${a#"$ROOT"/}"
  [ "$(head -n1 "$a" | tr -d '\r')" = "---" ] || { err "$rel: missing opening --- frontmatter"; continue; }
  fm="$(frontmatter "$a")"
  [ -n "$(field "$fm" name)" ]        || err "$rel: missing name"
  [ -n "$(field "$fm" description)" ] || err "$rel: missing description"
done

# --- JSON manifests -------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  for j in "$ROOT"/.claude-plugin/plugin.json "$ROOT"/.claude-plugin/marketplace.json "$ROOT"/ralph/prd.example.json; do
    [ -e "$j" ] || continue
    jq empty "$j" 2>/dev/null || err "${j#"$ROOT"/}: invalid JSON"
  done
else
  echo "note: jq not found - skipping JSON validation"
fi

# --- Result ---------------------------------------------------------------
if [ "$errors" -eq 0 ]; then
  echo "OK: ${#skills[@]} skill(s), agents, and manifests valid"
  exit 0
fi
echo "$errors problem(s) found"
exit 1
