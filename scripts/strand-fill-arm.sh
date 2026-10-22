#!/bin/bash
# strand-fill-arm.sh — start work on an account whose weekly limit is falling behind pace, gated
# and capped (weekly-strand post-mortem docs/research/weekly-strand-next-2026-10-18/REPORT.md §4.1).
#
# ── WHY THIS EXISTS ───────────────────────────────────────────────────────────────────────────────
# Week ending 2026-10-18: account `next` left 21 points of its weekly limit unused. Its strand
# forecast showed the shortfall from Oct 12, and nothing turned a forecast into work — no mechanism
# in bin/, scripts/ or hooks/ fills unused quota, and the one arm that creates work
# (drain-revival-arm) never fired. This arm is that mechanism. It is modelled on drain-revival-arm:
# same three modes, same claim-before-act cooldown, one JSON line per decision for the sweep to
# journal.
#
# ── THREE MODES — CC_STRAND_FILL ──────────────────────────────────────────────────────────────────
#   off          the kill switch: nothing is read, nothing is decided.
#   would-fire   DEFAULT. Decides exactly as `on` would — pace, alarm, KMAX, admission, cooldown —
#                and logs every decision, but launches nothing and spends no quota. Turning it on is
#                the operator's decision (the auto-mode classifier refused an agent switching on its
#                own spending, backlog c109e9e850fb).
#   on           launches one fill session pinned to the account:
#                `handoff-fire.sh --prompt-file $CC_STRAND_FILL_PROMPT_FILE --account <acct>`. With no
#                prompt file (the work pool, §4 item 2, is not built yet) it fails closed: `no-work`.
# Any other value FAILS CLOSED: treated as off and reported as `bad-mode`.
#
# ── THE PACE RULE (§4.1) — per account, every tick ────────────────────────────────────────────────
#   horizon  72h, widened to 96h for an account whose weekly reset is within 24h of another's (that
#            week next2, next and next4 reset within 22h of each other).
#   fire iff all three hold, for an account resetting inside its horizon:
#     1. 100 - weekly_pct > (weekly_reset_h - 12) * r          r = CC_STRAND_FILL_RATE_PPH (1.0)
#     2. need = (100 - weekly_pct) / weekly_reset_h  >  1.5 * actual   (actual = the 24h flat pace,
#        burn_wk_flat_ph; the EWMA stands in when it abstains; neither => `pace-unknown`, no fire)
#     3. the full 5h windows needed, (100 - weekly_pct) / 24.5, fit in the windows left, hours / 5
#   r = 1.0 rather than gap-3's 2.5: on that week's rows 2.5 fires on next only at Oct 16 14Z, 38h
#   out; 1.0 fires at Oct 14 16Z, 84h out, which is the 72-96h trigger the report's slot-hour
#   arithmetic favours (220-304 fill slot-hours against 52 for a 36h trigger). A false alarm costs an
#   account reaching 100% a few hours early; a miss costs a week like that one.
#   `on-pace` (no fire) once weekly_pct + actual * hours >= 100: the account is projected to finish.
#
# ── THE GATES, in order, each failing closed (no fire) ────────────────────────────────────────────
#   capacity-alarm ALARM → alarm-held, unless the reset is under 12h away (the pace check already
#   failed) · k >= KMAX → kmax-held · cc_capacity_admit strand-fill refuses → admit-refused (active
#   term only, ceiling 7 = 8 minus the operator's slot whatever presence says; load term off, since
#   load does not slow burn, r = +0.41) · per-account stamp younger than the cooldown → cooldown-held
#   · stamp write failed → claim-failed. The stamp is CLAIMED BEFORE the fire, like drain-revival-arm,
#   and would-fire keeps its own stamps so its log counts what `on` would have launched.
#
# ── OUTPUT ────────────────────────────────────────────────────────────────────────────────────────
# `--tick` prints ONE compact JSON line PER DECISION (one per account, or one tick-level line for
# off / bad-mode / interval-held / no-data) and exits 0; the sweep journals each line. `--help` prints this header.
# Env seams: CC_STRAND_FILL_ACCOUNTS_BIN · CC_STRAND_FILL_FIRE_BIN · CC_STRAND_FILL_STATE_DIR ·
# CC_STRAND_FILL_ALARM_LOG · CC_STRAND_FILL_COOLDOWN_S (1800) · CC_STRAND_FILL_INTERVAL_S (1800) · CC_STRAND_FILL_RATE_PPH (1.0) ·
# CC_STRAND_FILL_KMAX (accounts.json router.KMAX) · CC_STRAND_FILL_PROMPT_FILE ·
# CC_STRAND_FILL_FIRE_TIMEOUT_S · CC_STRAND_FILL_NOW (fixed clock).
set -uo pipefail
# shellcheck disable=SC1091  # #! helpers run via their interpreter, not by path (kalloc leak; plan KALLOC_TRIGGER_ELIMINATION W4)
if [ -f "${BASH_SOURCE[0]%/*}/lib/cc-run.sh" ]; then . "${BASH_SOURCE[0]%/*}/lib/cc-run.sh"; else cc_argv() { CC_ARGV=("$1"); }; fi

