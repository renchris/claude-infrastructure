#!/usr/bin/env bash
# pane-census.sh — the standing pane census (husk-history-2026-10-24/FIX-DESIGN.md §4 W3, D15).
#
# WHY. "Husks are fixed" was declared five times from a field proof on one pane (census §6 item 7).
# This is the metric of record instead: every drainer tick it lists kitty once (READ-ONLY: `ls`,
# never a close, focus or send) and classifies every FLEET pane still listed, one JSONL row per tick
# to ~/.claude/logs/pane-census.jsonl. Done = `metric` max 0 for 7 consecutive days (§6 item 5):
#   jq -s '[.[] | select(.readable and .ts >= "<since>") | .metric] | max' ~/.claude/logs/pane-census.jsonl
#
# Population (D15): panes of THIS kitty process (window ids restart at 1 per kitty) that a fleet
# session registered in (lead-crash-watchdog `registered session=… pane=N`, tty≠none), that were
# fired (cc-fired/<pane>.json) or that cc-pane-runner launched (pane-exit/<pane>.launch). A record
# keyed census alone cannot see lr, reso, boot-resume or layout roots (skeptic break 18).
# Classes, by the pane's foreground and its runner exit record's `tail` (the §2 pane states):
#   running      claude, or any job that is not a shell or the runner, or a runner whose command runs
#   held         the runner holds the pane (`hold:*`); age_s = now − the record's ts (the hold's start)
#   deciding     the runner returned and has not written its tail yet, or is acting on it
#   kept[r]      shells only, `keep:<r>` (r ≠ fallback): kept on purpose, for the reason named
#   unexplained  shells only with any other tail, `keep:fallback`, or no record for a fired or
#                runner-launched pane: a bare shell nobody can account for — THE anomaly
#   operator     shells only and none of the above: an operator-typed session (D2 not ruled)
# metric = unexplained + holds older than CC_PANE_CENSUS_HOLD_MAX_S (6 h). Pages once per
# (kitty pid, pane) for an unexplained pane seen two ticks running, and once for an over-age hold.
#
# usage: pane-census.sh [--dry-run]   --dry-run prints the row and the counts; writes and pages nothing
# Never fatal (rc 0 always), bash 3.2 safe (launchd's /bin/bash), every kitty call bounded.
# Seams: CC_PANE_CENSUS_{LOG,STATE_DIR,KITTY_BIN,SOCKET_BIN,KITTY_START_EPOCH,WATCHDOG_LOG,EXIT_DIR,
#        FIRED_DIR,PAGE_BIN,NOW,TIMEOUT_S,HOLD_MAX_S,MIN_INTERVAL_S}.
set -u
# shellcheck disable=SC1091  # #! helpers run via their interpreter, not by path (kalloc leak)
if [ -f "${BASH_SOURCE[0]%/*}/lib/cc-run.sh" ]; then . "${BASH_SOURCE[0]%/*}/lib/cc-run.sh"; else cc_run() { "$@"; }; fi
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
DRY=0; [ "${1:-}" = --dry-run ] && DRY=1
LOG="${CC_PANE_CENSUS_LOG:-$HOME/.claude/logs/pane-census.jsonl}"
STATE="${CC_PANE_CENSUS_STATE_DIR:-$HOME/.claude/run/pane-census}"
WDLOG="${CC_PANE_CENSUS_WATCHDOG_LOG:-$HOME/.claude/logs/lead-crash-watchdog.log}"
EXITDIR="${CC_PANE_CENSUS_EXIT_DIR:-$HOME/.claude/run/pane-exit}"
FIRED="${CC_PANE_CENSUS_FIRED_DIR:-$HOME/.claude/cc-fired}"
PAGE_BIN="${CC_PANE_CENSUS_PAGE_BIN:-$HERE/../bin/cc-desk-page}"
NOW="${CC_PANE_CENSUS_NOW:-$(date +%s)}"
HOLD_MAX="${CC_PANE_CENSUS_HOLD_MAX_S:-21600}"
TS="$(date -u -r "$NOW" +%FT%TZ 2>/dev/null || date -u +%FT%TZ)"
command -v jq >/dev/null 2>&1 || exit 0
# Every TSV cell this file reads is padded at its emitter: IFS=<tab> is whitespace, so an empty cell
# collapses and the next one shifts left into its place (scripts/tsv-pad-lint.sh).
CELL='def cell(ph): (if . == null then "" else . end) | tostring | gsub("[\\t\\r\\n]"; " ") | if . == "" then ph else . end;'

# One row per tick: the drainer also runs from SessionEnd, and a second row seconds after the first
# would make "two ticks running" mean nothing. The stamp is the last counted tick.
if [ "$DRY" = 0 ]; then
  mkdir -p "$STATE" "$(dirname "$LOG")" 2>/dev/null || exit 0
  _m="$(stat -f %m "$STATE/last" 2>/dev/null || echo 0)"
  [ $(($(date +%s) - _m)) -ge "${CC_PANE_CENSUS_MIN_INTERVAL_S:-120}" ] || exit 0   # the file clock, never the NOW seam
  : > "$STATE/last" 2>/dev/null || exit 0
