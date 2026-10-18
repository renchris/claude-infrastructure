#!/usr/bin/env bats
# shellcheck disable=SC2034,SC2119,SC2120  # globals are read by the eval-extracted functions under test; fire() takes optional args
# handoff-fire.sh --recycle, remote form — the four narrow fixes of docs/plans/LIMIT_RECOVER_SELF_INPLACE.md
# § W0 (root causes R1, R2, R3) that live in the recycle's admission and hold paths.
#
#   R1  a remote recycle whose --source-session/--source-pane name the CALLER ITSELF is refused up
#       front: the remote form's post-confirm at-rest read can never pass on a session whose own
#       Bash call is in flight, so it could only confirm and then unconfirm.
#   R2  a --transplanted-source remote recycle refuses while ANOTHER live actuator holds the move
#       lane's per-sid claim (runs/by-sid/<sid>.active): the holder owns the transplant and its retry.
#   R3  owed rows say which form they are; a transplanted-source hold after unconfirm rc 0 names a
#       runnable re-drive instead of a replay whose tombstone is gone.
#
# Setup mirrors tests/handoff-recycle-remote-resume.bats (PATH shims, --dry-run, whole script), with
# one addition: the ps shim can answer `-o ppid=` from the real /bin/ps (PS_REAL_PPID=1), because R1's
# second proof and R2's ownership test are ancestry walks.

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export CC_ADMIT_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  unset KITTY_WINDOW_ID LR_STATE_DIR LR_RECORD_ID
  export IT2_WRAPPER_NO_KITTY=1
  export CC_TERM=iterm2
  unset ITERM_SESSION_ID CLAUDE_CODE_SESSION_ID

  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired"; mkdir -p "$CC_FIRED_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep-stamp.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"
  export CC_PANE_CLOSE_QUEUE_DIR="$BATS_TEST_TMPDIR/pcq"
  # Any transplant phase would run this stub; R1/R2 refusals must never reach it.
  TP_LOG="$BATS_TEST_TMPDIR/lr-transplant.calls"
  export HF_LR_TRANSPLANT="$BATS_TEST_TMPDIR/lr-transplant-stub.sh"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$TP_LOG" > "$HF_LR_TRANSPLANT"
  chmod +x "$HF_LR_TRANSPLANT"

  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  cat > "$SHIM/osascript" <<'SH'
#!/usr/bin/env bash
uuid=""
while [ $# -gt 0 ]; do
  case "$1" in
    -e) shift 2 2>/dev/null || shift ;;
    -)  shift ;;
    *)  uuid="$1"; shift ;;
  esac
done
[ -n "$uuid" ] && printf '%s' "TTY-$uuid"
exit 0
SH
  cat > "$SHIM/git" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  # ps: `-o tty=` answers PS_TTY_OUT (the row pid sits on the pane's tty); `-o lstart=` one fixed
  # start time; `-o ppid=` answers NOTHING unless PS_REAL_PPID=1, when it is the real /bin/ps.
  cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
orig=("$@"); want=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) case "${2:-}" in tty=) want=tty ;; ppid=) want=ppid ;; lstart=) want=lstart ;; esac; shift 2 ;;
    *) shift ;;
  esac
