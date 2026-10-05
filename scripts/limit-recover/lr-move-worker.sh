#!/bin/bash
# lr-move-worker.sh <batch> <sid> — move ONE session to its batch's target account, in its own pane,
# with no model turn (design-swap-v3 §4.3, 2026-10-04). Started detached by lr-move-batch.sh, one
# per session; nothing here waits on another session's worker.
#
# States (each appends {stage,t_ms} to <batch>/<sid>.events.jsonl):
#   W0 claim     the per-session claim the batch took is re-stamped to THIS process; not ours ⇒ stop
#   W1 fence     lr_recon_may_act: the reconciler, or anything holding the launch lock, wins
#   W2 wait      only `wait:*` rows: until the batch's shared census says `move` twice in a row
#   W3 slot      the swap slot (lr-move-lib.sh), then the kernel-safety read — both BEFORE /exit
#   W5 actuate   lr-handoff --in-place --voluntary --operator-intent --no-prompt --no-replace
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
# Draft carry (W4/W7) is not built: a pane with a draft is held by the plan and by the probe.
# Kill switch LR_MOVE_LANE=off: the worker writes NOTMOVED and touches nothing.
set -uo pipefail

BATCH="${1:?usage: lr-move-worker.sh <batch> <sid>}"; SID="${2:?usage: lr-move-worker.sh <batch> <sid>}"
LR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$LR/lr-lib.sh"
# shellcheck source=/dev/null
. "$LR/lr-move-lib.sh"
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
CWD="$(row cwd)"; DISP="$(row disposition)"; UNTIL="$(jq -r '.until_idle_s // 0' "$PLAN" 2>/dev/null)"
WIDTH="$(jq -r '.slots // empty' "$PLAN" 2>/dev/null)"; : "${WIDTH:=${LR_MOVE_SLOTS:-4}}"
REC="move-$BATCH-${SID:0:8}"

ev() { lr_move_event "$BDIR" "$SID" "$@"; }
T0="$(date +%s)"
finish() { # $1=verdict $2=reason [$3=verdict flags]  → the result file, then every release; exits
  local tmp="$RESULT.$$.tmp"
  jq -nc --arg sid "$SID" --arg pane "$PANE" --arg v "$1" --arg r "$2" --arg f "${3:-}" --arg from "$FROM" --arg to "$TO" \
        --arg batch "$BATCH" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson wall "$(( $(date +%s) - T0 ))" \
        '{sid:$sid, pane:$pane, verdict:$v, reason:$r, conjuncts:$f, from:$from, to:$to, batch:$batch, ts:$ts, wall_s:$wall}' \
        > "$tmp" 2>/dev/null && mv -f "$tmp" "$RESULT" 2>/dev/null
  ev "result" "$1: $2"
  lr_swap_slot_release
  rm -f "$BDIR/$SID.waiting" 2>/dev/null || true
  lr_claim_release "$CLAIMS" "$SID" "$$"
  command -v lr_recon_act_done >/dev/null 2>&1 && lr_recon_act_done
  case "$1" in MOVED|MOVED-NEW-PANE|MOVED-UNREGISTERED) exit 0 ;; NOTMOVED) exit 3 ;; *) exit 1 ;; esac
}
trap 'lr_swap_slot_release' EXIT

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
# consecutive snapshots.
case "$DISP" in
  wait:*)
    : > "$BDIR/$SID.waiting"
    ev waiting "$DISP, budget ${UNTIL}s"
    deadline=$(( T0 + UNTIL )); calm=0; last_ts=""; d=""
    while :; do
      aborted && finish NOTMOVED "aborted while waiting for idle; nothing touched"
      ts="$(sed -n '1p' "$BDIR/snap.ts" 2>/dev/null || true)"
      if [ -n "$ts" ] && [ "$ts" != "$last_ts" ]; then
        last_ts="$ts"
        d="$(awk -F'\t' -v s="$SID" '$2 == s { print $7 }' "$BDIR/snap.tsv" 2>/dev/null | sed -n '1p')"
        if [ "$d" = move ]; then calm=$((calm + 1)); else calm=0; fi
        [ "$calm" -lt 2 ] || break
      fi
      [ "$(date +%s)" -lt "$deadline" ] || finish NOTMOVED "still-busy:${d:-unread} after ${UNTIL}s; nothing touched"
      sleep "${LR_MOVE_WAIT_POLL_S:-5}"
    done
    rm -f "$BDIR/$SID.waiting" 2>/dev/null || true ;;
esac

