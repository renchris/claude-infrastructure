#!/bin/bash
# lr-move-worker.sh <batch> <sid> — move ONE session to its batch's target account, in its own pane,
# with no model turn (design-swap-v3 §4.3, 2026-10-04). Started detached by lr-move-batch.sh, one
# per session; nothing here waits on another session's worker.
#
# States (each appends {stage,t_ms} to <batch>/<sid>.events.jsonl):
#   W0 claim     the per-session claim the batch took is re-stamped to THIS process; not ours ⇒ stop
#   W1 fence     lr_recon_may_act: the reconciler, or anything holding the launch lock, wins
#   W2 wait      only `wait:*` rows: until the batch's shared census says `move` twice in a row
#   W2c load     wait while load/core is above handoff-fire's recycle bound — no slot held (R7)
#   W3 slot      the swap slot (lr-move-lib.sh), then the kernel-safety read — both BEFORE /exit
#   W5 actuate   lr-handoff --in-place --voluntary --operator-intent --no-prompt --no-replace;
#                a clean HELD:unreachable (admit withdrawn, nothing confirmed) is re-driven (R6)
#   W6 prove     lr_move_verdict until it is terminal; the slot is released at the first proof
#   W8 result    <batch>/<sid>.json written atomically; the claim and the launch lock released
#
# WHAT THIS REPLACES. The drain typed a prompt into each subject asking it to move itself: one
# global lock, a 10 s gap, a full model turn per subject (376K input-equivalent tokens at the
# median, paid even when the move was then refused), and a verdict parsed from the reply. Here the
# subject is never typed at except by the recycle's own /exit, and the verdict is read from disk.
#
# NOTHING REFUSES AFTER /exit: the actuator runs with LR_ADMIT_MODE=swap (no token, no in-pane
# gate), and every hold this worker can raise (claim, fence, idle wait, slot, kernel read, abort)
# happens before lr-handoff is started. lr-handoff's own holds (probe, last read, dialog) all leave
# the session alive in its pane and exit 6.
#
# Draft carry (W2d, 2026-10-18): a `draft` row waits until its box sits unchanged, clears junk, has
# the recycle carry real text unsent into the successor; a pasted block keeps HELD:draft.
# LR_MOVE_CARRY_DRAFT=off holds them all.
# Kill switch LR_MOVE_LANE=off: the worker writes NOTMOVED and touches nothing.
set -uo pipefail

BATCH="${1:?usage: lr-move-worker.sh <batch> <sid>}"; SID="${2:?usage: lr-move-worker.sh <batch> <sid>}"
LR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$LR/lr-lib.sh"
# shellcheck source=/dev/null
. "$LR/lr-move-lib.sh"
# shellcheck source=/dev/null
[ -f "$LR/lr-intent.sh" ] && . "$LR/lr-intent.sh"
# shellcheck source=/dev/null
[ -f "$LR/lr-recon-fence.sh" ] && . "$LR/lr-recon-fence.sh"
for _mw_ca in "$LR/../lib/capacity-admit.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/capacity-admit.sh"; do
  # shellcheck source=/dev/null
  [ -f "$_mw_ca" ] && { . "$_mw_ca"; break; }
done

STATE="$(lr_move_state)"; BDIR="$(lr_move_dir "$BATCH")"; CLAIMS="$STATE/runs/by-sid"
PLAN="$BDIR/plan.json"; RESULT="$BDIR/$SID.json"
HANDOFF="${LR_MOVE_HANDOFF_BIN:-$LR/lr-handoff.sh}"

row() { jq -r --arg s "$SID" --arg k "$1" '.rows[] | select(.sid == $s) | .[$k] // empty' "$PLAN" 2>/dev/null; }
PANE="$(row pane)"; FROM="$(jq -r '.from // empty' "$PLAN" 2>/dev/null)"; TO="$(jq -r '.to // empty' "$PLAN" 2>/dev/null)"
SRC_CFG="$(row config_dir)"; TO_CFG="$(jq -r '.to_config_dir // empty' "$PLAN" 2>/dev/null)"
CWD="$(row cwd)"; DISP="$(row disposition)"; UNTIL="$(jq -r '.until_idle_s // 0' "$PLAN" 2>/dev/null)"; ACCT="$(row account)"
WIDTH="$(jq -r '.slots // empty' "$PLAN" 2>/dev/null)"; : "${WIDTH:=${LR_MOVE_SLOTS:-4}}"
# The driven rows ahead of this one in the plan (act move or wait, plan order): W3 yields to them.
AHEAD="$(jq -r --arg s "$SID" '[.rows[] | select(.act == "move" or .act == "wait") | .sid] | .[0:(index($s) // 0)][]' "$PLAN" 2>/dev/null | tr '\n' ' ')"
REC="move-$BATCH-${SID:0:8}"