done
[ "$want" = ppid ] && [ "${PS_REAL_PPID:-0}" = 1 ] && exec /bin/ps "${orig[@]}"
[ "$want" = tty ] && [ -n "${PS_TTY_OUT:-}" ] && printf '%s\n' "$PS_TTY_OUT"
[ "$want" = lstart ] && printf 'Tue Sep 29 10:00:00 2026\n'
exit 0
SH
  chmod +x "$SHIM/osascript" "$SHIM/git" "$SHIM/ps"
  export PATH="$SHIM:$PATH"

  SRC_PANE="11110000-2222-3333-4444-555566667777"
  SESS="7b3f9c10-0000-4000-8000-abcdefabcdef"
  SRC_CFG="$BATS_TEST_TMPDIR/cfg-source"
  TARGET_CFG="$BATS_TEST_TMPDIR/cfg-target"
  SLUG="-Users-x-Development-thing"
  mkdir -p "$SRC_CFG/projects/$SLUG" "$TARGET_CFG/projects/$SLUG"
  export CC_PROJECTS_DIRS="$SRC_CFG/projects $TARGET_CFG/projects"
  TOMB="$SRC_CFG/projects/$SLUG/$SESS.HANDOFF.json"
  LOCKDIR="$HOME/.reso/limit-recover/locks"; mkdir -p "$LOCKDIR"
  LOCK="$LOCKDIR/$SESS.lock"
  CLAIM="$HOME/.reso/limit-recover/runs/by-sid/$SESS.active"
  LAUNCHER="$BATS_TEST_TMPDIR/lr-launch-abcd1234-XXXXXX.sh"
  printf '#!/bin/bash\nexec /bin/echo resume\n' > "$LAUNCHER"; chmod +x "$LAUNCHER"
  CWD_DIR="$BATS_TEST_TMPDIR/wt"; mkdir -p "$CWD_DIR"
  export PS_TTY_OUT="TTY-$SRC_PANE"
}

mk_transplant() {
  printf '{"handed_off_to":"%s","target_transcript":"%s","ts":"2026-09-09T00:00:00Z","lock":"%s"}\n' \
    "$TARGET_CFG" "$TARGET_CFG/projects/$SLUG/$SESS.jsonl" "$LOCK" > "$TOMB"
  printf '{"sid":"%s","from":"%s","to":"%s","pid":1}\n' "$SESS" "$SRC_CFG" "$TARGET_CFG" > "$LOCK"
}
src_row() { # $1 = pid the row names (default: this bats process)
  printf '{"paneUUID":"%s","name":"x-%s","cwd":"%s","account":"cfg-source","pid":%d,"session_id":"%s","surface":"pane"}\n' \
    "$SRC_PANE" "$SRC_PANE" "$CWD_DIR" "${1:-$$}" "$SESS" > "$CC_REGISTRY_DIR/$SRC_PANE.json"
}
live_stranger() { # → a live process of ours that is NOT an ancestor of the subject; dies on its own
  sleep 60 >/dev/null 2>&1 3>&- &
  STRANGER=$!
}
mk_claim() { # $1 = holder pid
  mkdir -p "$CLAIM"
  printf '{"sid":"%s","pane":"-","pid":%d,"ts":"2026-10-18T00:00:00Z","by":"lr-fleet worker"}\n' "$SESS" "$1" > "$CLAIM/holder"
}
recycle() {
  run bash "$HF" --recycle --dry-run --transplanted-source --source-pane "$SRC_PANE" --source-session "$SESS" \
      --resume-launcher "$LAUNCHER" --resume-cfg "$TARGET_CFG" "$@"
}
admitted() { [[ "$output" == *"remote in-place resume: pane $SRC_PANE is PROVEN to hold session ${SESS:0:8}"* ]]; }
no_side_effects() {
  [ ! -e "$TP_LOG" ] || { echo "lr-transplant ran: $(cat "$TP_LOG")"; return 1; }
  [ -z "$(ls -A "$CC_PANE_CLOSE_QUEUE_DIR" 2>/dev/null)" ] || { echo "a pcq row was written"; ls -la "$CC_PANE_CLOSE_QUEUE_DIR"; return 1; }
}

# ── R1 — the caller names ITSELF ──────────────────────────────────────────────────────────────────

