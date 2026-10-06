#!/bin/bash
# lr-move-batch.sh <batch> — admit one `cc-lr move` batch ONCE, then start one detached worker per
# session (design-swap-v3 §4.2, 2026-10-04). Started detached by the launchd poller's lrp_move_kick,
# never from a session's own tool call: auto mode refuses an agent keying a live peer pane, and a
# worker started from a tool call dies with it.
#
#   ADMIT (under move-admit.lock, the lane's only global section, seconds long)
#     · the router, read ONCE and failing CLOSED: target ranked ⇒ admit; excluded ⇒ refuse with the
#       router's own words; cannot answer ⇒ refuse `target-unverified` unless the plan carries the
#       operator's --target-unverified. 15 moves acting on "unknown" multiply one mistake by 15,
#       and the old fail-open path admitted an excluded target at 16:41Z on 2026-10-04;
#     · the kernel-safety read (segments under the 90% swap ceiling, headroom over the floor);
#     · one per-session claim each, judged by (pid, lstart); a held claim is that row's NOTMOVED;
#     · the target's folder trust preseeded once per (target, cwd), so 15 workers never contend
#       the 2 s .claude.json lock that silently skips the seed.
#   FAN-OUT   one lr-move-worker.sh per claimed row; the claim is re-stamped to the worker.
#   WATCH     while any worker waits for its session to go idle, ONE census per LR_MOVE_SNAP_S is
#             written to snap.tsv for all of them; a worker that died is given its verdict from disk.
#   CLOSE     two checks that CAN fail (critic 12), then summary.json and at most ONE mail:
#             a fresh router read (did the target stay ranked through the batch's own boots?), and
#             the prompt guard run against every moved session's real transcript (can it take a
#             prompt? this is the check a SWITCHED verdict lacked on 762a6daa).
#
# No swap row gets an admission token and no gate runs after /exit (LR_ADMIT_MODE=swap in the worker).
# Kill switch LR_MOVE_LANE=off: every row is NOTMOVED, nothing is claimed or started.
set -uo pipefail

BATCH="${1:?usage: lr-move-batch.sh <batch>}"
LR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$LR/lr-lib.sh"
# shellcheck source=/dev/null
. "$LR/lr-move-lib.sh"
for _mb_f in "$LR/../lib/capacity-admit.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/capacity-admit.sh"; do
  # shellcheck source=/dev/null
  [ -f "$_mb_f" ] && { . "$_mb_f"; break; }
done
for _mb_f in "$LR/../lib/detach.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/detach.sh" "$HOME/.claude/scripts/lib/detach.sh"; do
  # shellcheck source=/dev/null
  [ -f "$_mb_f" ] && { . "$_mb_f"; break; }
done

STATE="$(lr_move_state)"; BDIR="$(lr_move_dir "$BATCH")"; PLAN="$BDIR/plan.json"; CLAIMS="$STATE/runs/by-sid"
WORKER="${LR_MOVE_WORKER_BIN:-$LR/lr-move-worker.sh}"
UPGRADE="${LR_MOVE_UPGRADE_BIN:-$LR/lr-upgrade.sh}"
AB="${CC_ACCOUNTS_BIN:-$HOME/bin/claude-accounts}"
GUARD="${LR_MOVE_GUARD_BIN:-}"
if [ -z "$GUARD" ]; then
  for _mb_f in "$LR/../../hooks/handed-off-session-guard.sh" "$HOME/.claude/hooks/handed-off-session-guard.sh"; do
    [ -f "$_mb_f" ] && { GUARD="$_mb_f"; break; }
  done
