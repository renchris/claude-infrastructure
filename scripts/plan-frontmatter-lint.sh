#!/bin/bash
# plan-frontmatter-lint.sh — every plan in docs/plans/*.md opens with YAML frontmatter carrying a
# `status:` (BACKLOG_MASTER W0 ledger-retraction.3).
#
# find-plan.sh --list-open reads a plan's status from its frontmatter; a plan without one is listed
# as UNKNOWN forever and the plan-open producer keeps an `advance <plan>` row open for it. So the
# frontmatter is what lets a finished plan retract its row.
#
# DESIGN COMPANIONS ARE EXCLUDED: a file under a subdirectory of docs/plans/ (a programme's working
# notes), or a top-level file whose first line is `<!-- plan-companion: <PLAN> -->`. A companion
# carries no status of its own; its plan does.
#
# usage: plan-frontmatter-lint.sh [--file <path>]... | --selftest
# exit 0 clean · 1 a plan lacks frontmatter/status (named) · 2 usage
set -uo pipefail

check() { # <file> → rc 0 ok / 1 finding (printed)
  local f="$1" first
  case "$f" in docs/plans/*/*|*/docs/plans/*/*) return 0 ;; esac
  IFS= read -r first < "$f" 2>/dev/null || first=""
  case "$first" in "<!-- plan-companion:"*) return 0 ;; esac
  if [ "$first" != "---" ]; then
    printf 'plan-frontmatter: %s has no frontmatter — open it with ---/status: <open|in-progress|complete|superseded>/---\n' "$f"
    return 1
  fi
  if ! sed -n '2,/^---$/p' "$f" | grep -qiE '^status:[[:space:]]*[^[:space:]]'; then
    printf 'plan-frontmatter: %s has frontmatter but no status: line\n' "$f"
    return 1
  fi
  return 0
}

selftest() {
  local d rc=0; d="$(mktemp -d)"
  mkdir -p "$d/docs/plans/sub"
  printf -- '---\nstatus: open\n---\n# ok\n' > "$d/docs/plans/OK.md"
  printf '# bare\n' > "$d/docs/plans/BARE.md"
  printf -- '---\ntitle: x\n---\n' > "$d/docs/plans/NOSTATUS.md"
  printf '<!-- plan-companion: OK -->\n# notes\n' > "$d/docs/plans/NOTES.md"
  printf '# sub notes\n' > "$d/docs/plans/sub/x.md"
  check "$d/docs/plans/OK.md" >/dev/null || rc=1
  check "$d/docs/plans/NOTES.md" >/dev/null || rc=1
  check "$d/docs/plans/sub/x.md" >/dev/null || rc=1
  check "$d/docs/plans/BARE.md" >/dev/null && rc=1
  check "$d/docs/plans/NOSTATUS.md" >/dev/null && rc=1
  rm -f "$d"/docs/plans/*.md "$d"/docs/plans/sub/x.md; rmdir "$d/docs/plans/sub" "$d/docs/plans" "$d/docs" "$d" 2>/dev/null
  return "$rc"
}

files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) selftest; exit $? ;;
    --file) files+=("${2:-}"); shift 2 ;;
    *) echo "usage: $0 [--file <path>]... | --selftest" >&2; exit 2 ;;
  esac
done
if [ "${#files[@]}" -eq 0 ]; then
  cd "$(dirname "$0")/.." || exit 2
  for f in docs/plans/*.md; do [ -e "$f" ] && files+=("$f"); done
fi
bad=0
for f in ${files[@]+"${files[@]}"}; do check "$f" || bad=$((bad + 1)); done
[ "$bad" -eq 0 ]
