#!/usr/bin/env bash
# backlog-consolidation-trigger.sh — notice that it is time to consolidate, so a human does not have to.
#
# WHY THIS EXISTS. Deciding what constitutes "one effort" needs judgment. Noticing that the moment
# has arrived does not — and on 2026-08-09 the trigger was the operator feeling the pain and asking
# for a heroic sweep. By then the store held 18 rows for a single failing suite, all minted by one
# generator that keys its item ids per-sha. Nothing counted them; nothing said "these are one thing".
#
# THE SHAPE IT LOOKS FOR, and why exact-match would find nothing. `cc-backlog` hashes an item id from
# project+title+source, so two rows with an IDENTICAL title collapse to the same id by construction —
# a duplicate CANNOT exist in that form. Duplicates arise precisely when the title VARIES in a part
# that carries no meaning: an embedded sha, a count, a size, a timestamp. That is why this normalises
# shas and digits out of the title before grouping. Measured on the live store 2026-08-10, AFTER the
# 161-item prune: zero clusters at threshold 2 — the shape is real but currently absent, which is why
# the positive control lives in the fixture (tests/) and not in a live-store assertion.
#
# ALARM POLARITY. Silent when healthy. A trigger that fires on every run is one the reader learns to
# skip, and it would fire on this store today for no reason (MEMORY.md:
# alarm-polarity-and-attention-budget). It speaks only when a cluster crosses the threshold.
#
# IT FILES, RATHER THAN PRINTS. A printed warning is advisory and dies with the terminal that showed
# it; the whole class of failure this repo keeps rediscovering is a conclusion that never reaches an
# enforcing store. `--file` writes ONE condition-keyed item, so repeated runs update rather than mint
# — the same defect (one row per measurement) that this script exists to detect must not be committed
# by the detector itself.
#
# Usage:
#   backlog-consolidation-trigger.sh                 report clusters at/above threshold; exit 0
#   backlog-consolidation-trigger.sh --assert        exit 1 if any cluster crosses (for a gate)
#   backlog-consolidation-trigger.sh --file          file/update ONE condition-keyed backlog item
#   --threshold N                                    default 5
set -uo pipefail

BACKLOG="${CC_BACKLOG_FILE:-$HOME/.claude/autonomy/backlog.jsonl}"
BACKLOG_BIN="${CC_BACKLOG_BIN:-$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")/bin/cc-backlog}"
THRESHOLD=5
MODE="report"
while [ $# -gt 0 ]; do
  case "$1" in
    --assert) MODE="assert"; shift ;;
    --file)   MODE="file"; shift ;;
    --threshold) THRESHOLD="${2:-5}"; shift 2 ;;
    --help|-h) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *) printf 'backlog-consolidation-trigger: unknown arg %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -f "$BACKLOG" ] || { printf 'no store at %s — nothing to measure\n' "$BACKLOG" >&2; exit 0; }
command -v jq >/dev/null 2>&1 || { printf 'jq missing — cannot measure (fail-open)\n' >&2; exit 0; }

# The FOLD first (an item's state is its last event), then normalise the MEANINGLESS parts of the
# title away. `[0-9a-f]{7,40}` is deliberately greedy about shas; it also eats hex-looking words like
# "added", which is acceptable here because the key is only ever compared against other keys built
# the same way — it never has to be read back or resolved.
#
# `cell` pads the two non-numeric cells: the fold defaults an absent project to "" (line below), and
# tab is IFS-whitespace, so an empty project cell collapses the run and shifts the TITLE into the
# project column with a blank title after it — the same defect this repo pinned in cc-backlog's own
# `list` render (tests/tsv-field-collapse.bats §2). It is reachable today: `cc-backlog add` without
# --project mints exactly such an item, and .key groups on the project, so a cluster of them is a
# cluster of empty cells. gsub also flattens a tab/newline pasted into a title, which would widen
# the row into cells the reader has no variables for.
clusters="$(jq -rs --argjson th "$THRESHOLD" '
  def cell(ph): (if . == null then "" else . end) | tostring
                | gsub("[\\t\\r\\n]"; " ") | if . == "" then ph else . end;
  (reduce .[] as $r ({};
     .[$r.id] //= {title: ($r.title // ""), project: ($r.project // ""), status: "open"}
   | (if ($r.event // "") == "done"   then .[$r.id].status = "done"
      elif ($r.event // "") == "block"  then .[$r.id].status = "blocked"
      elif ($r.event // "") == "reopen" then .[$r.id].status = "open"
      else . end)))
  | [ .[] | select(.status == "open" or .status == "blocked") ]
  | map(.key = (.project + "|" + (.title | ascii_downcase
        | gsub("[0-9a-f]{7,40}"; "<sha>") | gsub("[0-9]+"; "<n>") | .[0:90])))
  | group_by(.key) | map(select(length >= $th)) | sort_by(-length)
  | map("\(length)\t\(.[0].project | cell("-"))\t\(.[0].title[0:110] | cell("-"))") | .[]
' "$BACKLOG" 2>/dev/null)"

n_clusters=0
[ -n "$clusters" ] && n_clusters="$(printf '%s\n' "$clusters" | grep -c . || echo 0)"

if [ "$n_clusters" -eq 0 ]; then
  [ "$MODE" = "report" ] && printf 'backlog-consolidation-trigger: no cluster at/above %s — nothing to consolidate.\n' "$THRESHOLD"
  exit 0
fi

biggest="$(printf '%s\n' "$clusters" | head -1 | cut -f1)"
printf 'backlog-consolidation-trigger: %s cluster(s) at/above %s — largest is %sx.\n' "$n_clusters" "$THRESHOLD" "$biggest"
printf '%s\n' "$clusters" | while IFS=$'\t' read -r cnt proj title; do
  printf '  %sx  [%s]  %s\n' "$cnt" "$proj" "$title"
done
printf 'These are one effort wearing N rows. Consolidate them, or fix the generator that mints them.\n'

case "$MODE" in
  assert) exit 1 ;;
  file)
    [ -x "$BACKLOG_BIN" ] || { printf 'cannot file: no cc-backlog at %s\n' "$BACKLOG_BIN" >&2; exit 1; }
    # ONE condition-keyed row. Without --condition this would mint a fresh item per run (the title
    # carries a live count), reproducing one layer down the exact defect it reports.
    "$BACKLOG_BIN" add --project claude-infrastructure \
      --source backlog-consolidation-trigger \
      --condition backlog-duplicate-cluster-over-threshold \
      --falsifier "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/backlog-consolidation-trigger.sh --threshold $THRESHOLD" \
      --title "$n_clusters duplicate cluster(s) at/above $THRESHOLD rows (largest ${biggest}x) — one effort wearing N rows. Consolidate, or fix the generator whose id keying mints a row per sha. Detected by backlog-consolidation-trigger.sh; the falsifier on this row IS that detector, so this item closes itself when the clusters are gone." \
      >/dev/null 2>&1 && printf 'filed/updated the condition-keyed consolidation item.\n'
    exit 0
    ;;
esac
exit 0