fi
say() { printf '%s lr-move-batch %s: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$BATCH" "$*" >&2; }
T0="$(date +%s)"

[ -s "$PLAN" ] || { say "no plan at $PLAN; nothing to do"; exit 2; }
FROM="$(jq -r '.from // empty' "$PLAN")"; TO="$(jq -r '.to // empty' "$PLAN")"
TO_CFG="$(jq -r '.to_config_dir // empty' "$PLAN")"; UNTIL="$(jq -r '.until_idle_s // 0' "$PLAN")"
BY="$(jq -r '.requested_by // empty' "$PLAN")"; UNVERIFIED_OK="$(jq -r '.target_unverified // false' "$PLAN")"
# The rows this batch drives: sid<TAB>pane<TAB>cwd, for every row whose act is move or wait.
# Padded at the emitter: tab is IFS whitespace, so an empty pane or cwd would shift the next column
# into its place on read.
DRIVE="$(jq -r 'def cell(ph): (if . == null then "" else . end) | tostring | gsub("[\\t\\r\\n]"; " ") | if . == "" then ph else . end;
  .rows[] | select(.act == "move" or .act == "wait") | [(.sid | cell("-")), (.pane | cell("-")), (.cwd | cell("-"))] | @tsv' "$PLAN")"

result() { # $1=sid $2=pane $3=verdict $4=reason — written only when the row has no result yet
  [ -e "$BDIR/$1.json" ] && return 0
  jq -nc --arg sid "$1" --arg pane "$2" --arg v "$3" --arg r "$4" --arg from "$FROM" --arg to "$TO" --arg batch "$BATCH" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{sid:$sid, pane:$pane, verdict:$v, reason:$r, conjuncts:"", from:$from, to:$to, batch:$batch, ts:$ts, wall_s:0}' \
        > "$BDIR/$1.json.$$.tmp" 2>/dev/null && mv -f "$BDIR/$1.json.$$.tmp" "$BDIR/$1.json" 2>/dev/null
}
admit_json() { # $1=admitted true|false $2=target_auth $3=reason
  jq -nc --argjson ok "$1" --arg auth "$2" --arg why "$3" --arg to "$TO" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{admitted:$ok, target:$to, target_auth:$auth, reason:$why, ts:$ts}' > "$BDIR/admit.json.$$.tmp" 2>/dev/null \
    && mv -f "$BDIR/admit.json.$$.tmp" "$BDIR/admit.json" 2>/dev/null
}
summary() { # $1=batch verdict (done|refused) $2=note
  local counts auth_after="${AUTH_AFTER:-unchecked}"
  # LEADING-PAREN PATTERNS, AND THEY ARE LOAD-BEARING: launchd runs this file under /bin/bash 3.2,
  # which ends a `$( )` at the first unbalanced `)` — the one closing a bare `a|b)` pattern. The
  # 2026-10-06 batch (7 of 7 MOVED) logged a syntax error here and mailed "done: no rows".
  counts="$(for f in "$BDIR"/*.json; do
              case "${f##*/}" in (plan.json|admit.json|summary.json|request*.json|*.watcher.json) continue ;; esac
              jq -r '.verdict // empty' "$f" 2>/dev/null
            done | sort | uniq -c | awk '{ printf "%s%s=%s", (NR > 1 ? " " : ""), $2, $1 }')"
  jq -nc --arg b "$BATCH" --arg st "$1" --arg note "$2" --arg c "${counts:-none}" --arg a "$auth_after" \
        --argjson wall "$(( $(date +%s) - T0 ))" --arg from "$FROM" --arg to "$TO" \
        '{batch:$b, status:$st, note:$note, verdicts:$c, target_auth_after:$a, wall_s:$wall, from:$from, to:$to}' \
        > "$BDIR/summary.json.$$.tmp" 2>/dev/null && mv -f "$BDIR/summary.json.$$.tmp" "$BDIR/summary.json" 2>/dev/null
  say "$1: ${counts:-no rows} (target auth after: $auth_after) $2"
  # ONE mail, to the requester only, never to a moved pane (a mailed no-prompt resume takes a turn).
  local notify="${CC_NOTIFY_BIN:-$HOME/.claude/bin/cc-notify}"
  if [ "${CC_LR_MOVE_MAIL:-on}" != off ] && [ -n "$BY" ] && [ "$BY" != "?" ] && [ -x "$notify" ]; then
    "$notify" "$BY" "cc-lr move $BATCH ($FROM -> $TO) $1: ${counts:-no rows}; target auth after the batch: $auth_after. $2 Details: cc-lr move --status $BATCH" >/dev/null 2>&1 || true
  fi
}
refuse() { # $1=reason — the whole batch: every driven row NOTMOVED, nothing claimed or started
  local sid pane cwd
  admit_json false "${2:-unverified}" "$1"
  while IFS=$'\t' read -r sid pane cwd; do
    [ -n "$sid" ] && result "$sid" "$pane" NOTMOVED "batch refused: $1; nothing touched"
  done <<EOF
$DRIVE
EOF
  summary refused "$1"
  exit 2
}