ev() { lr_move_event "$BDIR" "$SID" "$@"; }
T0="$(date +%s)"
finish() { # $1=verdict $2=reason [$3=verdict flags]  → the result file, then every release; exits
  local tmp="$RESULT.$$.tmp"
  jq -nc --arg sid "$SID" --arg pane "$PANE" --arg v "$1" --arg r "$2" --arg f "${3:-}" --arg from "$FROM" --arg to "$TO" \
        --arg batch "$BATCH" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson wall "$(( $(date +%s) - T0 ))" \
        '{sid:$sid, pane:$pane, verdict:$v, reason:$r, conjuncts:$f, from:$from, to:$to, batch:$batch, ts:$ts, wall_s:$wall}' \
        > "$tmp" 2>/dev/null && mv -f "$tmp" "$RESULT" 2>/dev/null
  # The claim and the fence go the moment the verdict exists: nothing below touches the pane, and
  # lr_move_summary_late can spin on summary.lock and mail (33 s under load, 2026-10-18), which held
  # the sid claimed after its move was decided (docs/plans/LIMIT_RECOVER_SELF_INPLACE.md § W1).
  lr_claim_release "$CLAIMS" "$SID" "$$"
  command -v lr_recon_act_done >/dev/null 2>&1 && lr_recon_act_done
  ev "result" "$1: $2"
  # A verdict that lands after the batch closed rewrites its summary, and mails a casualty or the
  # settled batch (lr_move_summary_late; 9f6593c5's STRANDED, 2026-10-17, reached no summary).
  lr_move_summary_late "$BDIR" "$BATCH"
  lr_swap_slot_release
  rm -f "$BDIR/$SID.waiting" "$BDIR/$SID.slotwait" 2>/dev/null || true
  case "$1" in MOVED|MOVED-NEW-PANE|MOVED-UNREGISTERED) exit 0 ;; NOTMOVED) exit 3 ;; *) exit 1 ;; esac
}
trap 'lr_swap_slot_release; rm -f "$BDIR/$SID.slotwait" 2>/dev/null' EXIT

ev spawned "pid $$"
[ -s "$PLAN" ] && [ -n "$PANE" ] && [ -n "$SRC_CFG" ] && [ -n "$TO_CFG" ] && [ -n "$TO" ] \
  || finish NOTMOVED "plan-unreadable: $PLAN names no pane, source or target for this session; nothing touched"
[ "${LR_MOVE_LANE:-on}" != off ] || finish NOTMOVED "LR_MOVE_LANE=off; nothing touched"

# W0. The claim the batch runner took for this sid must now name THIS process.
# The runner re-stamps it right after the spawn that returned this pid, so the first reads can be
# early: wait a bounded moment for the stamp before calling the claim lost.
_w0=0
until [ "$(lr_claim_holder_pid "$CLAIMS/$SID.active" 2>/dev/null || true)" = "$$" ]; do
  _w0=$((_w0 + 1))
  [ "$_w0" -lt "${LR_MOVE_CLAIM_WAIT_N:-30}" ] \
    || finish NOTMOVED "claim-lost: the per-session claim does not name this worker; nothing touched"
  sleep 0.5
done
ev claimed

# The operator's intent, re-checked at every hold rather than first at W5. lr-handoff refuses an
# intent that has lapsed, but only once it runs, which is after the claim, the idle wait and the
# slot: batch 69593's four rows held ALL 4 swap slots for 107-116 s, each then refused as
# intent-invalid (expired 902-904 s before), while three valid rows of another batch sat in
# slot-wait. The same call lr-handoff makes, so the worker and the actuator cannot disagree.
# Read once at the claim and once right before the actuator, always; the idle-wait and slot polls
# re-read it at most every LR_MOVE_INTENT_RECHECK_S (default 30 s). An intent expires minutes out
# and one read is ~12 forks, so a read on every poll is pure fork cost on a box whose load ran
# ~270-390 while this was built (2026-10-18).
_mw_intent_at=0
intent_ok() { # → 0 while the intent still admits this move (LR_INTENT_WHY says why not)
  _mw_intent_at=$SECONDS
  command -v lr_intent_check >/dev/null 2>&1 \
    || { LR_INTENT_WHY="unavailable: lr-intent.sh is not beside the worker, so no intent can be checked"; return 1; }
  lr_intent_check "$BDIR/intent/$SID.json" "$SID" "$PANE" "$ACCT" "$TO"
}
intent_stop() { finish NOTMOVED "intent-invalid: $LR_INTENT_WHY (re-checked by the worker before the move); nothing touched"; }
intent_recheck() { # the polls' re-read, once LR_MOVE_INTENT_RECHECK_S have passed since the last one
  local every="${LR_MOVE_INTENT_RECHECK_S:-30}"
  case "$every" in ''|*[!0-9]*) every=30 ;; esac
  [ $(( SECONDS - _mw_intent_at )) -ge "$every" ] || return 0
  intent_ok || intent_stop
}
intent_ok || intent_stop

