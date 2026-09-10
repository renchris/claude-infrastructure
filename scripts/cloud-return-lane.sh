#!/bin/bash
# cloud-return-lane.sh — the cloud lane's OWN tick: RETURN (land what has come back from the cloud
# VMs), RETIRE (settle what never will), then ANSWER (route what is asking a question at the one
# thing that can answer it), each under a bound sized to ITS unit, journaled.
#
#   scripts/cloud-return-lane.sh            one tick: return pass, then retire pass, then exit
#   scripts/cloud-return-lane.sh --status   print the lane lock's holder / age and exit
#
# ── WHY THE LAND LEFT THE SWEEP TICK (2026-09-06, docs/plans/CLOUD_BACKLOG_PIPELINE.md §A9) ─────
# The cloud lane FIRED reliably and HARVESTED almost never: 682 declarations, 309 holding a pushed
# sha uncollected for 1-19 days, 37 backlog items closed by the lane in 26 days. The collector was a
# block INSIDE scripts/autonomy-sweep.sh, bounded at 900 s (720 s of budget) because "a longer bound
# makes it a worse neighbour" to the sweep's other blocks — and the unit it must complete is a full
# `ship-land` gate, which on this box costs 700-3,900 s (land.log, cloud branches since 09-01:
# 36 of 40 attempted lands exit 143 = CUT by that bound at gate_s 441-715; the 4 that completed ran
# 974-3,856 s). One completed land priced at 3,873 s then made every pass read
# `fits_bound=false — no tick can ever start it` for the price's 6 h shelf life (57 land-deferred
# rows on 09-06 alone, 0 refused, 1 returned). Meanwhile the sweep WAITED on this pass, so its whole
# tick took ~60 min and every other block — pages, alarms, custody, config parity — ran hourly, and
# cc-reaper TERMed the sweep as `orphan-bash` at ≥600 s (36-61 kills/day, 08-25→09-03).
#
# Every prior fix tuned the harvester INSIDE that budget (bound 240→900 · reorder-first · --limit +
# cursor · inventory scoping · cost pacing · cut-floor cap). None changed the budget's relation to
# the unit, and the code named the remedy and declined it: "move the land off the sweep tick".
# This file is that move. The sweep now SPAWNS this script detached and records the spawn; this
# script owns the bound, sized to the unit (CC_LANE_RETURN_BOUND_S, default 5,400 s = the worst
# completed land ×1.4), runs for as long as one land takes, and journals what it did.
#
# ── THE CONTRACT ─────────────────────────────────────────────────────────────────────────────────
#   · SINGLE-FLIGHT. A lane lock (mkdir, pid, TTL) makes a second spawn exit 4 immediately; the
#     return pass keeps its own lock underneath, so nothing here weakens it.
#   · DETACHED, WHITELISTED. The sweep spawns this in a NEW SESSION (perl POSIX::setsid) so launchd
#     does not kill it with the sweep's process group, and cc-reaper's orphan-bash arm exempts any
#     argv naming `cloud-return` (bin/cc-reaper, the `wl` list) — this file's name is chosen to
#     match it. Its children are not orphan-checked at all (parent ≠ 1).
#   · JOURNALED BY THE PARTY THAT KNOWS. The sweep can only say "spawned"; this script writes the
#     `cloud-return` and `cloud-retire` rows (tool: cloud-return-lane) with rc, elapsed and load —
#     the same field names the sweep's rows carried, so every existing reader keeps working.
#   · THE KILLER CLEANS UP. A return pass SIGKILLed by its bound runs no EXIT trap, so its
#     single-flight lock is reaped HERE on 137/143, exactly as the sweep used to.
#   · NO DEPLOYED-COPY GUARD OF ITS OWN. The sweep's exact-path discriminator decides whether the
#     lane is spawned at all (a verifier-worktree or suite copy of the sweep never spawns it); this
#     file resolves its siblings from its OWN directory, so a copied tree with stubs beside it runs
#     the stubs — which is what tests/autonomy-sweep.bats relies on.
#
# Env seams: CC_LANE_RETURN_BOUND_S (5400) · CC_LANE_RETIRE_BOUND_S (900) · CC_LANE_ANSWER_BOUND_S
#   (300) · CC_LANE_ANSWER (1; 0 disables the answer pass) · CC_LANE_RETURN_LIMIT (25)
#   · CC_LANE_RETIRE_MAX (200) · CC_LANE_REPO (else CC_SWEEP_PRUNE_REPO, else the shared checkout) ·
#   CC_CLOUD_STATE · CC_IDL · CC_LANE_TIMEOUT_BIN · CC_LANE_NOW (epoch override, tests)
# Exits: 0 ran · 4 another lane holds the lock · 3 jq missing · 2 usage
set -uo pipefail