[ "${LR_MOVE_LANE:-on}" != off ] || refuse "LR_MOVE_LANE=off"
[ -n "$DRIVE" ] || { admit_json true ok "no row to move"; summary "done" "the plan held no row to move."; exit 0; }
[ -n "$TO" ] && [ -n "$TO_CFG" ] || refuse "the plan names no target account or config dir"

# ── ADMIT ────────────────────────────────────────────────────────────────────────────────────────
ALOCK="$STATE/locks/move-admit.lock"; mkdir -p "$STATE/locks" "$CLAIMS" 2>/dev/null || true
t=0
until mkdir "$ALOCK" 2>/dev/null; do
  if ! lr_pidlock_live "$ALOCK" && [ -n "$(find "$ALOCK" -maxdepth 0 -mmin +1 2>/dev/null)$(cat "$ALOCK/pid" 2>/dev/null)" ]; then
    say "move-admit lock held by a dead process; taking it"; rm -f "$ALOCK/pid" "$ALOCK/lstart" 2>/dev/null; rmdir "$ALOCK" 2>/dev/null || true
    continue
  fi
  t=$((t + 1)); [ "$t" -lt "${LR_MOVE_ADMIT_WAIT_S:-90}" ] || refuse "another batch held the admit section for ${LR_MOVE_ADMIT_WAIT_S:-90}s"
  sleep 1
done
lr_pidlock_stamp "$ALOCK" "$$" || true
unlock() { if [ "$(cat "$ALOCK/pid" 2>/dev/null || true)" = "$$" ]; then rm -f "$ALOCK/pid" "$ALOCK/lstart" 2>/dev/null; rmdir "$ALOCK" 2>/dev/null || true; fi; }
trap unlock EXIT

# The router. rc 0 ranked · 1 excluded (ROUTE_WHY) · 3 could not answer (ROUTE_WHY).
ROUTE_WHY=""
route_read() { # [$1=--fresh] → as above
  local out rc=0 errf
  [ -x "$AB" ] || { ROUTE_WHY="the router is not executable at $AB"; return 3; }
  errf="$BDIR/router.err"
  out="$("$AB" --rank general ${1:+"$1"} 2>"$errf")" || rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then ROUTE_WHY="the router could not answer (rc $rc)"; return 3; fi
  case $'\n'"$(printf '%s\n' "$out" | awk 'NF { print $1 }')"$'\n' in *$'\n'"$TO"$'\n'*) return 0 ;; esac
  ROUTE_WHY="$(sed -n 's/.*excluded — //p' "$errf" | tr ';' '\n' | sed 's/^ *//' \
               | awk -v t="$TO" 'index($0, t "=") == 1 { print substr($0, length(t) + 2); exit }')"
  case "$ROUTE_WHY" in
    *throttled*|*cached*) ROUTE_WHY="the router has no fresh reading for $TO ($ROUTE_WHY)"; return 3 ;;
  esac
  ROUTE_WHY="${ROUTE_WHY:-not ranked by the router}"; return 1
}
rrc=0; route_read || rrc=$?
if [ "$rrc" -ne 0 ]; then rrc=0; route_read --fresh || rrc=$?; fi
AUTH=ok
case "$rrc" in
  0) ;;
  1) refuse "target-unroutable: $ROUTE_WHY" excluded ;;
  *) if [ "$UNVERIFIED_OK" = true ]; then AUTH=unverified-accepted; say "router unverified ($ROUTE_WHY); proceeding on --target-unverified"
     else refuse "target-unverified: $ROUTE_WHY (pass --target-unverified to move anyway)" unverified; fi ;;