# W1. The fence. A reconciler that owns the sid, or a live launch-lock holder, wins.
if command -v lr_recon_may_act >/dev/null 2>&1; then
  lr_recon_may_act "$SID" cc-lr-move >"$BDIR/$SID.fence.log" 2>&1 \
    || finish NOTMOVED "reconciler-owns: the fence deferred ($(tail -1 "$BDIR/$SID.fence.log" 2>/dev/null)); nothing touched"
  export LR_LAUNCH_LOCK="${LR_LAUNCH_LOCK:-}"
fi
ev fenced
aborted() { [ -e "$BDIR/abort" ]; }

# W2. A row that was busy at plan time waits for the batch runner's shared census (one census for
# every waiting worker, never one each: a census is ~7 CPU-seconds) to call it `move` on two
# consecutive snapshots. A sid ABSENT from two consecutive snapshots has left the source's census —
# moved elsewhere or ended — and no later snapshot will call it `move`: on 2026-10-18 such rows
# waited out 9-28 min of budget as "not move yet" (lr-inplace-immediacy raw/E R1). Two, not one,
# like `move`. The batch writes snap.tsv only from a census that exited 0, so absence is a read, not
# a failed census. Kill switch: LR_MOVE_WAIT_GONE=off waits out the budget as before.
case "$DISP" in
  wait:*)
    : > "$BDIR/$SID.waiting"
    ev waiting "$DISP, budget ${UNTIL}s"
    deadline=$(( T0 + UNTIL )); calm=0; absent=0; last_ts=""; d=""
    while :; do
      aborted && finish NOTMOVED "aborted while waiting for idle; nothing touched"
      intent_recheck
      ts="$(sed -n '1p' "$BDIR/snap.ts" 2>/dev/null || true)"
      if [ -n "$ts" ] && [ "$ts" != "$last_ts" ] && [ -f "$BDIR/snap.tsv" ]; then
        last_ts="$ts"
        d="$(awk -F'\t' -v s="$SID" '$2 == s && !f { print $7; f = 1 } END { if (!f) print "-absent-" }' "$BDIR/snap.tsv" 2>/dev/null)"
        if [ "$d" = -absent- ]; then absent=$((absent + 1)); d=""; else absent=0; fi
        [ "$absent" -lt 2 ] || [ "${LR_MOVE_WAIT_GONE:-on}" = off ] \
          || finish NOTMOVED "gone: the session left the census on two consecutive snapshots (moved elsewhere or ended); nothing touched"
        if [ "$d" = move ]; then calm=$((calm + 1)); else calm=0; fi
        [ "$calm" -lt 2 ] || break
      fi
      [ "$(date +%s)" -lt "$deadline" ] || finish NOTMOVED "still-busy:${d:-unread} after ${UNTIL}s; nothing touched"
      sleep "${LR_MOVE_WAIT_POLL_S:-5}"
    done
    rm -f "$BDIR/$SID.waiting" 2>/dev/null || true ;;
esac

