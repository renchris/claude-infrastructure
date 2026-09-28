#!/bin/bash
# fire-rate.sh — how often does hooks/lib/episodic_cue.sh fire on real typed prompts? READ-ONLY.
# Scores every `display` in ~/.claude/history-union.jsonl (entries starting with `<` or `/` dropped,
# as the brief specifies) with the lib's OWN jq program — the same eligibility and patterns the hook
# runs — and prints the fire rate over all typed prompts and over the last 30 days, the per-pattern
# counts, and every 30-day fire's first 160 chars so a reader can judge precision by eye.
# Usage: bash fire-rate.sh [history.jsonl] [now-epoch-seconds]
set -u
here=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$here/../../../.." && pwd)
H=${1:-$HOME/.claude/history-union.jsonl}
NOW=${2:-$(date +%s)}
# shellcheck source=../../../../hooks/lib/episodic_cue.sh
# shellcheck disable=SC1091
. "$REPO/hooks/lib/episodic_cue.sh"
defs="${_EC_JQ%%(try verdict*}"
# shellcheck disable=SC2016  # jq program
prog='select(.display | type == "string") | .display as $p
  | select(($p | test("\\A\\s*[</]")) | not)
  | [((.timestamp // 0) | tonumber? // 0 | tostring),
     ((try verdict($p) catch ["classify-error", ""])[0]),
     ($p | .[0:160] | gsub("[[:cntrl:]]+"; " "))] | join("\t")'
T=$(mktemp)
jq -r "$defs $prog" "$H" > "$T"
cut30=$(( (NOW - 30 * 86400) * 1000 ))
awk -F'\t' -v c="$cut30" '
  { n++; if ($2 ~ /^fired:/) f++; if ($2 == "not-typed") nt++
    if ($1 + 0 >= c) { n30++; if ($2 ~ /^fired:/) { f30++; ex[f30] = $2 "  " $3 } if ($2 == "not-typed") nt30++ }
    if ($2 ~ /^fired:/) pat[$2]++ }
  END {
    printf "all:     scored=%d not-typed=%d eligible=%d fired=%d rate=%.2f%%\n", n, nt, n - nt, f, 100 * f / (n - nt)
    printf "30-day:  scored=%d not-typed=%d eligible=%d fired=%d rate=%.2f%%\n", n30, nt30, n30 - nt30, f30, (n30 - nt30) ? 100 * f30 / (n30 - nt30) : 0
    for (k in pat) printf "  %-26s %d\n", k, pat[k]
    print "30-day fires:"
    for (i = 1; i <= f30; i++) print "  " ex[i]
  }' "$T"
rm -f "$T"
