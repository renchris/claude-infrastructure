#!/bin/bash
# plan-index-update.sh — durable plan indexer for the desk mission-ledger.
#
# Two modes:
#   (default / hook)  PostToolUse Write|Edit: reads the tool payload on stdin and
#                     indexes a plan write into plans-index.json. Indexes ALL three
#                     plan namespaces — global (~/.claude/plans), */docs/plans, and
#                     */.claude-plans — keyed by ABSOLUTE PATH (no cross-project
#                     basename collision).
#   reconcile         `plan-index-update.sh reconcile`: rebuild the index from disk
#                     truth. Prunes phantom entries (file-missing ⇒ drop), adds any
#                     on-disk plan missing from the index, preserves firstIndexed on
#                     survivors, and refreshes `generated`. Runnable standalone (does
#                     NOT read stdin). Wire it at SessionStart — see
#                     docs/activation/ledger-activate-snippet.md.
#
# Env overrides (tests): CC_PLAN_INDEX, CC_PLANS_DIR, CC_PLAN_SCAN_ROOTS (colon-list).
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INDEX="${CC_PLAN_INDEX:-$HOME/.claude/plans-index.json}"
PLANS_DIR="${CC_PLANS_DIR:-$HOME/.claude/plans}"

# classify_path <abspath> → sets PROJ / PN / NS (namespace) globals.
classify_path() {
  local p="$1"
  case "$p" in
    */docs/plans/*.md)     PROJ="${p%/docs/plans/*}";    NS="docs-plans" ;;
    */.claude-plans/*.md)  PROJ="${p%/.claude-plans/*}"; NS="claude-plans" ;;
    "$PLANS_DIR"/*.md)     PROJ="$PLANS_DIR";            NS="global" ;;
    *)                     PROJ="$(dirname "$p")";       NS="other" ;;
  esac
  PN="$(basename "$PROJ")"
  if [ "$PROJ" = "$PLANS_DIR" ]; then PN="global"; fi
  return 0   # never let a false test trip `set -e` at a bare call site
}

# ── reconcile mode ──────────────────────────────────────────────────────────────
reconcile() {
  local now; now=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  [ -f "$INDEX" ] || echo '{"version":1,"plans":{}}' > "$INDEX"

  # Scan roots: explicit override, else global sink + every Development project store.
  local -a roots=()
  if [ -n "${CC_PLAN_SCAN_ROOTS:-}" ]; then
    IFS=: read -ra roots <<< "$CC_PLAN_SCAN_ROOTS"
  else
    [ -d "$PLANS_DIR" ] && roots+=("$PLANS_DIR")
    local d
    for d in "$HOME"/Development/*/docs/plans;    do [ -d "$d" ] && roots+=("$d"); done
    for d in "$HOME"/Development/*/.claude-plans;  do [ -d "$d" ] && roots+=("$d"); done
  fi

  local lines; lines=$(mktemp)
  # 1. Existing entries whose file still exists (phantom ⇒ dropped by omission).
  jq -r '.plans | to_entries[] | [ (.value.path // .key), (.value.firstIndexed // "") ] | @tsv' \
     "$INDEX" 2>/dev/null | while IFS=$'\t' read -r p first; do
       [ -n "$p" ] || continue
       case "$p" in /*) ;; *) p="$PLANS_DIR/$p" ;; esac   # legacy basename ⇒ global sink
       [ -f "$p" ] || continue
       classify_path "$p"
       printf '%s\t%s\t%s\t%s\t%s\n' "$p" "$PROJ" "$PN" "$NS" "$first"
     done >> "$lines"

  # 2. Disk truth from every scan root.
  local root f
  for root in "${roots[@]}"; do
    [ -d "$root" ] || continue
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      classify_path "$f"
      printf '%s\t%s\t%s\t%s\t%s\n' "$f" "$PROJ" "$PN" "$NS" ""
    done < <(find "$root" -maxdepth 1 -type f -name '*.md' 2>/dev/null)
  done >> "$lines"

  # 3. Fold to an abspath-keyed object; prefer any non-empty firstIndexed, else now.
  local tmp; tmp=$(mktemp)
  jq -Rn --arg now "$now" '
    reduce (inputs | split("\t")) as $e ({};
      ($e[0]) as $path |
      if ($path | length) == 0 then . else
      .[$path] = (
        (.[$path] // {}) as $prev |
        {
          project:      $e[1],
          projectName:  $e[2],
          path:         $path,
          basename:     ($path | split("/") | last),
          namespace:    $e[3],
          firstIndexed: (if ($e[4] // "") != "" then $e[4]
                         elif ($prev.firstIndexed // "") != "" then $prev.firstIndexed
                         else $now end),
          lastSeen:     $now
        }
      ) end
    ) | { version: 1, generated: $now, plans: . }
  ' "$lines" > "$tmp" && mv "$tmp" "$INDEX"
  rm -f "$lines"
}

# ── dispatch ────────────────────────────────────────────────────────────────────
case "${1:-hook}" in
  reconcile) reconcile; exit 0 ;;
esac

# ── hook mode (PostToolUse) ─────────────────────────────────────────────────────
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_result.filePath // empty')
[ -z "$FILE" ] && exit 0

case "$FILE" in
  "$PLANS_DIR"/*.md)     ;;
  */docs/plans/*.md)     ;;
  */.claude-plans/*.md)  ;;
  *) exit 0 ;;
esac

classify_path "$FILE"

# Global plans carry no project in their path — attribute to the authoring cwd.
if [ "$NS" = "global" ]; then
  CWD="${CLAUDE_PROJECT_DIR:-}"
  [ -z "$CWD" ] && CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
  if [ -n "$CWD" ]; then
    case "$CWD" in "$HOME/.claude"|"$HOME/.claude/"*) exit 0 ;; esac   # not a project
    PROJ="$CWD"; PN="$(basename "$CWD")"
  fi
fi

NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
[ -f "$INDEX" ] || echo '{"version":1,"plans":{}}' > "$INDEX"

TEMP=$(mktemp)
jq --arg path "$FILE" --arg project "$PROJ" --arg projectName "$PN" \
   --arg ns "$NS" --arg base "$(basename "$FILE")" --arg now "$NOW" \
   '.version = (.version // 1)
    | .plans[$path] = (
        (.plans[$path] // {})
        | .project = $project
        | .projectName = $projectName
        | .path = $path
        | .basename = $base
        | .namespace = $ns
        | .lastSeen = $now
        | .firstIndexed = (.firstIndexed // $now)
      )
    | .generated = $now' \
   "$INDEX" > "$TEMP" && mv "$TEMP" "$INDEX"

exit 0