fi
emit() { # <row json>
  if [ "$DRY" = 1 ]; then printf '%s\n' "$1"; else printf '%s\n' "$1" >> "$LOG" 2>/dev/null; fi
}
unreadable() { # <kitty pid or ""> <why>
  emit "$(jq -nc --arg ts "$TS" --arg k "$1" --arg why "$2" \
    '{ts: $ts, kitty_pid: ($k | tonumber? // null), readable: false, why: $why}')"
  exit 0
}

TO_BIN=""
for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
          /opt/homebrew/bin/timeout /usr/local/bin/timeout /opt/homebrew/bin/gtimeout; do
  [ -n "$_c" ] && [ -x "$_c" ] && { TO_BIN="$_c"; break; }
done
SOCK="$(cc_run "${CC_PANE_CENSUS_SOCKET_BIN:-$HERE/../bin/cc-kitty-socket}" 2>/dev/null)"
KPID="${SOCK##*kitty-}"; KPID="${KPID%%[!0-9]*}"
[ -n "$SOCK" ] && [ -n "$KPID" ] || unreadable "" "no live kitty socket"
KSTART="${CC_PANE_CENSUS_KITTY_START_EPOCH:-}"
if [ -z "$KSTART" ]; then
  _l="$(LC_ALL=C ps -p "$KPID" -o lstart= 2>/dev/null | tr -s ' ' | sed 's/^ //;s/ $//')"
  KSTART="$(LC_ALL=C date -j -f '%a %b %d %T %Y' "$_l" +%s 2>/dev/null)"
fi
case "$KSTART" in ''|*[!0-9]*) unreadable "$KPID" "kitty start time unreadable" ;; esac
KITTY="${CC_PANE_CENSUS_KITTY_BIN:-$(cc_run "$HERE/../bin/cc-kitty-bin" 2>/dev/null || command -v kitty 2>/dev/null)}"
[ -n "$KITTY" ] || unreadable "$KPID" "no kitty binary"
if [ -n "$TO_BIN" ]; then LS="$("$TO_BIN" -k 3 "${CC_PANE_CENSUS_TIMEOUT_S:-10}" "$KITTY" @ --to "$SOCK" ls 2>/dev/null)"
else LS="$("$KITTY" @ --to "$SOCK" ls 2>/dev/null)"; fi
jq -e 'type == "array"' >/dev/null 2>&1 <<<"$LS" || unreadable "$KPID" "kitty @ ls did not answer"

# Registered in this kitty's lifetime: the watchdog writes local time, so compare local strings.
SINCE="$(date -r "$KSTART" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
REG=$'\n'"$(grep -F ' registered session=' "$WDLOG" 2>/dev/null | sed -E 's/ teammate=[^ ]*[[:space:]]*$//' \
  | LC_ALL=C awk -v since="$SINCE" 'substr($0, 2, 19) >= since && !index($0, " tty=none ") {
      p = $NF; if (sub(/^pane=/, "", p) && p ~ /^[0-9]+$/) print p }' | sort -u)"$'\n'
since_kitty() { [ -e "$1" ] && [ "$(stat -f %m "$1" 2>/dev/null || echo 0)" -ge "$KSTART" ]; }
fired_here() { # <pane> → rc 0 iff a fired stamp for it was written in this kitty's lifetime
  local at e
  at="$(jq -r '.firedAt // empty' "$FIRED/$1.json" 2>/dev/null)"; [ -n "$at" ] || return 1
  e="$(TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%SZ' "$at" +%s 2>/dev/null)" && [ "${e:-0}" -ge "$KSTART" ]
}

# One line per window: id, then its foreground — claude | runner | shell | job | none. A shell is a
# shell binary with option words only (`-zsh`, `zsh -i`); `bash some-script` is a job.
LINES=""; WINDOWS=0
while IFS=$'\t' read -r id fg; do
  [ -n "$id" ] || continue; WINDOWS=$((WINDOWS + 1))
  launched=0; since_kitty "$EXITDIR/$id.launch" && launched=1
  case "$REG" in *$'\n'"$id"$'\n'*) ;; *) [ "$launched" = 1 ] || fired_here "$id" || continue ;; esac
  rts=""; tail=""
  IFS=$'\t' read -r rts tail < <(jq -r "$CELL"'[(.ts // 0 | floor | cell("0")), (.tail | cell("-"))] | @tsv' "$EXITDIR/$id.json" 2>/dev/null)
  [ "$tail" = - ] && tail=""
  case "$rts" in ''|*[!0-9]*) rts="" ;; esac
  [ -n "$rts" ] && [ "$rts" -lt "$KSTART" ] && rts=""       # an older kitty's pane of the same id
  cls=running; why="$fg"; age=""
  case "$fg" in
    runner)
      # a record older than this launch is the last occupant's: the runner's own command still runs
      if [ -n "$rts" ] && { [ "$launched" = 0 ] || [ "$rts" -ge "$(stat -f %m "$EXITDIR/$id.launch")" ]; }; then
        case "$tail" in hold:*) cls=held; why="$tail"; age=$((NOW - rts)) ;; *) cls=deciding; why="${tail:-no tail}" ;; esac
      fi ;;
    shell)
      if [ -n "$rts" ]; then
        case "$tail" in
          keep:fallback|keep:) cls=unexplained; why="$tail" ;;
          keep:*) cls="kept[${tail#keep:}]"; why="$tail" ;;
          *) cls=unexplained; why="tail=${tail:-none}" ;;
        esac
      elif [ "$launched" = 1 ] || fired_here "$id"; then cls=unexplained; why="no exit record"
      else cls=operator; why="registered, never fired or runner-launched"; fi ;;
  esac
  LINES="$LINES$id"$'\t'"$cls"$'\t'"$why"$'\t'"$age"$'\n'
