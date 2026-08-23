#!/usr/bin/env bats
# cc-backlog `reap` — the CURE SWEEP that re-adjudicates the machine's own off-box blocks.
#
# THE DEFECT THIS PINS (measured on the live store 2026-08-23, backlog cloud-lane wave):
# `cloud_map` blocks an item whose off-box worker reads BOOTING/ALIVE, writing the sentence
#   "a LIVE off-box worker (cc-cloud reads ALIVE) still holds this item past the ceiling…"
# The cure sweep is what later reverses that block once the worker stops. It selects rows by
# matching their `needs` prose — and it was still matching only "worker runs off-box (venue",
# a sentence cloud_map had stopped writing. Result: the select matched 0 rows while 20 blocked
# rows carried the live sentence, the oldest stuck since 08-18, every one of them already read
# STALLED/NOT-STARTED/ABANDONED by `cc-cloud --table` — states cloud_map maps to `open`.
# The verdict was right and no actuator could reach it.
#
# The block record persists only {by,event,id,needs,ts} — there is NO token field — so the
# sentence is the join key between the writer and the reader, and two sides joined on prose can
# drift again. Hence test 1 does not hard-code the sentence: it RENDERS it out of cc-backlog's own
# `cloud_map` printf and feeds that to the sweep. Reword cloud_map and this suite goes red, instead
# of silently stranding rows (memory: control-calibrated-to-implementation-decays).

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"        # hermeticity rule 1
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/.dispatch-kick"
  export CC_BACKLOG_KICK_BIN="$BATS_TEST_TMPDIR/no-such-dispatch"
  BINDIR="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BINDIR"
}

# cloud_state() resolves cc-cloud from `dirname $0` FIRST, so the subject must be a COPY with our
# stub beside it — otherwise the real cc-cloud answers and the test reads live fleet state.
install_subject() {  # $1=source cc-backlog  $2=state the stub reports
  cp "$1" "$BINDIR/cc-backlog"; chmod +x "$BINDIR/cc-backlog"
  cat > "$BINDIR/cc-cloud" <<STUB
#!/usr/bin/env bash
[ "\$1" = "show" ] || exit 2
echo "state=$2"
STUB
  chmod +x "$BINDIR/cc-cloud"
}

# Render cloud_map's BOOTING/ALIVE message straight out of the SOURCE, so the fixture cannot drift
# away from the producer. Anchored on the printf (not the phrase) so prose in comments is not read
# as code.
render_cloud_map_msg() {  # $1=cc-backlog path  $2=id
  local fmt
  fmt="$(grep -F "printf 'block" "$1" | grep -F "a LIVE off-box worker (cc-cloud reads" \
         | sed -e "s/^[[:space:]]*printf '//" -e "s/' \"\\\$st\".*//")"
  [ -n "$fmt" ] || return 1
  # shellcheck disable=SC2059
  printf "$fmt" ALIVE "$2" "$2" | cut -d$'\037' -f3
}

# Seed one row in exactly the shape the live store holds: added, claimed off-box, then blocked by
# the reap itself with cloud_map's sentence.
seed_blocked_offbox() {  # $1=id  $2=needs
  local id="$1" needs="$2"
  {
    jq -cn --arg id "$id" '{ts:"2026-08-18T09:00:00Z",id:$id,event:"add",title:"cloud lane fixture row",condition:"master-fixture"}'
    jq -cn --arg id "$id" '{ts:"2026-08-18T09:20:00Z",id:$id,event:"claim",venue:"cloud"}'
    jq -cn --arg id "$id" --arg n "$needs" '{ts:"2026-08-18T09:33:16Z",id:$id,event:"block",by:"cc-backlog-reap",needs:$n}'
  } > "$CC_BACKLOG_FILE"
}

status_of() {  # $1=id → the folded state
  "$BINDIR/cc-backlog" list --json 2>/dev/null \
    | jq -r --arg id "$1" '.[] | select(.id==$id) | .status' | tail -1
}

