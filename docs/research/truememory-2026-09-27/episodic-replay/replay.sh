#!/bin/bash
# replay.sh — would the episodic cue's own query have found the gold for each of the 4 cited misses?
# For every target in targets.jsonl (the real prompt text, gap-2.md:54-57) it derives the noun query
# with hooks/lib/episodic_cue.sh's OWN jq program, runs claude-search's engine with
# `--format json --limit 50` (plain, then --deep-search), keeps only results created BEFORE the
# prompt (`at`) and not the incident session itself (`self_sid`), and prints whether the gold appears
# in the top 5 of those (a result whose text matches gold_re, or whose session id starts with a gold
# sid). The filter is ours because claude-search's own --before is silently ignored (measured
# 2026-09-28: --before 2026-09-27 returned sessions from 09-27T20:10Z and 09-28). #110 is a true
# negative: there, a hit would be the surprise.
#
# READ-ONLY by construction: every search inserts a search_log row and rewrites a results cache, so
# the index is copied with sqlite3 `.backup` into a mktemp HOME and the engine runs there. The live
# ~/.claude/session-index.db is only read.
# Usage: bash replay.sh [session-index.db] [session-search.py]
# Run it BEFORE and AFTER the workflow-indexing item (#18a) lands; record both in README.md.
set -u
here=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$here/../../../.." && pwd)
DB=${1:-$HOME/.claude/session-index.db}
PY=${2:-$(readlink -f "$HOME/.claude/bin/session-search.py" 2>/dev/null || echo "$HOME/.claude/bin/session-search.py")}
# shellcheck source=../../../../hooks/lib/episodic_cue.sh
# shellcheck disable=SC1091
. "$REPO/hooks/lib/episodic_cue.sh"
T=$(mktemp -d)
mkdir -p "$T/.claude"
sqlite3 "$DB" ".backup '$T/.claude/session-index.db'" || { echo "COPY-FAIL: could not back up $DB"; exit 2; }
echo "index: $DB (copied; $(sqlite3 "$T/.claude/session-index.db" 'select count(*) from sessions') sessions)"
while IFS= read -r row; do
  id=$(jq -r .id <<< "$row"); at=$(jq -r .at <<< "$row"); self=$(jq -r .self_sid <<< "$row")
  re=$(jq -r .gold_re <<< "$row")
  prompt=$(jq -j .prompt <<< "$row")
  line=$(jq -rn --arg p "$prompt" "$_EC_JQ")
  verdict=${line%%$'\x1f'*}; nouns=${line#*$'\x1f'}
  echo "#$id  cue=$verdict  query='$nouns'  ($(jq -r .gold <<< "$row"))"
  for mode in plain deep; do
    extra=(); [ "$mode" = deep ] && extra=(--deep-search)
    out=$(HOME="$T" python3 "$PY" --format json --limit 50 ${extra[@]+"${extra[@]}"} "$nouns" 2>/dev/null) || out='[]'
    jq -e 'type == "array"' >/dev/null 2>&1 <<< "$out" || out='[]'
    out=$(jq -c --arg at "$at" --arg self "$self" \
      '[.[] | select((.created_at // "9999") < $at and ((.session_id // "") | startswith($self) | not))][:5]' <<< "$out")
    rank=$(jq -r --arg re "$re" --argjson sids "$(jq -c .gold_sids <<< "$row")" '
      [to_entries[] | .key as $k | .value
       | select(((.summary // "") + " " + (.first_prompt // "") + " " + (.context_text // "") + " "
                 + ((.keywords // "") | tostring) + " " + ((.chunk_text // .matched_chunk // "") | tostring))
                | test($re; "i"))
                or ((.session_id // "") as $s | any($sids[]; . as $g | $s | startswith($g)))
       | $k + 1][0] // "none"' <<< "$out")
    printf '    %-5s results=%s gold-rank=%s top5=%s\n' "$mode" "$(jq length <<< "$out")" "$rank" \
      "$(jq -r '[.[] | "\((.session_id // "?")[0:8])@\((.created_at // "?")[0:10])"] | join(",")' <<< "$out")"
  done
done < "$here/targets.jsonl"
rm -rf "$T"