# W2b. A session whose last record is now a limit error owes a turn, and this lane types none: it
# would come up on the target at rest, still unanswered, and be reported MOVED. The plan-time hold
# (bin/cc-lr, hold:limited) reads the transcript once, when the plan is written; a row that waited
# for idle, or queued for a slot, can have hit its limit since. The census the wait loop reads does
# not look (an api-error tail is "at rest"), so the same read is made here and again once the slot
# is held.
limited_now() { # → 0 when the session's last assistant record is a limit error
  local tx
  for tx in "$SRC_CFG"/projects/*/"$SID".jsonl; do [ -f "$tx" ] && break; tx=""; done
  [ -n "$tx" ] && [ "$(lr_last_api_error "$tx" 2>/dev/null | cut -f3 || true)" = limit ]
}
limited_stop() { finish NOTMOVED "became-limited: its last record is now a limit error, so it owes a turn this lane does not type; nothing touched. Recover it: cc-lr recover ${SID:0:8}"; }
limited_now && limited_stop

# W2d. A DRAFT IS CARRIED, NEVER HELD FOR BEING THERE (operator request 2026-10-18). The plan gives a
# composer-occupied row disposition `draft` (bin/cc-lr) where it used to hold it forever, while
# `cc-lr switch` and the transplanted recycle already carried drafts. Here, before any slot is held:
# a [Pasted text #N] block cannot be carried (its content lives only in the session's memory, so a
# clear destroys it: cc_carry_save rc 3) and keeps HELD:draft; real text is handed to the recycle's
# own carry (handoff-fire hf_rcy_carry: save text + image bytes, clear with read-back, the watcher
# retypes it UNSENT in the successor), which lr-handoff's precheck lets through on LRH_CARRY_DRAFT=1.
# Only a `draft` row is read: no other row touches the terminal from here. Kill switch
# LR_MOVE_CARRY_DRAFT=off (also in the plan): the precheck holds HELD:draft as before.
DRAFT_CARRY="" DRAFT_TEXT=""
MW_TUI_LIB="${LR_MOVE_TUI_LIB:-$LR/../lib/cc-tui.sh}"
mw_composer() { # → the box, space-stripped (cc_tui_composer's form); rc 1 unreadable
  local sock
  [ -f "$MW_TUI_LIB" ] || return 1
  sock="$(jq -r '.kitty_listen_on // empty' "${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$PANE.json" 2>/dev/null || true)"
  # shellcheck source=/dev/null
  ( [ -z "$sock" ] || export CC_TERM_KITTY_TO="$sock"; . "$MW_TUI_LIB" >/dev/null 2>&1 && cc_tui_composer "$PANE" )
}
MW_INTENT_LIB="${LR_MOVE_INTENT_LIB:-$LR/../lib/composer-intent.sh}"
# STALE, NOT JUST PRESENT. A box that changed within LR_MOVE_DRAFT_STALE_S (default 120 s) may be
# someone typing, so the row waits here, holding no slot, and re-reads every LR_MOVE_DRAFT_POLL_S.
# Nothing records when a box last changed, so the first read starts the clock (<sid>.draft under
# the batch dir), and any change restarts it. The operator's HID idle time (lr_hid_idle_s) at or
# past the same bound proves no keystroke reached ANY pane, so the box is stale at once: most
# moved drafts sat for hours on a rejected account. A box still changing at LR_MOVE_DRAFT_WAIT_S
# (default the batch's --until-idle, at least 600 s) is HELD:draft.
# Stale junk (composer-intent.sh's classes: rail prompts, tokens, terminal replies, a stray
# keystroke) is cleared with read-back (cc_tui_clear) and logged (composer_discard_note), then the
# row moves with no carry.
draft_gate() { # → returns with DRAFT_CARRY set (or not); finishes HELD:draft for a pasted block
  local c prev="" seen=0 now hid said="" stale wait deadline cls crc
  stale="${LR_MOVE_DRAFT_STALE_S:-120}"; case "$stale" in ''|*[!0-9]*) stale=120 ;; esac
  wait="${LR_MOVE_DRAFT_WAIT_S:-$(( ${UNTIL:-0} > 600 ? ${UNTIL:-0} : 600 ))}"; case "$wait" in ''|*[!0-9]*) wait=600 ;; esac
  deadline=$(( $(date +%s) + wait ))
  while :; do
    c="$(mw_composer)" || { ev draft "the box could not be read; the recycle's probe decides"; return 0; }
    [ -n "$c" ] || { ev draft "the box is empty now; a plain move"; return 0; }
    now="$(date +%s)"
    if [ "$c" != "$prev" ]; then
      prev="$c"; seen="$now"
      printf '%s\t%s\n' "$seen" "$c" > "$BDIR/$SID.draft" 2>/dev/null || true
    fi
    [ $(( now - seen )) -lt "$stale" ] || break
    hid="$(lr_hid_idle_s 2>/dev/null || echo unreadable)"
    case "$hid" in ''|*[!0-9]*) ;; *) [ "$hid" -lt "$stale" ] || break ;; esac
    [ -n "$said" ] || { said=1; ev draft-wait "its box changed within ${stale}s (input idle ${hid}s); waiting until it sits unchanged that long, up to ${wait}s"; }
    aborted && finish NOTMOVED "aborted while its draft was still changing; nothing touched"
    intent_recheck
    [ "$now" -lt "$deadline" ] \
      || finish NOTMOVED "HELD:draft — its box was still changing after ${wait}s, so someone is typing in it; nothing touched"
    sleep "${LR_MOVE_DRAFT_POLL_S:-10}"
  done
  # shellcheck source=/dev/null
  if [ -f "$MW_INTENT_LIB" ] && cls="$( . "$MW_INTENT_LIB" && composer_unintended_class "$c")"; then
    crc=0
    # shellcheck source=/dev/null
    ( . "$MW_TUI_LIB" >/dev/null 2>&1 && cc_tui_clear "$PANE" ) >/dev/null 2>&1 || crc=$?
    [ "$crc" -eq 0 ] \
      || finish NOTMOVED "HELD:draft — its box holds stale $cls text that could not be cleared (cc_tui_clear rc $crc); nothing else touched"
    # shellcheck source=/dev/null
    ( . "$MW_INTENT_LIB" && composer_discard_note "$PANE" "$cls" "$c" )
    ev draft-discarded "stale $cls (${#c} chars) cleared with read-back; a plain move"
    return 0
  fi
  case "$c" in
    *'[Pastedtext#'[0-9]*)
      finish NOTMOVED "HELD:draft — its box holds a pasted block ([Pasted text #N]) whose content lives only in the session's memory, so clearing it would destroy it; nothing touched" ;;
  esac
  DRAFT_CARRY=1 DRAFT_TEXT="$c"
  ev draft-carry "${#c} chars; the recycle saves and clears it and retypes it unsent in the successor"
}
if [ "$DISP" = draft ] && [ "${LR_MOVE_CARRY_DRAFT:-on}" != off ]; then draft_gate; fi

# W2c. THE LOAD PRECHECK (R7, docs/plans/LIMIT_RECOVER_SELF_INPLACE.md § W0). handoff-fire holds
# every resume recycle, which a move always is, when load per core is above its bound (the F1 guard:
# /exit typed at ~45 runnable per core stranded pane 44, 2026-10-09). That hold sits AFTER
# lr-handoff's admit and handoff-fire's confirm, so on a loaded box every move paid admit + confirm
# + unconfirm, left a locks/<sid>.unconfirmed-* dir and failed anyway. The same test is made here,
# before the slot and before anything is touched; the bound itself is handoff-fire's, unchanged.
# These two copies MUST stay in step with scripts/handoff-fire.sh's hf_load_per_core and
# hf_recycle_load_bound (same seam HF_LOAD_PER_CORE, same knobs, same "unreadable ⇒ proceed").
# LR_MOVE_LOAD_PRECHECK=off restores the old behaviour (actuate and let handoff-fire hold).
mw_load_per_core() { # → 1-min load average / logical cpus, 2 decimals; "" if unreadable · seam HF_LOAD_PER_CORE
  if [ -n "${HF_LOAD_PER_CORE+set}" ]; then printf '%s' "$HF_LOAD_PER_CORE"; return 0; fi
  local la nc
  la="$(/usr/sbin/sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}' || true)"
  nc="$(/usr/sbin/sysctl -n hw.ncpu 2>/dev/null || true)"
  awk -v l="$la" -v n="$nc" 'BEGIN { if (l == "" || n + 0 <= 0) exit; printf "%.2f", l / n }'
}
mw_load_bound() { # → the per-core bound; nothing when the hold is off
  [ "${CC_FIRE_CAPACITY_GATE:-on}" != off ] || return 0
  awk -v b="${HF_RECYCLE_HOLD_LOAD_PER_CORE:-${CC_GATE_MAX_LOAD_PER_CORE:-8}}" 'BEGIN {
    if (b == "off") exit
    if (b ~ /^[0-9]+(\.[0-9]+)?$/) { if (b + 0 > 0) printf "%s", b; exit }
    printf "8" }'
}
LOAD_LPC=""; LOAD_BOUND=""
load_over() { # → 0 when load per core is above the recycle bound (LOAD_LPC, LOAD_BOUND set)
  [ "${LR_MOVE_LOAD_PRECHECK:-on}" != off ] || return 1
  LOAD_BOUND="$(mw_load_bound)"; [ -n "$LOAD_BOUND" ] || return 1
  LOAD_LPC="$(mw_load_per_core || true)"
  awk -v l="$LOAD_LPC" -v b="$LOAD_BOUND" 'BEGIN { exit !(l + 0 > b + 0) }'
}
LOAD_WAIT_S="${LR_MOVE_LOAD_WAIT_S:-$(( ${UNTIL:-0} > 600 ? ${UNTIL:-0} : 600 ))}"
load_t0="$(date +%s)"; load_deadline=$(( load_t0 + LOAD_WAIT_S )); load_said=""
load_wait() { # returns once the load is under the bound; past the deadline finishes HELD:load
  while load_over; do
    aborted && finish NOTMOVED "aborted while waiting for the load to fall; nothing touched"
    intent_recheck
    [ -n "$load_said" ] || { load_said=1; ev load-wait "load ${LOAD_LPC}/core above the ${LOAD_BOUND}/core recycle bound; waiting up to ${LOAD_WAIT_S}s"; }
    [ "$(date +%s)" -lt "$load_deadline" ] \
      || finish NOTMOVED "HELD:load — load ${LOAD_LPC}/core stayed above the ${LOAD_BOUND}/core recycle bound for $(( $(date +%s) - load_t0 ))s; nothing touched (no admit, no copy)"
    sleep "${LR_MOVE_LOAD_POLL_S:-15}"
  done
}

# The load wait, then W3 (slot + kernel read), then one more load read right before the actuator:
# a load that rose while this worker queued sends it back to waiting WITHOUT the slot, within the
# same deadline, so no slot is held while waiting.
while :; do
load_wait

# W3. The slot, then the kernel-safety read, both while the session is still alive in its pane.
# The width is a fixed count (terminal control streams and overlapping boots), not a memory
# reading, and its timeout says so: `slot-wait:`, never the `capacity:` of the memory read below.
#
# THE ORDER WITHIN A BATCH. The plan lists its rows in the operator's priority (highest-activity
# first), and the batch keeps that order for claims and spawns, but the slot was a free-for-all
# poll: after a release, whichever waiter's tick reached `mkdir` first took it, so the order was
# lost at the last step (docs/research/lr-inplace-immediacy-2026-10-18 G §4(b); the admit lock's
# release order is the same race, measured there with two rows losing both releases and running
# out). So each waiter here leaves <sid>.slotwait holding its pid, and a row yields while rows
# ahead of it in the plan are waiting too, unless enough slots are free for all of them and it as
# well (yielding then would only add a poll tick to every row behind). Only rows in W3 compete: a
# row still waiting for idle holds nothing, and a marker whose worker is dead is ignored.
slot_yield() { # → 0 when this row must leave the free slots to the rows ahead of it (_mw_ahead names the first)
  local s p n=0 free=0 i=1 w="$WIDTH" root
  _mw_ahead=""
  for s in $AHEAD; do
    p="$(cat "$BDIR/$s.slotwait" 2>/dev/null || true)"
    case "$p" in ''|*[!0-9]*) continue ;; esac
    kill -0 "$p" 2>/dev/null || continue
    n=$((n + 1)); [ -n "$_mw_ahead" ] || _mw_ahead="$s"
  done
  [ "$n" -gt 0 ] || return 1
  case "$w" in ''|*[!0-9]*) w=4 ;; esac
  root="$(lr_swap_slot_dir)"
  while [ "$i" -le "$w" ]; do
    lr_pidlock_live "$root/slot-$i" || free=$((free + 1))
    i=$((i + 1))
  done
  [ "$n" -ge "$free" ]
}
slot_try() { # → 0 with a slot held (LR_SWAP_SLOT); 1 while none is free or a row ahead has the first call on it
  if slot_yield; then
    [ -n "${_mw_yielded:-}" ] || { _mw_yielded=1; ev slot-yield "behind ${_mw_ahead:0:8}, ahead of this row in the plan and waiting too"; }
    return 1
  fi
  lr_swap_slot_acquire "$WIDTH"
}
printf '%s\n' "$$" > "$BDIR/$SID.slotwait"
ev slot-wait "width $WIDTH"
slot_deadline=$(( $(date +%s) + ${LR_MOVE_SLOT_WAIT_S:-600} ))
until slot_try; do
  aborted && finish NOTMOVED "aborted while waiting for a slot; nothing touched"
  intent_recheck
  [ "$(date +%s)" -lt "$slot_deadline" ] || finish NOTMOVED "slot-wait: no move slot freed in ${LR_MOVE_SLOT_WAIT_S:-600}s (width $WIDTH, a fixed count, not a memory limit)${_mw_yielded:+, and it yielded the free ones to rows ahead of it in the plan}; nothing touched. Run it again once the lane has drained"
  sleep "${LR_MOVE_SLOT_POLL_S:-2}"
done
rm -f "$BDIR/$SID.slotwait" 2>/dev/null || true
ev slot "${LR_SWAP_SLOT##*/}"
limited_now && limited_stop
if [ "${LR_MOVE_KERNEL_CHECK:-on}" != off ] && command -v lr_capacity_probe_corrected >/dev/null 2>&1; then
  # The swap read: segments under the 90% swap ceiling and headroom over the floor. The active and
  # load terms do not apply to a move that owes no turn, and the operator reserve does not apply to
  # a move the operator asked for.
  if ! CC_ADMIT_ACTIVE_TERM=off CC_ADMIT_LOAD_TERM=off CC_ADMIT_RESERVE_TERM=off lr_capacity_probe_corrected lr-move-worker "swap of ${SID:0:8} onto $TO" >"$BDIR/$SID.capacity.log" 2>&1; then
    finish NOTMOVED "capacity: $(cc_capacity_admit_reason 2>/dev/null | cut -c1-200); nothing touched"
  fi