@test "R1 RED: CLAUDE_CODE_SESSION_ID = --source-session ⇒ rc 2, refused up front, nothing typed or recorded" {
  mk_transplant; src_row
  CLAUDE_CODE_SESSION_ID="$SESS" recycle
  [ "$status" -eq 2 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"!! --recycle REFUSED: --source-pane/--source-session name THIS session (${SESS:0:8}, pane $SRC_PANE)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"Move yourself with: cc-lr move --sid $SESS --to "* ]] || { echo "$output"; false; }
  [[ "$output" == *"Nothing was typed."* ]] || false
  ! admitted || { echo "the remote form was taken: $output"; false; }
  no_side_effects
}

@test "R1 RED: the env proof binds before the registry is even read (no row at all)" {
  mk_transplant
  CLAUDE_CODE_SESSION_ID="$SESS" recycle
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"name THIS session"* ]] || { echo "$output"; false; }
  [[ "$output" != *"no session-registry row"* ]] || false
}

@test "R1 RED: no env, but the bound row's pid is an ANCESTOR of the caller ⇒ refused as self" {
  mk_transplant; src_row "$$"
  PS_REAL_PPID=1 recycle
  [ "$status" -eq 2 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"name THIS session (${SESS:0:8}, pane $SRC_PANE)"* ]] || { echo "$output"; false; }
  no_side_effects
}

@test "R1 CONTROL: a different session id and a non-ancestor row pid ⇒ the remote form, unchanged" {
  live_stranger
  mk_transplant; src_row "$STRANGER"
  CLAUDE_CODE_SESSION_ID="00000000-0000-4000-8000-000000000000" PS_REAL_PPID=1 recycle
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  admitted || { echo "$output"; false; }
  [[ "$output" != *"name THIS session"* ]] || false
}

@test "R1 kill switch: CC_RECYCLE_REMOTE_SELF_REFUSE=off restores the old admission" {
  mk_transplant; src_row
  CC_RECYCLE_REMOTE_SELF_REFUSE=off CLAUDE_CODE_SESSION_ID="$SESS" recycle
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  admitted || { echo "$output"; false; }
}

# ── R2 — another actuator holds the move claim ───────────────────────────────────────────────────

@test "R2 RED: a LIVE foreign holder of runs/by-sid/<sid>.active ⇒ rc 2 before any confirm" {
  live_stranger
  mk_transplant; src_row; mk_claim "$STRANGER"
  recycle
  [ "$status" -eq 2 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"!! --recycle REFUSED: another actuator holds session ${SESS:0:8}'s move claim (pid $STRANGER, lr-fleet worker) — it owns this transplant and its retry. Nothing was typed."* ]] || { echo "$output"; false; }
  ! admitted || false
  no_side_effects
}

@test "R2 CONTROL: the holder is an ANCESTOR of the caller (worker → lr-handoff → handoff-fire) ⇒ proceeds" {
  live_stranger
  mk_transplant; src_row "$STRANGER"; mk_claim "$$"
  PS_REAL_PPID=1 recycle
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  admitted || { echo "$output"; false; }
}

@test "R2 CONTROL: a DEAD holder, or no claim at all, proceeds exactly as before" {
  mk_transplant; src_row
  recycle
  [ "$status" -eq 0 ] && admitted || { echo "no claim: $output"; false; }
  ( exit 0 ) & dead=$!; wait "$dead"
  mk_claim "$dead"
  recycle
  [ "$status" -eq 0 ] && admitted || { echo "dead holder: $output"; false; }
}

@test "R2 kill switch: CC_RECYCLE_CLAIM_CHECK=off ignores a live foreign holder" {
  live_stranger
  mk_transplant; src_row; mk_claim "$STRANGER"
  CC_RECYCLE_CLAIM_CHECK=off recycle
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  admitted || { echo "$output"; false; }
}

# ── R2/R3 — owed rows carry their form ───────────────────────────────────────────────────────────

owed_units() {
  eval "$(sed -n '/^sc_pcq_load() {/,/^}/p;/^hf_recycle_owed_record() {/,/^}/p' "$HF")"
  cc_sid_for_pane() { printf 'sid-77'; }
  export HF_INVOKED_ARGS="--recycle " CC_PCQ_LIB="$REPO/scripts/lib/pane-close-queue.sh"
}

