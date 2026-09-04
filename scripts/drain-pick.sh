#!/usr/bin/env bash
# drain-pick.sh — the ranked worklist a drain link picks its next row from. READ-ONLY.
#
# WHY A SCRIPT AND NOT A SENTENCE IN THE BRIEF. The old chain's brief told each link to "pick the
# smallest live master-* effort from the current fold" — a selection rule retyped by a model, which
# decayed into no selection at all (§4.1's own invariant 1, unreachable by #299). This prints the
# choice so the link reads a table instead of composing a query, and so the same ranking runs on
# every link (memory `enforcement-must-live-at-the-chokepoint`).
#
# THE RANKING, cheapest adjudication first, oldest first within a tier:
#   tier 0  carries a falsifier — one command decides it (exit 0 = retract; exit ≠0 = still real)
#   tier 1  carries a dodRef — a document says what done means
#   tier 2  everything else
#   tier 3  umbrellas ("advance MASTER: …", "W4 WAVE: …", condition group parents) — closable only
#           when their group is empty, so they go last rather than being taken first and released
# Rows are EXCLUDED, and counted in the footer, when: status is not `open` (blocked/claimed/done),
# the project does not match, or the row has been claimed >= --max-claims times without a done —
# the thrash class DRAIN_CIRCUIT_2026-09-01 §1.3 measured (17 ids re-claimed 8–23 times, 1 done).
# Those are printed as a count with their ids so a link can see them and choose not to be the 24th
# claimer.
#
# Usage:
#   drain-pick.sh [--project P[,P2]] [--top N] [--max-claims K] [--json]
#     --project   default claude-infrastructure; `all` = every non-skip project in
#                 scripts/dispatch-projects.conf
#     --top       rows to print (default 10)
#     --max-claims  thrash ceiling (default 5)
#     --json      one JSON array of the ranked rows instead of the table
# Env: CC_BACKLOG_FILE (the ledger), CC_BACKLOG_BIN (default bin/cc-backlog beside this script's repo)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
CB="${CC_BACKLOG_BIN:-$REPO/bin/cc-backlog}"
CFG="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
LEDGER="${CC_BACKLOG_FILE:-$CFG/autonomy/backlog.jsonl}"
CONF="${CC_DISPATCH_PROJECTS:-$HERE/dispatch-projects.conf}"

die() { printf 'drain-pick: %s\n' "$1" >&2; exit "${2:-2}"; }

PROJECT="claude-infrastructure"; TOP=10; MAXC=5; JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project)    PROJECT="${2:?--project needs a label}"; shift 2 ;;
    --top)        TOP="${2:?--top needs a number}"; shift 2 ;;
    --max-claims) MAXC="${2:?--max-claims needs a number}"; shift 2 ;;
    --json)       JSON=1; shift ;;
    -h|--help)    sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *)            die "unknown argument: $1" ;;
  esac
done
case "$TOP" in ''|*[!0-9]*) die "--top must be digits" ;; esac
case "$MAXC" in ''|*[!0-9]*) die "--max-claims must be digits" ;; esac
command -v jq >/dev/null 2>&1 || die "jq is required" 4
[ -r "$LEDGER" ] || die "no readable ledger at $LEDGER" 4
[ -x "$CB" ] || [ -r "$CB" ] || die "no cc-backlog at $CB" 4

if [ "$PROJECT" = all ]; then
  [ -r "$CONF" ] || die "--project all needs $CONF" 4
  # A conf line is `<label>  repo=…` or `<label>  skip=…`; the label is the first word, skips drop.
  PROJECT="$(grep -vE '^\s*#|^\s*$' "$CONF" | grep -v 'skip=' | awk '{print $1}' | paste -sd, -)"
  [ -n "$PROJECT" ] || die "no non-skip projects in $CONF" 4
fi

rows="$(CC_BACKLOG_FILE="$LEDGER" bash "$CB" list --open --json 2>/dev/null)" || die "cc-backlog list failed" 4
[ -n "$rows" ] || rows='[]'

# Claim counts and falsifier presence come from the STORE, not the list surface: the list synthesizes
# status and carries neither. Fold on the `id` FIELD (never grep the line — ids appear in other rows'
# prose; backlog-telemetry.sh measured OWN=5/CITE=2 on one id).
aux="$(jq -cs '
  ( [ .[] | select(.event=="claim") | .id ] | group_by(.) | map({key: .[0], value: length}) | from_entries ) as $claims
  | ( [ .[] | select(.event=="falsify") | .id ] | unique ) as $fals
  | {claims: $claims, falsifiers: $fals}' "$LEDGER" 2>/dev/null)" || die "could not fold $LEDGER" 4

ranked="$(jq -c --argjson aux "$aux" --arg projects "$PROJECT" --argjson maxc "$MAXC" --argjson top "$TOP" '
  ($projects | split(",")) as $ps
  | (now) as $now
  | [ .[]
      | select(.status == "open")
      | select(.project as $p | $ps | index($p) != null)
      | .id as $id
      | . + { claims: ($aux.claims[$id] // 0),
              falsifier: (($aux.falsifiers | index($id)) != null),
              age_d: ((($now - (.firstTs | sub("Z$"; "") | strptime("%Y-%m-%dT%H:%M:%S") | mktime)) / 86400) | floor) }
      | . + { tier: (if (.title | test("^(advance MASTER|W[0-9]+ WAVE|MASTER:)")) then 3
                     elif .falsifier then 0
                     elif ((.dodRef // "") != "") then 1
                     else 2 end) }
    ] as $all
  | ($all | map(select(.claims >= $maxc))) as $thrash
  | ($all | map(select(.claims < $maxc)) | sort_by(.tier, .firstTs)) as $pick
  | { candidates: ($pick | .[0:$top] | map({rank: 0, id, project, age_d, claims, tier, condition: (.condition // ""), title})),
      eligible: ($pick | length),
      thrash: ($thrash | map({id, claims, title: (.title[0:60])})),
      projects: $ps }
  | .candidates |= (to_entries | map(.value + {rank: (.key + 1)}))
' <<<"$rows")" || die "ranking failed" 4

if [ "$JSON" -eq 1 ]; then printf '%s\n' "$ranked" | jq '.candidates'; exit 0; fi

printf 'DRAIN PICK  ·  %s  ·  projects=%s  ·  ledger=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROJECT" "$LEDGER"
printf 'ranking: tier 0 falsifier · 1 dodRef · 2 plain · 3 umbrella; oldest first within a tier; status=open only;\n'
printf '         rows claimed >= %s times are held back (thrash) and listed below, not ranked.\n' "$MAXC"
printf '%-4s %-13s %-22s %5s %6s %4s  %s\n' rank id project age_d claims tier title
printf '%s\n' "$ranked" | jq -r '.candidates[] | [(.rank|tostring), .id, (.project[0:22]), (.age_d|tostring), (.claims|tostring), (.tier|tostring), (.title[0:96])] | @tsv' \
  | awk -F'\t' '{printf "%-4s %-13s %-22s %5s %6s %4s  %s\n", $1, $2, $3, $4, $5, $6, $7}'
elig="$(printf '%s' "$ranked" | jq -r '.eligible')"
nthr="$(printf '%s' "$ranked" | jq -r '.thrash | length')"
printf 'eligible=%s shown=%s thrash_held=%s\n' "$elig" "$(printf '%s' "$ranked" | jq -r '.candidates | length')" "$nthr"
if [ "$nthr" -gt 0 ]; then
  printf '%s\n' "$ranked" | jq -r '.thrash[] | "  held: \(.id) claims=\(.claims) \(.title)"'
fi