fi
aborted && finish NOTMOVED "aborted before the move; nothing touched"
intent_ok || intent_stop
load_over || break
lr_swap_slot_release
ev load-recheck "load ${LOAD_LPC}/core rose above the ${LOAD_BOUND}/core bound while queued; slot released, waiting again"
done

# W5. The actuator: the reconciler's idle-move argv with the operator's intent in place of an
# account fact, and its environment with three differences (placer, swap admission, bgwork answer).
#
# R6 (docs/plans/LIMIT_RECOVER_SELF_INPLACE.md § W0): a CLEAN HELD:unreachable — kitty's control
# socket did not answer (load ~290, 2026-10-18), and lr-handoff's `lr-transplant --phase abort rc 0`
# withdrew the admit before any confirm — left the source untouched and said "a retry is safe", but
# the worker finished NOTMOVED after one attempt; the only retry left was a mail to the subject,
# which put two actuators on one session. The worker now re-drives exactly that case itself, with
# the claim and slot still held, at most LR_MOVE_UNREACHABLE_RETRIES (default 2) more times.
# Every other hold (busy, draft, load, wedged, anything after a confirm) is final as before.
# LR_MOVE_UNREACHABLE_RETRIES=0 restores the old behaviour (one attempt).
SOCK="$(jq -r '.kitty_listen_on // empty' "${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$PANE.json" 2>/dev/null || true)"
# A carried draft (W2d) is read once more with the slot held: a box that changed while this row
# queued is somebody typing, and it is never moved mid-typing. The recycle's carry re-checks the same
# thing at its own save (hf_rcy_carry: saved ≠ held ⇒ refuse). The three variables: the precheck's
# pass (LRH_CARRY_DRAFT), no 180 s draft wait at the recycle's composer gate for a box already read
# stale (CC_RECYCLE_DRAFT_WAIT=0), and the stale vouch that lifts the carry's focus refusal
# (HF_RCY_CARRY_STALE).
if [ -n "$DRAFT_CARRY" ]; then
  _mw_now="$(mw_composer)" || _mw_now=""
  [ "$_mw_now" = "$DRAFT_TEXT" ] \
    || finish NOTMOVED "HELD:draft — its box changed after it was read for the carry, so someone may be typing; nothing touched"
fi
attempt=1
while :; do
  HLOG="$BDIR/$SID.handoff.log"; [ "$attempt" -eq 1 ] || HLOG="$BDIR/$SID.handoff.$attempt.log"
  if [ "$attempt" -eq 1 ]; then ev actuate; else ev actuate "attempt $attempt"; fi
  hrc=0
  env LR_RECORD_ID="$REC" LR_ATTEMPT="$attempt" HF_RECYCLE_ATTEMPT="$REC:$attempt" \
      HF_WATCHER_RECORD="$BDIR/$SID.watcher.json" \
      CC_RECYCLE_BGWORK_ANSWER="${LR_MOVE_BGWORK_ANSWER:-stop-if-watcher}" \
      LR_WAKE_GUARD_S=30 LR_INPLACE_AWAIT=0 LR_PLACED_BY=cc-lr-move LR_ASSIGN_ID="$BATCH" \
      CLAUDE_CODE_DISABLE_AGENT_VIEW=1 HF_ENGAGE_BY_PROCESS=1 LR_ADMIT_MODE=swap LR_SEGMENT_PCT=90 \
      ${LR_MOVE_PRESEEDED:+LR_PRESEED_DONE=1} ${SOCK:+CC_TERM_KITTY_TO="$SOCK"} \
      ${DRAFT_CARRY:+LRH_CARRY_DRAFT=1 CC_RECYCLE_DRAFT_WAIT=0 HF_RCY_CARRY_STALE=1} \
      /bin/bash "$HANDOFF" --sid "$SID" --config-dir "$SRC_CFG" --cwd "$CWD" --target "$TO" --launch --in-place \
        --source-pane "$PANE" --record-id "$REC" --attempt "$attempt" \
        --voluntary --operator-intent "$BDIR/intent/$SID.json" --no-prompt --no-replace \
        >"$HLOG" 2>&1 || hrc=$?
  ev actuated "rc $hrc"
  held="$(sed -n 's/.*\(HELD:[A-Za-z:-]*\).*/\1/p; s/.*\(REFUSED:[A-Za-z:-]*\).*/\1/p' "$HLOG" 2>/dev/null | tail -1)"
  if [ "$hrc" -ne 6 ] || [ "$held" != HELD:unreachable ] \
     || ! grep -qE 'lr-transplant --phase abort rc 0([^0-9]|$)' "$HLOG" 2>/dev/null; then break; fi
  [ $(( attempt - 1 )) -lt "${LR_MOVE_UNREACHABLE_RETRIES:-2}" ] || { ev retry-exhausted "$attempt attempt(s), each HELD:unreachable"; break; }
  sleep "${LR_MOVE_UNREACHABLE_BACKOFF_S:-45}"
  # The retry re-reads what the first attempt's holds read: the abort file, the limit tail, the claim.
  aborted && finish NOTMOVED "aborted before retrying a clean HELD:unreachable (attempt $attempt, the admit withdrawn); nothing touched"
  limited_now && limited_stop
  [ "$(lr_claim_holder_pid "$CLAIMS/$SID.active" 2>/dev/null || true)" = "$$" ] \
    || finish NOTMOVED "claim-lost: the per-session claim no longer names this worker after a clean HELD:unreachable (attempt $attempt); nothing touched"
  attempt=$((attempt + 1))
  ev retry "attempt $attempt after HELD:unreachable"
done

# W6. Prove it. A hold (rc 6) is read once: the source must be untouched. Anything else is polled,
# because the relaunch is still booting when lr-handoff returns (LR_INPLACE_AWAIT=0).
bound="${LR_MOVE_PROVE_S:-300}"; [ "$hrc" -eq 6 ] && bound="${LR_MOVE_HELD_PROVE_S:-20}"
watcher_hold() { # → "HELD:<reason>" when this attempt's watcher row held after the confirm and unconfirmed, else empty
  tail -n 2000 "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null | jq -R -r --arg a "$REC:$attempt" '
    fromjson? | select(.attempt == $a and ((.class // "") | startswith("recycle-held-"))
      and ((.detail // "") | test("unconfirm rc 0($|;)")) and (((.detail // "") | contains("unconfirm=needed")) | not))
    | .class | sub("^recycle-held-"; "") | if . == "bgwork" then "HELD:bg-work" else "HELD:" + . end' 2>/dev/null | tail -1
}
deadline=$(( $(date +%s) + bound )); stable_pid=""; stable_at=0; v="" why="" vpid="" flags=""
while :; do
  IFS=$'\t' read -r v why vpid flags <<EOF
$(lr_move_verdict "$SID" "$PANE" "$SRC_CFG" "$TO_CFG" "$BDIR")
EOF
  case "$v" in
    MOVED|MOVED-NEW-PANE|MOVED-UNREGISTERED)
      # The first proof read frees the slot for the next worker; the verdict is final only once the
      # same process has been read twice, 5 s apart (a relaunch that dies at boot fails this).
      lr_swap_slot_release
      now="$(date +%s)"
      if [ "$vpid" != "$stable_pid" ]; then stable_pid="$vpid"; stable_at="$now"; ev proof-first "$v pid $vpid"
      elif [ $(( now - stable_at )) -ge "${LR_MOVE_STABLE_S:-5}" ]; then finish "$v" "$why" "$flags"
      fi ;;
    NOTMOVED)
      [ "$hrc" -eq 0 ] || finish NOTMOVED "${held:-HELD:unknown} — $why (lr-handoff rc $hrc)" "$flags"
      # rc 0 is lr-handoff not awaiting the engagement (LR_INPLACE_AWAIT=0): its detached watcher may
      # since have held at a dialog AFTER the confirm and handed the source back (handoff-fire
      # rcy_bgwork_unconfirm: `unconfirm rc 0` in its row). That is a named hold, not a bound to wait out.
      wh="$(watcher_hold)"
      [ -z "$wh" ] || finish NOTMOVED "$wh — the recycle's watcher held after the confirm and handed the source back; $why" "$flags" ;;
  esac
  [ "$(date +%s)" -lt "$deadline" ] || break
  sleep "${LR_MOVE_PROVE_POLL_S:-2}"
done
case "$v" in
  NOTMOVED) finish NOTMOVED "the recycle returned rc $hrc and the session is still on the source: $why" "$flags" ;;
  STRANDED) finish STRANDED "$why; lr-handoff rc $hrc, log $HLOG" "$flags" ;;
  *)        finish FAILED "${why:-no verdict} after ${bound}s; lr-handoff rc $hrc${held:+, $held}, log $HLOG" "$flags" ;;
esac