@test "R3 RED: a REMOTE hold's owed row carries form=remote, the record id and the actor pid" {
  owed_units
  RCY_REMOTE=1 LR_RECORD_ID="rec-4242" hf_recycle_owed_record 77 "kitty remote control not answering" 2>/dev/null
  row="$CC_PANE_CLOSE_QUEUE_DIR/recycle-77.json"
  [ -s "$row" ] || { ls -la "$CC_PANE_CLOSE_QUEUE_DIR"; false; }
  [ "$(jq -r .form "$row")" = remote ] || { cat "$row"; false; }
  [ "$(jq -r .record_id "$row")" = rec-4242 ] || { cat "$row"; false; }
  [ "$(jq -r .actor_pid "$row")" = "$PPID" ] || { cat "$row"; false; }
}

@test "R3 RED: a SELF hold's owed row carries form=self and no remote fields" {
  owed_units
  RCY_REMOTE=0 LR_RECORD_ID="rec-4242" hf_recycle_owed_record 77 "kitty remote control not answering" 2>/dev/null
  row="$CC_PANE_CLOSE_QUEUE_DIR/recycle-77.json"
  [ "$(jq -r .form "$row")" = self ] || { cat "$row"; false; }
  [ "$(jq -r 'has("record_id") or has("actor_pid")' "$row")" = false ] || { cat "$row"; false; }
  [ "$(jq -r .sid "$row")" = sid-77 ] || false
}

# ── R3 — the hold after a withdrawn transplant names a runnable re-drive ─────────────────────────

hold_units() {
  eval "$(sed -n '/^hf_recycle_hold() {/,/^}/p' "$HF")"
  hf_recycle_unconfirm() { RCY_UNCONFIRM_RC="${UNCONFIRM:-0}"; }
  hf_recycle_disarm() { :; }
  emit_recycle_event() { :; }
  hf_tx_account() { return 1; }
  SID=77 CMD="bash handoff-fire.sh --recycle …" HF_TS_TO="$TARGET_CFG" RCY_TS_SID="$SESS"
}
# The parser that consumes the hold sentence (lr-handoff.sh:1975-1976). Pinned here by grep so a drift
# on either side fails this file, not a live move.
LRH_HELD_RE='recycle (ABORTED before /exit|HELD after /exit was TYPED|HELD after SIGTERM) \(held: [A-Za-z-]+\)'

@test "R3 RED: transplanted-source hold after unconfirm rc 0 adds the re-drive line; the parsed sentence is unchanged" {
  grep -qF "$LRH_HELD_RE" "$REPO/scripts/limit-recover/lr-handoff.sh"
  grep -qF "grep -q 'unconfirm rc 0\.'" "$REPO/scripts/limit-recover/lr-handoff.sh"
  hold_units
  RCY_TRANSPLANTED_SOURCE=1 UNCONFIRM=0 run hf_recycle_hold draft "detail" "an operator draft"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"!! the transplant was withdrawn (unconfirm rc 0), so the command above cannot be replayed — its tombstone and lock are gone. Re-drive the whole move: cc-lr move --sid $SESS --to $TARGET_CFG"* ]] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE "$LRH_HELD_RE" || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'unconfirm rc 0\.' || { echo "$output"; false; }
  [[ "$output" == *"Re-run: bash handoff-fire.sh --recycle …"* ]] || false
}

@test "R3 CONTROL: no re-drive line for a self-form hold, or when the unconfirm did not succeed" {
  hold_units
  RCY_TRANSPLANTED_SOURCE=0 UNCONFIRM=0 run hf_recycle_hold draft "detail" "an operator draft"
  [[ "$output" != *"transplant was withdrawn"* ]] || { echo "$output"; false; }
  RCY_TRANSPLANTED_SOURCE=1 UNCONFIRM=n/a run hf_recycle_hold draft "detail" "an operator draft"
  [[ "$output" != *"transplant was withdrawn"* ]] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE "$LRH_HELD_RE" || false
}