case "${1:-}" in
  --tick) ;;
  -h|--help) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
  *) printf 'strand-fill-arm: usage: strand-fill-arm.sh --tick\n' >&2; exit 2 ;;
esac

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# By path, not bare: the sweep runs under launchd's PATH, which does not carry ~/.claude/bin.
ACCOUNTS_BIN="${CC_STRAND_FILL_ACCOUNTS_BIN:-$_here/../bin/claude-accounts}"
[ -x "$ACCOUNTS_BIN" ] || ACCOUNTS_BIN="$HOME/.claude/bin/claude-accounts"
FIRE_BIN="${CC_STRAND_FILL_FIRE_BIN:-$_here/handoff-fire.sh}"
STATE_DIR="${CC_STRAND_FILL_STATE_DIR:-$HOME/.claude/autonomy/strand-fill}"
ALARM_LOG="${CC_STRAND_FILL_ALARM_LOG:-$HOME/.claude/logs/capacity-alarm.jsonl}"
COOLDOWN_S="${CC_STRAND_FILL_COOLDOWN_S:-1800}"
INTERVAL_S="${CC_STRAND_FILL_INTERVAL_S:-1800}"
RATE="${CC_STRAND_FILL_RATE_PPH:-1.0}"
PROMPT_FILE="${CC_STRAND_FILL_PROMPT_FILE:-}"
FIRE_TIMEOUT_S="${CC_STRAND_FILL_FIRE_TIMEOUT_S:-300}"
NOW="${CC_STRAND_FILL_NOW:-$(date +%s)}"
case "$COOLDOWN_S" in ''|*[!0-9]*) COOLDOWN_S=1800 ;; esac
case "$INTERVAL_S" in ''|*[!0-9]*) INTERVAL_S=1800 ;; esac
case "$RATE" in ''|*[!0-9.]*|*.*.*) RATE=1.0 ;; esac
case "$NOW" in ''|*[!0-9]*) NOW="$(date +%s)" ;; esac
KMAX="${CC_STRAND_FILL_KMAX:-}"
[ -n "$KMAX" ] || KMAX="$(jq -r '.router.KMAX // empty' "${CLAUDE_ACCOUNTS_JSON:-$HOME/.claude/accounts.json}" 2>/dev/null)"
case "$KMAX" in ''|*[!0-9]*) KMAX=24 ;; esac

TIMEOUT_BIN=""
for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
          /opt/homebrew/bin/timeout /opt/homebrew/bin/gtimeout /usr/local/bin/timeout; do
  [ -n "$_c" ] && [ -x "$_c" ] && { TIMEOUT_BIN="$_c"; break; }
done
bounded() { # <seconds> <cmd…>
  local s="$1"; shift
  declare -F cc_argv >/dev/null && { cc_argv "$1"; shift; set -- "${CC_ARGV[@]}" "$@"; }   # #! via its interpreter (cc-run.sh)
  if [ -z "$TIMEOUT_BIN" ]; then "$@"; return $?; fi
  "$TIMEOUT_BIN" -k 5 "$s" "$@"
}

mode="${CC_STRAND_FILL:-would-fire}"

emit_tick() { # <decision> [why] — one tick-level line, for decisions taken before any account
  jq -nc --arg mode "$mode" --arg d "$1" --arg why "${2:-}" \
    '{mode:$mode, decision:$d, acct:null, why:(if $why=="" then null else $why end)}'
}

