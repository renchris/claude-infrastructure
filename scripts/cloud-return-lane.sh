#!/bin/bash
# cloud-return-lane.sh — the cloud lane's OWN tick: RETURN (land what has come back from the cloud
# VMs), then RETIRE (settle what never will), each under a bound sized to ITS unit, journaled.
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
# Env seams: CC_LANE_RETURN_BOUND_S (5400) · CC_LANE_RETIRE_BOUND_S (900) · CC_LANE_RETURN_LIMIT (25)
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

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; CFG="${CFG%/}"
STATE="${CC_CLOUD_STATE:-$CFG/autonomy/cloud}"
IDL="${CC_IDL:-$CFG/autonomy/idl.jsonl}"
REPO="${CC_LANE_REPO:-${CC_SWEEP_PRUNE_REPO:-$HOME/Development/claude-infrastructure}}"
RETURN_BOUND="${CC_LANE_RETURN_BOUND_S:-5400}"; case "$RETURN_BOUND" in ''|*[!0-9]*) RETURN_BOUND=5400 ;; esac
RETIRE_BOUND="${CC_LANE_RETIRE_BOUND_S:-900}";  case "$RETIRE_BOUND" in ''|*[!0-9]*) RETIRE_BOUND=900 ;; esac
RETURN_LIMIT="${CC_LANE_RETURN_LIMIT:-25}";     case "$RETURN_LIMIT" in ''|*[!0-9]*) RETURN_LIMIT=25 ;; esac
RETIRE_MAX="${CC_LANE_RETIRE_MAX:-200}";        case "$RETIRE_MAX" in ''|*[!0-9]*) RETIRE_MAX=200 ;; esac
TMO="${CC_LANE_TIMEOUT_BIN:-$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)}"
LOCK="$STATE/.lane.lock"
# The lock outlives one whole tick and no more: a holder past both bounds plus the grace is dead.
LOCK_TTL=$(( RETURN_BOUND + RETIRE_BOUND + 120 ))

now() { if [ -n "${CC_LANE_NOW:-}" ]; then printf '%s' "$CC_LANE_NOW"; else date +%s; fi; }
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
say() { printf '%s %s\n' "$(now_iso)" "$*"; }
load1() { local l; l="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')"; case "$l" in ''|*[!0-9.]*) l="" ;; esac; printf '%s' "$l"; }

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

lock_acquire || { say "another lane tick holds $LOCK — exiting 4 (single-flight by design)"; exit 4; }
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
# THE CENSUS IS THE DISPOSITION, AND A STRING CANNOT BE SUMMED (2026-09-07, DRAIN_CIRCUIT).
# `summary` keeps the pass's own words and no reader can do arithmetic on them, so the one question
# the pile cap cannot answer stays unanswerable: a pile that drained because the work LANDED and a
# pile that drained because the work was DISCARDED move `pending_total` by exactly the same amount.
# Measured on the first deployed pass (CLOUD_BACKLOG_PIPELINE §A9.5): `examined=331 landed=8
# superseded=142 conflict=126 gone=23 kept=32 retired=299` — the cap opened on 299 retirements of
# which 8 were lands, and 337 branches carrying 492 patch-id-novel commits stayed on origin
# untouched (nothing retires a branch, only a declaration). That is §1.5's defect in a new costume:
# the unit counts pile SIZE, not pile DISPOSITION. Typed fields turn a regex scrape into a sum.
#
# Parsed as a CLASS (every `key=<int>` token), never as an enumeration of the strata we know today —
# this repo's own `denylist-enumerates-spellings-not-the-class` lesson, which cost it the cc-reaper
# whitelist twice. A stratum added to cloud-retire-terminal.sh appears here with no edit.
# ABSENT IS null, NEVER 0, and here that is the load-bearing direction: a retire pass CUT by its
# bound prints no census, and a zeroed census would read as "ran, settled nothing" — the exact
# non-verdict-read-as-verdict this lane was built to stop.
census="null"
if [ -n "$summary" ]; then
  census="$(printf '%s' "$summary" | jq -Rc '
    split(" ")
    | map(select(test("^[A-Za-z][A-Za-z0-9_-]*=[0-9]+$")) | split("=") | {(.[0]): (.[1]|tonumber)})
    | add // null' 2>/dev/null)" || census="null"
  case "$census" in ''|'{}') census="null" ;; esac
fi
# Same rule as the return row above: load1 only if the pass actually ran. Without it the elapsed is
# unstratifiable, which is precisely what §3h had to retrofit onto the return row after the fact.
rl1=""; [ -n "$rtook" ] && rl1="$(load1)"
log_idl cloud-retire "$(jq -cn --arg c "$rrc" --arg e "$rtook" --arg l "$rl1" --argjson b "$RETIRE_BOUND" --arg s "$summary" --argjson cen "$census" \
  '{cloud_retire_rc:$c, elapsed_s:($e|tonumber? // null), load1:($l|tonumber? // null), bound_s:$b, summary:$s, census:$cen}')"

exit 0