# W3. The slot, then the kernel-safety read, both while the session is still alive in its pane.
ev slot-wait "width $WIDTH"
slot_deadline=$(( $(date +%s) + ${LR_MOVE_SLOT_WAIT_S:-600} ))
until lr_swap_slot_acquire "$WIDTH"; do
  aborted && finish NOTMOVED "aborted while waiting for a slot; nothing touched"
  [ "$(date +%s)" -lt "$slot_deadline" ] || finish NOTMOVED "capacity: no swap slot freed in ${LR_MOVE_SLOT_WAIT_S:-600}s (width $WIDTH); nothing touched"
  sleep "${LR_MOVE_SLOT_POLL_S:-2}"
done
ev slot "${LR_SWAP_SLOT##*/}"
if [ "${LR_MOVE_KERNEL_CHECK:-on}" != off ] && command -v lr_capacity_probe_corrected >/dev/null 2>&1; then
  # The swap read: segments under the 90% swap ceiling and headroom over the floor. The active and
  # load terms do not apply to a move that owes no turn, and the operator reserve does not apply to
  # a move the operator asked for.
  if ! CC_ADMIT_ACTIVE_TERM=off CC_ADMIT_LOAD_TERM=off CC_ADMIT_RESERVE_TERM=off lr_capacity_probe_corrected lr-move-worker "swap of ${SID:0:8} onto $TO" >"$BDIR/$SID.capacity.log" 2>&1; then
    finish NOTMOVED "capacity: $(cc_capacity_admit_reason 2>/dev/null | cut -c1-200); nothing touched"
  fi
fi
aborted && finish NOTMOVED "aborted before the move; nothing touched"

# W5. The actuator: the reconciler's idle-move argv with the operator's intent in place of an
# account fact, and its environment with three differences (placer, swap admission, bgwork answer).
ev actuate
SOCK="$(jq -r '.kitty_listen_on // empty' "${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$PANE.json" 2>/dev/null || true)"
hrc=0
env LR_RECORD_ID="$REC" LR_ATTEMPT=1 HF_RECYCLE_ATTEMPT="$REC:1" \
    HF_WATCHER_RECORD="$BDIR/$SID.watcher.json" \
    CC_RECYCLE_BGWORK_ANSWER="${LR_MOVE_BGWORK_ANSWER:-stop-if-watcher}" \
    LR_WAKE_GUARD_S=30 LR_INPLACE_AWAIT=0 LR_PLACED_BY=cc-lr-move LR_ASSIGN_ID="$BATCH" \
    CLAUDE_CODE_DISABLE_AGENT_VIEW=1 HF_ENGAGE_BY_PROCESS=1 LR_ADMIT_MODE=swap LR_SEGMENT_PCT=90 \
    ${LR_MOVE_PRESEEDED:+LR_PRESEED_DONE=1} ${SOCK:+CC_TERM_KITTY_TO="$SOCK"} \
    /bin/bash "$HANDOFF" --sid "$SID" --config-dir "$SRC_CFG" --cwd "$CWD" --target "$TO" --launch --in-place \
      --source-pane "$PANE" --record-id "$REC" --attempt 1 \
      --voluntary --operator-intent "$BDIR/intent/$SID.json" --no-prompt --no-replace \
      >"$BDIR/$SID.handoff.log" 2>&1 || hrc=$?
ev actuated "rc $hrc"
held="$(sed -n 's/.*\(HELD:[A-Za-z:-]*\).*/\1/p; s/.*\(REFUSED:[A-Za-z:-]*\).*/\1/p' "$BDIR/$SID.handoff.log" 2>/dev/null | tail -1)"

# W6. Prove it. A hold (rc 6) is read once: the source must be untouched. Anything else is polled,
# because the relaunch is still booting when lr-handoff returns (LR_INPLACE_AWAIT=0).
bound="${LR_MOVE_PROVE_S:-300}"; [ "$hrc" -eq 6 ] && bound="${LR_MOVE_HELD_PROVE_S:-20}"
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
      [ "$hrc" -eq 0 ] || finish NOTMOVED "${held:-HELD:unknown} — $why (lr-handoff rc $hrc)" "$flags" ;;
  esac
  [ "$(date +%s)" -lt "$deadline" ] || break
  sleep "${LR_MOVE_PROVE_POLL_S:-2}"
done
case "$v" in
  NOTMOVED) finish NOTMOVED "the recycle returned rc $hrc and the session is still on the source: $why" "$flags" ;;
  STRANDED) finish STRANDED "$why; lr-handoff rc $hrc, log $BDIR/$SID.handoff.log" "$flags" ;;
  *)        finish FAILED "${why:-no verdict} after ${bound}s; lr-handoff rc $hrc${held:+, $held}, log $BDIR/$SID.handoff.log" "$flags" ;;
esac
