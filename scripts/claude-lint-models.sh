#!/usr/bin/env bash
# claude-lint-models — flag stale model references in a file (or all tracked).
#
# Usage:
#   claude-lint-models.sh <file>     # lint one file
#   claude-lint-models.sh --all      # lint every UPDATE-classified file
#
# Exit codes:
#   0 — clean
#   1 — stale refs present
#   2 — usage / config error
#
# macOS bash 3.2 compatible.

set -uo pipefail

readonly CONFIG="$HOME/.claude/model-config.yaml"
readonly CLASSIFICATION="$HOME/.claude/model-classification.json"

command -v yq >/dev/null 2>&1 || { echo "ERROR: yq not installed" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not installed" >&2; exit 2; }
[[ -f "$CONFIG" ]] || { echo "ERROR: missing $CONFIG" >&2; exit 2; }
[[ -f "$CLASSIFICATION" ]] || { echo "ERROR: missing $CLASSIFICATION" >&2; exit 2; }

# Collect stale literals: *_prior versions + deprecations map keys.
STALE_LITERALS_FILE=$(mktemp)
trap 'rm -f "$STALE_LITERALS_FILE"' EXIT

yq -r '.versions | to_entries | .[] | select(.key | test("_prior$")) | .value' "$CONFIG" >> "$STALE_LITERALS_FILE" 2>/dev/null || true
yq -r '.deprecations | keys[]' "$CONFIG" >> "$STALE_LITERALS_FILE" 2>/dev/null || true

# Dedupe + strip blanks
sort -u "$STALE_LITERALS_FILE" | grep -v '^$' > "${STALE_LITERALS_FILE}.clean"
mv "${STALE_LITERALS_FILE}.clean" "$STALE_LITERALS_FILE"

is_preserved() {
  # Return 0 (true) if $1 matches any preserve glob; 1 otherwise.
  local file="$1" glob
  while IFS= read -r glob; do
    [[ -z "$glob" ]] && continue
    # Strip leading ** for anywhere-match; else exact-ish substring.
    if [[ "$glob" == "**"* ]]; then
      local subpath="${glob#**/}"
      # Match if file contains the subpath fragment
      case "$file" in *"/$subpath"*|*"/$subpath") return 0 ;; esac
    else
      case "$file" in *"$glob"*) return 0 ;; esac
    fi
  done < <(jq -r '.preserve[]' "$CLASSIFICATION")
  return 1
}

lint_file() {
  local file="$1"
  if is_preserved "$file"; then
    return 0
  fi
  local stale_found=0 found="" literal
  while IFS= read -r literal; do
    [[ -z "$literal" ]] && continue
    # Word-boundary match: literal must NOT be followed by `-` or a digit.
    # Prevents "claude-opus-4" (deprecated undated) matching "claude-opus-4-7".
    if grep -qE "${literal}([^-0-9]|\$)" "$file" 2>/dev/null; then
      stale_found=1
      found="$found $literal"
    fi
  done < "$STALE_LITERALS_FILE"
  if [[ $stale_found -eq 1 ]]; then
    echo "❌ $file: stale refs:$found"
    return 1
  fi
  return 0
}

if [[ $# -eq 0 ]]; then
  echo "Usage: $(basename "$0") <file> | --all" >&2
  exit 2
elif [[ "$1" == "--all" ]]; then
  fail_count=0
  while IFS= read -r root; do
    [[ -d "$root" ]] || continue
    while IFS= read -r glob; do
      if [[ "$glob" == "**"* ]]; then
        subpath="${glob#**/}"
        while IFS= read -r f; do
          lint_file "$f" || fail_count=$((fail_count + 1))
        done < <(find "$root" -type f -path "*/$subpath" 2>/dev/null)
      else
        while IFS= read -r f; do
          lint_file "$f" || fail_count=$((fail_count + 1))
        done < <(find "$root" -type f -path "$root/$glob" 2>/dev/null)
      fi
    done < <(jq -r '.update[]' "$CLASSIFICATION")
  done < <(jq -r '.roots[]' "$CLASSIFICATION")
  if [[ $fail_count -gt 0 ]]; then
    echo ""
    echo "❌ $fail_count file(s) with stale refs. Fix: claude-bump-models --apply"
    exit 1
  fi
  echo "✅ All UPDATE-classified files clean."
else
  lint_file "$1"
  exit $?
fi