done < <(jq -r "$CELL"'def base: (. // "") | sub(".*/"; "");
    .[]?.tabs[]?.windows[]? | [(.id | cell("-")), ((.foreground_processes // []) | map(.cmdline // []) as $c
    | if ($c | length) == 0 then "none"
      elif any($c[]; (.[0] | base) as $b | $b == "claude" or $b == "claude.exe") then "claude"
      elif any($c[]; any(.[0:2][]; base == "cc-pane-runner")) then "runner"
      elif all($c[]; ((.[0] | base) as $b | ["zsh","bash","sh","-zsh","-bash","-sh","login"] | any(. == $b))
                     and all(.[1:][]; startswith("-"))) then "shell"
      else "job" end | cell("none"))] | @tsv' <<<"$LS" 2>/dev/null)

ROW="$(printf '%s' "$LINES" | jq -R -s -c --arg ts "$TS" --argjson k "$KPID" --argjson w "$WINDOWS" --argjson hmax "$HOLD_MAX" '
  [split("\n")[] | select(length > 0) | split("\t") | {pane: (.[0] | tonumber), class: .[1], why: .[2], age_s: (.[3] | tonumber? // null)}] as $r
  | {ts: $ts, kitty_pid: $k, readable: true, windows: $w, population: ($r | length),
     counts: (reduce ("running","held","deciding","kept","unexplained","operator") as $c
               ({}; .[$c] = ([$r[] | select(.class == $c or (.class | startswith($c + "[")))] | length))),
     kept: ([$r[] | select(.class | startswith("kept[")) | .class[5:-1]] | group_by(.) | map({key: .[0], value: length}) | from_entries),
     held: [$r[] | select(.class == "held") | {pane, age_s, tail: .why}],
     unexplained: [$r[] | select(.class == "unexplained") | {pane, why}],
     holds_over_max: ([$r[] | select(.class == "held" and .age_s > $hmax)] | length)}
  | .metric = .counts.unexplained + .holds_over_max')"
[ -n "$ROW" ] || unreadable "$KPID" "census row could not be built"
emit "$ROW"
if [ "$DRY" = 1 ]; then
  jq -r '"windows=\(.windows) population=\(.population) " + (.counts | to_entries | map("\(.key)=\(.value)") | join(" "))
         + " metric=\(.metric)"' <<<"$ROW"; exit 0
fi

# Page once per (kitty pid, pane). A marker from an older kitty names a stranger: dropped.
page() { [ -e "$STATE/$1" ] && return 0; cc_run "$PAGE_BIN" --source pane-census "$2" >/dev/null 2>&1 </dev/null; : > "$STATE/$1"; }
for _f in "$STATE"/paged-*; do case "${_f##*/}" in paged-"$KPID"-*|paged-hold-"$KPID"-*) ;; paged-*) rm -f "$_f" ;; esac; done
PREV="$(cat "$STATE/unexplained" 2>/dev/null)"; CUR=""
while IFS=$'\t' read -r p why; do
  [ -n "$p" ] || continue; CUR="$CUR$KPID-$p"$'\n'
  case $'\n'"$PREV"$'\n' in *$'\n'"$KPID-$p"$'\n'*)
    page "paged-$KPID-$p" "pane-census: pane $p is a bare shell nobody can account for ($why), two ticks running. Inspect: cc-husk-sweep --pane $p" ;;
  esac
done < <(jq -r "$CELL"'.unexplained[] | [(.pane | cell("-")), (.why | cell("-"))] | @tsv' <<<"$ROW")
printf '%s' "$CUR" > "$STATE/unexplained" 2>/dev/null
while IFS=$'\t' read -r p a; do
  [ -n "$p" ] && page "paged-hold-$KPID-$p" "pane-census: pane $p has been held for $((a / 3600)) h (over $((HOLD_MAX / 3600)) h); it closes itself once safe, or ⌘W it"
done < <(jq -r --argjson h "$HOLD_MAX" "$CELL"'.held[] | select(.age_s > $h) | [(.pane | cell("-")), (.age_s | cell("0"))] | @tsv' <<<"$ROW")
exit 0
