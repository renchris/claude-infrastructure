#!/bin/bash
# find-plan.sh — resolve a plan name or path to a plan file + print its content,
# OR enumerate all open work across projects with --list-open.
#
# Usage:
#   find-plan.sh <name-or-path>      resolve a plan → print content
#   find-plan.sh --list-open         list every non-terminal plan (index ∪ disk),
#                                    one line each: STATUS | project | path | title.
#                                    Missing/unparseable status ⇒ UNKNOWN (never hidden);
#                                    complete/superseded are excluded. This is the desk's
#                                    "what is ALL open work?" verb (G-P14-4).
#
# Resolution order (first match wins):
#   1. Literal path (absolute or relative to cwd)
#   2. ~/.claude/plans/<name>
#   3. ~/.claude/plans/<name>.md
#   4. $PWD/.claude-plans/<name>(.md)
#   5. $PWD/docs/plans/<name>(.md)
#   6. Every Development/*/(.claude-plans|docs/plans)/<name>(.md)
#
# On success: prints file content to stdout, exit 0.
# On miss:    prints usage + searched paths to stderr, exit 1.

set -uo pipefail

# ── --list-open: cross-project open-work enumerator ─────────────────────────────
CC_PLAN_INDEX_PATH="${CC_PLAN_INDEX:-$HOME/.claude/plans-index.json}"

# plan_status <file> → open|in-progress|complete|superseded|unknown (YAML frontmatter
# `status:`). Missing/unparseable ⇒ unknown. Kept in sync with setup-plan-symlinks.sh
# and validate-plan-structure.sh (no shared lib per single-owner file boundary).
plan_status() {
  local f="$1" first val
  IFS= read -r first < "$f" 2>/dev/null || true
  [[ "$first" == "---" ]] || { printf 'unknown\n'; return 0; }
  val=$(sed -n '2,/^---$/{ /^[Ss][Tt][Aa][Tt][Uu][Ss]:/p; }' "$f" 2>/dev/null | head -1)
  [[ -n "$val" ]] || { printf 'unknown\n'; return 0; }
  val=${val#*:}
  val=$(printf '%s' "$val" | tr -d ' \t"'\''`' | tr '[:upper:]' '[:lower:]')
  case "$val" in in_progress) val=in-progress ;; completed) val=complete ;; esac
  case "$val" in
    open|in-progress|complete|superseded) printf '%s\n' "$val" ;;
    *) printf 'unknown\n' ;;
  esac
  return 0
}

plan_title() {
  local f="$1" t=""
  if head -1 "$f" 2>/dev/null | grep -qx -- '---'; then
    t=$(sed -n '2,/^---$/{ /^[Tt][Ii][Tt][Ll][Ee]:/p; }' "$f" 2>/dev/null | head -1)
    t=${t#*:}
  fi
  [[ -z "${t// /}" ]] && t=$(grep -m1 '^# ' "$f" 2>/dev/null | sed 's/^#[[:space:]]*//')
  [[ -z "${t// /}" ]] && t=$(basename "$f")
  printf '%s\n' "$t" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

project_name_for() {
  local p="$1" pn=""
  if [[ -f "$CC_PLAN_INDEX_PATH" ]]; then
    pn=$(jq -r --arg k "$p" '.plans[$k].projectName // empty' "$CC_PLAN_INDEX_PATH" 2>/dev/null)
  fi
  if [[ -z "$pn" ]]; then
    case "$p" in
      */docs/plans/*)    pn=$(basename "${p%/docs/plans/*}") ;;
      */.claude-plans/*) pn=$(basename "${p%/.claude-plans/*}") ;;
      *)                 pn="global" ;;
    esac
  fi
  printf '%s\n' "$pn"
}

list_open_scan_disk() {
  local roots=() d r
  if [[ -n "${CC_PLAN_SCAN_ROOTS:-}" ]]; then
    IFS=: read -ra roots <<< "$CC_PLAN_SCAN_ROOTS"
  else
    [[ -d "$HOME/.claude/plans" ]] && roots+=("$HOME/.claude/plans")
    for d in "$HOME"/Development/*/docs/plans;   do [[ -d "$d" ]] && roots+=("$d"); done
    for d in "$HOME"/Development/*/.claude-plans; do [[ -d "$d" ]] && roots+=("$d"); done
  fi
  for r in "${roots[@]}"; do
    [[ -d "$r" ]] || continue
    find "$r" -maxdepth 1 -type f -name '*.md' 2>/dev/null
  done
}

list_open() {
  {
    [[ -f "$CC_PLAN_INDEX_PATH" ]] && \
      jq -r '.plans | to_entries[] | (.value.path // .key)' "$CC_PLAN_INDEX_PATH" 2>/dev/null
    list_open_scan_disk
  } | awk 'NF && !seen[$0]++' | while IFS= read -r p; do
      [[ -f "$p" ]] || continue
      local st; st=$(plan_status "$p")
      case "$st" in complete|superseded) continue ;; esac
      printf '%-11s | %-24s | %s | %s\n' \
        "$(printf '%s' "$st" | tr '[:lower:]' '[:upper:]')" \
        "$(project_name_for "$p")" "$p" "$(plan_title "$p")"
    done
}

if [[ "${1:-}" == "--list-open" ]]; then
  list_open
  exit 0
fi

NAME="${1:-}"
if [[ -z "$NAME" ]]; then
  cat >&2 <<EOF
usage: find-plan.sh <plan-name-or-path>

Searches common plan directories for <name>.md or <name>:
  ~/.claude/plans/
  \$PWD/.claude-plans/
  \$PWD/docs/plans/
  ~/Development/*/.claude-plans/
  ~/Development/*/docs/plans/

Or accepts an absolute/relative path directly.
EOF
  exit 1
fi

# 1. Literal path (absolute or relative to cwd)
if [[ -f "$NAME" ]]; then
  cat "$NAME"
  exit 0
fi

# Build search list. Order matters: user's home first, then project-local.
declare -a DIRS=(
  "$HOME/.claude/plans"
  "$PWD/.claude-plans"
  "$PWD/docs/plans"
)

# Add other Development project plan dirs (non-fatal if glob doesn't match).
for d in "$HOME"/Development/*/.claude-plans; do
  [[ -d "$d" ]] && DIRS+=("$d")
done
for d in "$HOME"/Development/*/docs/plans; do
  [[ -d "$d" ]] && DIRS+=("$d")
done

# 2-N. Search each directory for name + name.md
for dir in "${DIRS[@]}"; do
  for suffix in "" ".md"; do
    f="$dir/$NAME$suffix"
    if [[ -f "$f" ]]; then
      cat "$f"
      exit 0
    fi
  done
done

# Not found — emit helpful error
{
  echo "Plan not found: $NAME"
  echo ""
  echo "Searched:"
  for dir in "${DIRS[@]}"; do
    echo "  $dir/$NAME.md"
  done
} >&2
exit 1