case "$mode" in
  off) emit_tick off; exit 0 ;;
  would-fire|on) ;;
  *) emit_tick bad-mode "CC_STRAND_FILL=$mode"; exit 0 ;;
esac

# THE CADENCE: a full evaluation at most every INTERVAL_S (1800 s ~ drain-revival-arm's measured
# 31 min), so a 300 s sweep journals one `interval-held` line between evaluations rather than one
# line per account per tick. Per mode, like the cooldown stamps. An unwritable stamp only means
# evaluating more often; the per-account cooldown still bounds every fire.
tick_stamp="$STATE_DIR/tick-$mode.stamp"
last_tick="$(cat "$tick_stamp" 2>/dev/null || echo 0)"
case "$last_tick" in ''|*[!0-9]*) last_tick=0 ;; esac
if [ "$last_tick" -gt 0 ] && [ $(( NOW - last_tick )) -lt "$INTERVAL_S" ]; then
  emit_tick interval-held "last evaluation $(( NOW - last_tick ))s ago < ${INTERVAL_S}s"; exit 0
fi
mkdir -p "$STATE_DIR" 2>/dev/null && printf '%s\n' "$NOW" >"$tick_stamp" 2>/dev/null

# Cache-only read: never forces an endpoint sweep from a 5-minute tick (the keep-warm job owns that).
rows_json="$(bounded 60 "$ACCOUNTS_BIN" --json --no-heal --max-wait 0 --max-age 900 2>/dev/null)"
if ! printf '%s' "$rows_json" | jq -e '.rows | type == "array" and length > 0' >/dev/null 2>&1; then
  emit_tick no-data "claude-accounts --json returned no rows"; exit 0
fi

# Capacity alarm: the newest row's verdict, believed only while fresh (10 min). Stale or unreadable
# reads as not-ALARM: the alarm is an advisory hold here, and the admission gate below still binds.
alarm="$(tail -1 "$ALARM_LOG" 2>/dev/null | jq -r --argjson now "$NOW" \
  'select(((.ts // "") | sub("\\.[0-9]+";"") | fromdateiso8601? // 0) >= ($now - 600)) | .verdict // empty' 2>/dev/null)"