esac
if [ "${LR_MOVE_KERNEL_CHECK:-on}" != off ] && command -v lr_capacity_probe_corrected >/dev/null 2>&1; then
  if ! CC_ADMIT_ACTIVE_TERM=off CC_ADMIT_LOAD_TERM=off CC_ADMIT_RESERVE_TERM=off lr_capacity_probe_corrected lr-move-batch "batch $BATCH onto $TO" >"$BDIR/capacity.log" 2>&1; then
    refuse "capacity: $(cc_capacity_admit_reason 2>/dev/null | cut -c1-240)" "$AUTH"
  fi
fi
admit_json true "$AUTH" "router: ${ROUTE_WHY:-ranked}"

CLAIMED="" seeded=1 cwds=""
while IFS=$'\t' read -r sid pane cwd; do
  [ -n "$sid" ] || continue
  [ -e "$BDIR/$sid.json" ] && continue
  if [ ! -f "$BDIR/intent/$sid.json" ]; then result "$sid" "$pane" NOTMOVED "no operator intent was written for this row; nothing touched"; continue; fi
  if lr_claim_take "$CLAIMS" "$sid" cc-lr-move "$pane" "$$" >/dev/null 2>"$BDIR/$sid.claim.log"; then
    CLAIMED="$CLAIMED$sid"$'\t'"$pane"$'\n'
    case $'\n'"$cwds" in *$'\n'"$cwd"$'\n'*) ;; *) cwds="$cwds$cwd"$'\n' ;; esac
  else
    result "$sid" "$pane" NOTMOVED "claim-held: $(sed -n 's/^lr-claim: //p' "$BDIR/$sid.claim.log" | tail -1 | cut -c1-200); nothing touched"
  fi
done <<EOF
$DRIVE
EOF
if [ "${LR_MOVE_PRESEED:-on}" != off ] && [ -f "$LR/lr-preseed-env.sh" ]; then
  while IFS= read -r cwd; do
    [ -n "$cwd" ] && [ "$cwd" != - ] || continue
    /bin/bash "$LR/lr-preseed-env.sh" "$TO_CFG" "$cwd" >>"$BDIR/preseed.log" 2>&1 || seeded=0
  done <<EOF
$cwds
EOF
else
  seeded=0
fi
unlock; trap - EXIT

# ── FAN-OUT ──────────────────────────────────────────────────────────────────────────────────────
: > "$BDIR/workers.tsv"
seedflag=""; [ "$seeded" = 1 ] && seedflag=1
while IFS=$'\t' read -r sid pane; do
  [ -n "$sid" ] || continue
  wpid=""
  if command -v detach >/dev/null 2>&1; then
    wpid="$(detach "$BDIR/$sid.worker.log" env LR_MOVE_PRESEEDED="$seedflag" /bin/bash "$WORKER" "$BATCH" "$sid" 2>/dev/null)" || wpid=""
  fi
  case "$wpid" in
    ''|*[!0-9]*)
      lr_claim_release "$CLAIMS" "$sid" "$$"
      result "$sid" "$pane" NOTMOVED "worker-not-started: the detached worker could not be spawned; nothing touched" ;;
    *) lr_claim_restamp "$CLAIMS" "$sid" "$$" "$wpid" "lr-move-worker ($BATCH)" "$pane" || say "could not re-stamp the claim of ${sid:0:8} to worker $wpid"
       printf '%s\t%s\t%s\n' "$sid" "$pane" "$wpid" >> "$BDIR/workers.tsv" ;;
  esac
done <<EOF
$CLAIMED
EOF
say "admitted; $(grep -c . "$BDIR/workers.tsv" 2>/dev/null || echo 0) worker(s) started"