@test "cure sweep UNBLOCKS an off-box block once cc-cloud stops reading it as live" {
  install_subject "$REPO/bin/cc-backlog" STALLED
  # the sentence comes from the PRODUCER, not from this file
  msg="$(render_cloud_map_msg "$REPO/bin/cc-backlog" cure0001abcd)"
  [ -n "$msg" ]
  echo "$msg" | grep -q "a LIVE off-box worker"
  seed_blocked_offbox cure0001abcd "$msg"

  # precondition: it really is blocked before the sweep, so the assertion below is not vacuous
  [ "$(status_of cure0001abcd)" = "blocked" ]

  run "$BINDIR/cc-backlog" reap
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "UNBLOCK cure0001abcd"
  [ "$(status_of cure0001abcd)" = "open" ]
}

@test "CONTROL: the pre-fix cc-backlog (pinned e6e5a4355) leaves the same row blocked" {
  # Replayed from a LITERAL sha, never origin/main — origin/main advances past this fix the moment
  # it lands, and the control would then compare the fix to itself. (That exact error cost a land
  # rc 6 from moving-ref-control-lint on 2026-08-22.) origin/main had already moved from e6e5a4355
  # to beba9eab5 during the session that wrote this, which is the point.
  pre="$BATS_TEST_TMPDIR/cc-backlog-prefix"
  git -C "$REPO" show e6e5a4355:bin/cc-backlog > "$pre"
  # the control must be the PRE-fix subject or it proves nothing
  ! grep -qF 'a LIVE off-box worker \\(cc-cloud reads' "$pre" || false

  install_subject "$pre" STALLED
  # the FIXTURE sentence is the one the pre-fix binary itself writes, so this is its own prose,
  # not a sentence invented to make it fail
  msg="$(render_cloud_map_msg "$pre" cure0001abcd)"
  [ -n "$msg" ]
  seed_blocked_offbox cure0001abcd "$msg"
  [ "$(status_of cure0001abcd)" = "blocked" ]

  run "$BINDIR/cc-backlog" reap
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "UNBLOCK cure0001abcd" || false
  [ "$(status_of cure0001abcd)" = "blocked" ]     # ← the stranding this fix ends
}

@test "FAILURE DIRECTION: a worker cc-cloud still reads ALIVE stays blocked" {
  # Widening what the sweep can SEE must not widen what it ACTS on. A live off-box worker must keep
  # its block, or the reopen fires a second peer onto live work — the double-dispatch cloud_map
  # exists to prevent.
  install_subject "$REPO/bin/cc-backlog" ALIVE
  msg="$(render_cloud_map_msg "$REPO/bin/cc-backlog" cure0002abcd)"
  seed_blocked_offbox cure0002abcd "$msg"
  [ "$(status_of cure0002abcd)" = "blocked" ]

  run "$BINDIR/cc-backlog" reap
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "UNBLOCK cure0002abcd" || false
  [ "$(status_of cure0002abcd)" = "blocked" ]
}

@test "scope: a block by ANY other author is untouched, even with the same sentence" {
  install_subject "$REPO/bin/cc-backlog" STALLED
  msg="$(render_cloud_map_msg "$REPO/bin/cc-backlog" cure0003abcd)"
  {
    jq -cn '{ts:"2026-08-18T09:00:00Z",id:"cure0003abcd",event:"add",title:"fixture",condition:"master-fixture"}'
    jq -cn '{ts:"2026-08-18T09:20:00Z",id:"cure0003abcd",event:"claim",venue:"cloud"}'
    jq -cn --arg n "$msg" '{ts:"2026-08-18T09:33:16Z",id:"cure0003abcd",event:"block",by:"a-human",needs:$n}'
  } > "$CC_BACKLOG_FILE"

  run "$BINDIR/cc-backlog" reap
  [ "$status" -eq 0 ]
  [ "$(status_of cure0003abcd)" = "blocked" ]
}