_self="${BASH_SOURCE[0]:-$0}"
while [ -L "$_self" ]; do
  _d="$(cd "$(dirname "$_self")" && pwd)"; _self="$(readlink "$_self")"
  case "$_self" in /*) ;; *) _self="$_d/$_self" ;; esac
done
DIR="$(cd "$(dirname "$_self")" && pwd)"
RETURN_SH="$DIR/cloud-return.sh"
RETIRE_SH="$DIR/cloud-retire-terminal.sh"
ANSWER_PY="$DIR/cloud-answer.py"

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; CFG="${CFG%/}"
STATE="${CC_CLOUD_STATE:-$CFG/autonomy/cloud}"
IDL="${CC_IDL:-$CFG/autonomy/idl.jsonl}"
REPO="${CC_LANE_REPO:-${CC_SWEEP_PRUNE_REPO:-$HOME/Development/claude-infrastructure}}"
RETURN_BOUND="${CC_LANE_RETURN_BOUND_S:-5400}"; case "$RETURN_BOUND" in ''|*[!0-9]*) RETURN_BOUND=5400 ;; esac
RETIRE_BOUND="${CC_LANE_RETIRE_BOUND_S:-900}";  case "$RETIRE_BOUND" in ''|*[!0-9]*) RETIRE_BOUND=900 ;; esac
RETURN_LIMIT="${CC_LANE_RETURN_LIMIT:-25}";     case "$RETURN_LIMIT" in ''|*[!0-9]*) RETURN_LIMIT=25 ;; esac
RETIRE_MAX="${CC_LANE_RETIRE_MAX:-200}";        case "$RETIRE_MAX" in ''|*[!0-9]*) RETIRE_MAX=200 ;; esac
ANSWER_BOUND="${CC_LANE_ANSWER_BOUND_S:-300}";  case "$ANSWER_BOUND" in ''|*[!0-9]*) ANSWER_BOUND=300 ;; esac
ANSWER_ON="${CC_LANE_ANSWER:-1}"
TMO="${CC_LANE_TIMEOUT_BIN:-$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)}"
LOCK="$STATE/.lane.lock"
# The lock outlives one whole tick and no more: a holder past both bounds plus the grace is dead.
LOCK_TTL=$(( RETURN_BOUND + RETIRE_BOUND + 120 ))

now() { if [ -n "${CC_LANE_NOW:-}" ]; then printf '%s' "$CC_LANE_NOW"; else date +%s; fi; }
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
say() { printf '%s %s\n' "$(now_iso)" "$*"; }
# /usr/sbin/sysctl by absolute path: the first live tick ran under a PATH without /usr/sbin and
# journalled load1=null for a pass that ran 4,103 s — the unattended-path class, met on day one.
load1() { local l; l="$(/usr/sbin/sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')"; case "$l" in ''|*[!0-9.]*) l="" ;; esac; printf '%s' "$l"; }

command -v jq >/dev/null 2>&1 || { echo "cloud-return-lane: jq required" >&2; exit 3; }

case "${1:-}" in
  -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
  --status)
    if [ -d "$LOCK" ]; then
      printf 'lane lock HELD by pid %s since %s (%ss ago, ttl %ss)\n' "$(head -1 "$LOCK/pid" 2>/dev/null)" \
        "$(head -1 "$LOCK/at" 2>/dev/null)" "$(( $(now) - $(head -1 "$LOCK/at" 2>/dev/null || echo 0) ))" "$LOCK_TTL"
    else printf 'lane lock FREE\n'; fi
    exit 0 ;;
  '') ;;
  *) echo "cloud-return-lane: unknown arg $1" >&2; exit 2 ;;
esac

# Every row this lane writes carries the same key the sweep's rows carried for the same fact, plus
# `tool: cloud-return-lane` so a reader can tell WHO observed it. jq-encoded end to end: a value
# with a quote or a newline can never produce a malformed line (one malformed line aborts every
# `jq -rs` slurp of the journal).
log_idl() { # <disposition> <jq-built object>
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  jq -cn --arg ts "$(now_iso)" --arg disp "$1" --argjson extra "${2:-{\}}" \
    '{ts:$ts, tool:"cloud-return-lane", disposition:$disp} + $extra' >>"$IDL" 2>/dev/null || true
}

lock_acquire() {
  mkdir -p "$STATE" 2>/dev/null || return 1
  if mkdir "$LOCK" 2>/dev/null; then printf '%s\n' "$$" >"$LOCK/pid"; printf '%s\n' "$(now)" >"$LOCK/at"; return 0; fi
  local pid at age why=""
  pid="$(head -1 "$LOCK/pid" 2>/dev/null)"; case "$pid" in ''|*[!0-9]*) pid="" ;; esac
  at="$(head -1 "$LOCK/at" 2>/dev/null)";   case "$at"  in ''|*[!0-9]*) at=0 ;; esac
  age=$(( $(now) - at ))
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then why="holder pid $pid is gone"
  elif [ "$at" -gt 0 ] && [ "$age" -lt "$LOCK_TTL" ]; then return 1
  else why="held ${age}s, past the ${LOCK_TTL}s window"; fi
  say "reaping the lane lock: $why"
  rm -rf "$LOCK" 2>/dev/null; mkdir "$LOCK" 2>/dev/null || return 1
  printf '%s\n' "$$" >"$LOCK/pid"; printf '%s\n' "$(now)" >"$LOCK/at"
  return 0
}
# shellcheck disable=SC2329  # invoked through the EXIT/INT/TERM trap below
lock_release() { [ "$(head -1 "$LOCK/pid" 2>/dev/null)" = "$$" ] && rm -rf "$LOCK" 2>/dev/null; return 0; }

# A contended tick still JOURNALS. Measured on the first live day: the sweep spawned the lane at
# 06:37Z and 07:03Z while a hand-run tick held the lock, both exited 4 here, and neither left a row
# anywhere — the sweep writes nothing for a lane that finished inside its grace, so a lock-held tick
# read exactly like a tick that never happened (memory: alarm-must-key-on-the-store-not-the-sensor).
if ! lock_acquire; then
  say "another lane tick holds $LOCK — exiting 4 (single-flight by design)"
  log_idl cloud-return "$(jq -cn --arg h "$(head -1 "$LOCK/pid" 2>/dev/null)" \
    '{cloud_return_rc:"4", elapsed_s:null, load1:null, holder_pid:($h|tonumber? // null), note:"another lane tick holds the lane lock — single-flight; nothing ran, the holder journals its own rows"}')"
  exit 4
fi
trap 'lock_release' EXIT INT TERM

# ── 1. RETURN: land what has come back ─────────────────────────────────────────────────────────
# The child is TOLD the bound (CC_RETURN_BOUND_S) so its own deadline pacing and lock TTL derive
# from the same number that will kill it — one fact, one place.
rc="skipped"; took=""; note=""
if [ -x "$RETURN_SH" ]; then
  t0="$(date +%s)"
  if [ -n "$TMO" ] && [ -x "$TMO" ]; then
    CC_RETURN_BOUND_S="$RETURN_BOUND" "$TMO" -k 10 "$RETURN_BOUND" bash "$RETURN_SH" --sweep --limit "$RETURN_LIMIT"
  else
    bash "$RETURN_SH" --sweep --limit "$RETURN_LIMIT"
  fi
  rc=$?
  took=$(( $(date +%s) - t0 ))
  case "$rc" in
    137|143) [ -d "$STATE/.return.lock" ] && rm -rf "$STATE/.return.lock" 2>/dev/null; note="cut by the lane bound (${RETURN_BOUND}s); stranded return lock cleared" ;;
    124)     note="cut by the lane bound (${RETURN_BOUND}s) with grace; the next tick resumes" ;;
    4)       note="another return pass held the lock" ;;
    0)       note="pass completed — per-session outcomes in $STATE/return.jsonl" ;;
    *)       note="return pass exited $rc" ;;
  esac
  say "return pass rc=$rc took=${took}s — $note"
fi
# load1 is read AFTER the pass and ONLY if it ran: a not-run pass must journal null for both
# fields, never a number that reads like "ran instantly on an idle box".
l1=""; [ -n "$took" ] && l1="$(load1)"
log_idl cloud-return "$(jq -cn --arg c "$rc" --arg e "$took" --arg l "$l1" --argjson b "$RETURN_BOUND" --arg n "$note" \
  '{cloud_return_rc:$c, elapsed_s:($e|tonumber? // null), load1:($l|tonumber? // null), bound_s:$b, note:$n}')"

# ── 2. RETIRE: settle what will never return ───────────────────────────────────────────────────
# Runs AFTER the return pass on purpose: a branch the return pass just landed is answerable as
# `landed` by the time this reads the head list, so the row is settled one tick earlier.
rrc="skipped"; rtook=""; summary=""
if [ -x "$RETIRE_SH" ]; then
  t0="$(date +%s)"
  out_f="$(mktemp -t cloud-lane-retire.XXXXXX 2>/dev/null || printf '/tmp/cloud-lane-retire.%s' "$$")"
  if [ -n "$TMO" ] && [ -x "$TMO" ]; then
    CLOUD_RETIRE_REPO="$REPO" "$TMO" -k 10 "$RETIRE_BOUND" bash "$RETIRE_SH" --max "$RETIRE_MAX" >"$out_f" 2>&1
  else
    CLOUD_RETIRE_REPO="$REPO" bash "$RETIRE_SH" --max "$RETIRE_MAX" >"$out_f" 2>&1
  fi
  rrc=$?
  rtook=$(( $(date +%s) - t0 ))
  # The pass's one-line census (examined= gone= landed= superseded= conflict= …) is the fact worth
  # keeping; the sweep used to send it to /dev/null, which is how 255 retirements happened with no
  # record of WHY. Anything else it printed goes to this lane's log.
  summary="$(grep -E '^cloud-retire-terminal: examined=' "$out_f" 2>/dev/null | tail -1)"
  sed 's/^/    /' "$out_f" 2>/dev/null
  rm -f "$out_f" 2>/dev/null
  say "retire pass rc=$rrc took=${rtook}s ${summary:+— $summary}"
fi
log_idl cloud-retire "$(jq -cn --arg c "$rrc" --arg e "$rtook" --argjson b "$RETIRE_BOUND" --arg s "$summary" \
  '{cloud_retire_rc:$c, elapsed_s:($e|tonumber? // null), bound_s:$b, summary:$s}')"

# ── 3. ANSWER: route what is still ASKING ───────────────────────────────────────────────────────
# The return pass collects sessions that PUSHED and went quiet. It has nothing to say about a
# session that finished a turn and asked a QUESTION — 222 of 262 live sessions were in exactly that
# state when cloud-inbox was built, and the field had no reader at all. This pass routes each one to
# `cc-backlog needs`, so the operator's own consent rail (`cc-do <id>`, a typed yes) becomes the
# gate. It EXECUTES NOTHING, least of all anything the remote composed — see cloud-answer.py's
# docstring, where that line is the design rather than a caveat.
#
# 🚨 WHY IT IS THIRD, AND WHY THAT IS THE POSITION THAT WORKS. Placing it above the return pass
# would put it behind a bound it cannot survive: ONE land costs 700-3,900 s inside a 5,400 s pass,
# so the return pass is routinely SIGKILLed at the bound (`rc=137`, every tick since 09-04 on this
# box) and anything sequenced under it inside that pass would never run — the inner-bound-starves-
# the-tail shape this lane's own history records. It is a SEPARATE pass, after the retire pass,
# because that position is measured as reachable: the retire pass completes (rc=0, 32-89 s) on the
# very ticks whose return pass was killed, since a killed child ends the command, not the script.
# Its own bound is 300 s — the unit is one `cloud-inbox` sweep, seconds on the live store — and it
# is deliberately far below both siblings so this pass can never become the thing that starves.
arc="skipped"; atook=""; atally=""
if [ "$ANSWER_ON" != "0" ] && [ -f "$ANSWER_PY" ]; then
  t0="$(date +%s)"
  aout_f="$(mktemp -t cloud-lane-answer.XXXXXX 2>/dev/null || printf '/tmp/cloud-lane-answer.%s' "$$")"
  if [ -n "$TMO" ] && [ -x "$TMO" ]; then
    "$TMO" -k 10 "$ANSWER_BOUND" python3 "$ANSWER_PY" >"$aout_f" 2>&1
  else
    python3 "$ANSWER_PY" >"$aout_f" 2>&1
  fi
  arc=$?
  atook=$(( $(date +%s) - t0 ))
  # The one-line tally (`read N active session(s) — COLLECT 2, CLEAR 9`) is the fact worth keeping;
  # the per-row detail — which QUOTES remote-authored text — goes to this lane's log and nowhere a
  # later reader could mistake it for an instruction.
  atally="$(grep -E '^cloud-answer: read ' "$aout_f" 2>/dev/null | tail -1)"
  sed 's/^/    /' "$aout_f" 2>/dev/null
  rm -f "$aout_f" 2>/dev/null
  say "answer pass rc=$arc took=${atook}s ${atally:+— $atally}"
fi
log_idl cloud-answer "$(jq -cn --arg c "$arc" --arg e "$atook" --argjson b "$ANSWER_BOUND" --arg s "$atally" \
  '{cloud_answer_rc:$c, elapsed_s:($e|tonumber? // null), bound_s:$b, tally:$s}')"

exit 0