# ── WATCH ────────────────────────────────────────────────────────────────────────────────────────
deadline=$(( $(date +%s) + UNTIL + ${LR_MOVE_SLOT_WAIT_S:-600} + ${LR_MOVE_PROVE_S:-300} + 300 ))
last_snap=0
while :; do
  left=0
  while IFS=$'\t' read -r sid pane wpid; do
    [ -n "$sid" ] || continue
    [ -e "$BDIR/$sid.json" ] && continue
    if kill -0 "$wpid" 2>/dev/null; then left=$((left + 1)); continue; fi
    # The worker is gone and left no result: its verdict comes from disk, like every other.
    sleep 1; [ -e "$BDIR/$sid.json" ] && continue
    IFS=$'\t' read -r v why _ _ <<EOF2
$(lr_move_verdict "$sid" "$pane" "$(jq -r --arg s "$sid" '.rows[] | select(.sid == $s) | .config_dir' "$PLAN")" "$TO_CFG" "$BDIR")
EOF2
    result "$sid" "$pane" "${v:-FAILED}" "worker-died: ${why:-no verdict could be read}"
    lr_claim_release "$CLAIMS" "$sid" "$wpid"
  done < "$BDIR/workers.tsv"
  [ "$left" -gt 0 ] || break
  [ "$(date +%s)" -lt "$deadline" ] || { say "the watch bound passed with $left worker(s) still running; they keep their claims and write their own results"; break; }
  if compgen -G "$BDIR/*.waiting" >/dev/null 2>&1 && [ $(( $(date +%s) - last_snap )) -ge "${LR_MOVE_SNAP_S:-20}" ]; then
    if /bin/bash "$UPGRADE" --switch-census --from "$FROM" --target "$TO" > "$BDIR/snap.tsv.tmp" 2>/dev/null; then
      mv -f "$BDIR/snap.tsv.tmp" "$BDIR/snap.tsv" && date +%s > "$BDIR/snap.ts"
    fi
    last_snap="$(date +%s)"
  fi
  sleep "${LR_MOVE_WATCH_POLL_S:-2}"
done

# ── CLOSE: two checks that can fail ──────────────────────────────────────────────────────────────
AUTH_AFTER=unchecked
if [ "${LR_MOVE_AUTH_RECHECK:-on}" != off ]; then
  rrc=0; route_read --fresh || rrc=$?
  case "$rrc" in 0) AUTH_AFTER=ok ;; 1) AUTH_AFTER="LOST: $ROUTE_WHY" ;; *) AUTH_AFTER="unverified: $ROUTE_WHY" ;; esac
fi
if [ "${LR_MOVE_GUARD_CHECK:-on}" != off ] && [ -n "$GUARD" ]; then
  for f in "$BDIR"/*.json; do
    case "${f##*/}" in plan.json|admit.json|summary.json|request*.json) continue ;; esac
    case "$(jq -r '.verdict // empty' "$f" 2>/dev/null)" in MOVED|MOVED-NEW-PANE|MOVED-UNREGISTERED) ;; *) continue ;; esac
    sid="$(jq -r '.sid' "$f")"
    tx="$(lr_session_location "$sid" | sed -n '1p' | cut -f2)"
    [ -n "$tx" ] || continue
    grc=0
    jq -nc --arg s "$sid" --arg t "$tx" '{session_id:$s, transcript_path:$t, hook_event_name:"UserPromptSubmit", prompt:"."}' \
      | CLAUDE_CONFIG_DIR="$TO_CFG" /bin/bash "$GUARD" >"$BDIR/$sid.guard.log" 2>&1 || grc=$?
    if [ "$grc" -eq 2 ]; then
      jq -c '.verdict = "FAILED" | .reason = ("guard-blocks: the session runs on the target but the prompt guard refuses its prompts (cc-lr repair-markers --sid " + .sid + "); was " + .reason)' "$f" > "$f.$$.tmp" 2>/dev/null \
        && mv -f "$f.$$.tmp" "$f"
    fi
  done
fi
summary "done" ""
exit 0