# The pace rule, one object per account. Pure arithmetic over the rows; the gates follow in bash.
pace="$(printf '%s' "$rows_json" | jq -c --argjson r "$RATE" '
  def num: type == "number";
  [.rows[] | select(type == "object" and (.weekly_reset_h | num) and (.weekly_pct | num))] as $rows
  | $rows[]
  | . as $x
  | ($x.weekly_reset_h) as $h
  | (100 - $x.weekly_pct) as $rem
  | (if ([$rows[] | select(.acct != $x.acct and (((.weekly_reset_h - $h) | fabs) <= 24))] | length) > 0
     then 96 else 72 end) as $hz
  | (if ($x.burn_wk_flat_ph | num) then $x.burn_wk_flat_ph
     elif ($x.burn_wk_ewma_ph | num) then $x.burn_wk_ewma_ph else null end) as $act
  | {acct: $x.acct, weekly_pct: $x.weekly_pct, reset_h: $h, horizon_h: $hz, actual_pph: $act,
     k: (if ($x.k | num) then $x.k elif ($x.k_native | num) then $x.k_native else null end),
     need_pph: (if $h > 0 then ($rem / $h) else null end),
     windows_need: ($rem / 24.5), windows_left: ($h / 5),
     pace: (if ($x.auth // "ok") != "ok" then "auth-" + ($x.auth | tostring)
            elif $h <= 0 or $h > $hz then "outside-horizon"
            elif $act == null then "pace-unknown"
            elif ($x.weekly_pct + $act * $h) >= 100 then "on-pace"
            elif ($rem > ((if $h > 12 then $h - 12 else 0 end) * $r)) | not then "on-pace"
            elif (($rem / $h) > 1.5 * $act) | not then "on-pace"
            elif ($rem / 24.5) > ($h / 5) then "infeasible"
            else "behind" end)}' 2>/dev/null)"
if [ -z "$pace" ]; then emit_tick no-data "claude-accounts rows carry no weekly_pct / weekly_reset_h"; exit 0; fi

admit_lib="$_here/lib/capacity-admit.sh"
# shellcheck disable=SC1090,SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
[ -f "$admit_lib" ] && . "$admit_lib" 2>/dev/null

decide() { # <pace-object> → prints the decision line
  local p="$1" acct pc reset k decision why="" cmd="" frc="" stamp last
  # Every cell padded at the emitter: tab is IFS-whitespace, so an empty cell would shift the rest.
  IFS=$'\t' read -r acct pc reset k < <(jq -r '
    def cell(ph): (if . == null then "" else . end) | tostring
                  | gsub("[\\t\\r\\n]"; " ") | if . == "" then ph else . end;
    [(.acct | cell("-")), (.pace | cell("-")), (.reset_h | cell("-")), (.k | cell("-"))] | @tsv' <<<"$p")
  [ "$k" = "-" ] && k=""
  out() {
    jq -c --arg mode "$mode" --arg d "$decision" --arg why "$why" --arg cmd "$cmd" --arg frc "$frc" \
      --arg alarm "${alarm:-}" \
      '{mode:$mode, decision:$d} + . + {alarm:(if $alarm=="" then null else $alarm end),
        why:(if $why=="" then null else $why end), cmd:(if $cmd=="" then null else $cmd end),
        fire_rc:(if $frc=="" then null else ($frc|tonumber) end)}' <<<"$p"
  }
  if [ "$pc" != behind ]; then decision="$pc"; out; return; fi
  if [ "${alarm:-}" = ALARM ] && ! awk -v h="$reset" 'BEGIN { exit !(h < 12) }'; then
    decision="alarm-held"; why="capacity-alarm reads ALARM and the reset is 12h or more away"; out; return
  fi
  if [ -n "$k" ] && [ "${k%%.*}" -ge "$KMAX" ] 2>/dev/null; then
    decision="kmax-held"; why="k=$k >= KMAX $KMAX"; out; return
  fi
  if command -v cc_capacity_admit >/dev/null 2>&1; then
    if ! CC_ADMIT_LOAD_TERM=off CC_ADMIT_ACTIVE_CEILING="${CC_STRAND_FILL_ACTIVE_CEILING:-7}" \
         cc_capacity_admit strand-fill "strand-fill $acct" >/dev/null 2>&1; then
      decision="admit-refused"; why="$(cc_capacity_admit_reason 2>/dev/null)"; out; return
    fi
  else
    decision="admit-unavailable"; why="scripts/lib/capacity-admit.sh not loadable"; out; return
  fi
  case "$mode" in on) stamp="$STATE_DIR/fire-$acct.stamp" ;; *) stamp="$STATE_DIR/would-fire-$acct.stamp" ;; esac
  last="$(cat "$stamp" 2>/dev/null || echo 0)"
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  if [ "$last" -gt 0 ] && [ $(( NOW - last )) -lt "$COOLDOWN_S" ]; then
    decision="cooldown-held"; why="last decision $(( NOW - last ))s ago < ${COOLDOWN_S}s"; out; return
  fi
  if [ "$mode" = on ] && { [ -z "$PROMPT_FILE" ] || [ ! -s "$PROMPT_FILE" ]; }; then
    decision="no-work"; why="no fill work: CC_STRAND_FILL_PROMPT_FILE unset or empty (§4 item 2)"; out; return
  fi
  # CLAIM before acting — see the header. A failed claim is a failed gate.
  if ! { mkdir -p "$STATE_DIR" 2>/dev/null && printf '%s\n' "$NOW" >"$stamp.tmp.$$" 2>/dev/null \
         && mv -f "$stamp.tmp.$$" "$stamp" 2>/dev/null; }; then
    decision="claim-failed"; out; return
  fi
  cmd="bash $FIRE_BIN --prompt-file ${PROMPT_FILE:-<fill-pool-brief>} --account $acct"
  [ "$mode" = on ] || { decision="would-fire"; out; return; }
  bounded "$FIRE_TIMEOUT_S" bash "$FIRE_BIN" --prompt-file "$PROMPT_FILE" --account "$acct" >/dev/null 2>&1
  frc=$?
  decision="fired"; out
}

while IFS= read -r p; do
  [ -n "$p" ] && decide "$p"
done <<<"$pace"
exit 0
