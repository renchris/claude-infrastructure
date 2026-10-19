#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2034
#   SC2030/2031: every @test body is its own subshell. SC2034: read by eval-extracted functions.
#
# handoff-fire admits BEFORE it spawns, and hands the launcher the decision (lr-wake incident
# 2026-10-18, REPORT §4 Wave E; RC2/RC7).
#
# The night: an agent fired `--launcher /tmp/lr-rescue/resume-<sid>.sh` 25 times. handoff-fire's outer
# gate admitted each fire and minted nothing; lr-fire-resume then re-evaluated the box INSIDE the new
# pane and refused with exit 9 — after the pane existed — so every refusal left a plain shell (13
# husks). The fire budget was one counter for every fire on the box, so one session's refusal released
# the next session's fire. And the launchers it fired were hand-written into /tmp for sessions that
# limit-recover had recorded STRANDED, whose own text said "do NOT hand-spawn".
#
# What is pinned here:
#   1. a refused admission opens NO pane (0 `kitty @ launch`, 0 splits) and exits 9 — RED on main,
#      where the fire went on to split the anchor;
#   2. an admitted one hands lr-fire-resume an admission token, and the in-pane gate, called exactly as
#      lr-fire-resume.sh calls it, redeems it: its IDL row reads basis `token`, not a fresh decision;
#   3. the fire budget is keyed per subject (two sessions never share one refusal count);
#   4. a /tmp launcher for a session with a STRANDED record is refused, exit 2.
#
# Hermetic: HOME, the IDL, the admission state, limit-recover's state dir and every terminal are
# per-test; the it2 binary is a recording stub (IT2_BIN), so an unfixed tree cannot reach a real pane.

SID=5232121f-eb5b-487d-82b1-225e0730264a
SID2=e52f1f63-0000-4000-8000-000000000002

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  # Seams that do NOT resolve under $HOME (test-hermeticity-lint 5a/5b): absent paths, sensors fail open.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  # capacity-admit is a SUBJECT here, so its live terms are pinned rather than switched off
  # (test-hermeticity-lint AMBIENT): synthetic load and headroom, no reserve census.
  export CC_ADMIT_LOADAVG_OVERRIDE=0.10 CC_ADMIT_HEADROOM_OVERRIDE=64 CC_ADMIT_RESERVE_TERM=off
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  export CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/admit"
  export CC_FIRE_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/fire-admit"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lr"; mkdir -p "$LR_STATE_DIR"
  export CC_SPAWN_LOG_FILE="$BATS_TEST_TMPDIR/spawns.jsonl"
  export KLOG="$BATS_TEST_TMPDIR/kitty.log" KSTATE="$BATS_TEST_TMPDIR/ls.json"; : > "$KLOG"
  python3 -c 'import json,sys; json.dump([{"id":18,"tabs":[{"id":146,"layout":"splits","windows":[{"id":344,"columns":80}]}]}], open(sys.argv[1],"w"))' "$KSTATE"
  export CC_TERM_KITTY="$BATS_TEST_DIRNAME/fixtures/pane-placement/fake-kitty.py"
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/sock"
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  # it2 stub: every call recorded; a split "creates" pane 901 and records the command it carried.
  cat > "$STUB/it2" <<SH
#!/bin/bash
printf 'it2 %s | CC_PANE_CMD=%s\n' "\$*" "\${CC_PANE_CMD:-}" >> "$KLOG"
case "\$1 \$2" in "session split") echo "Created new pane: 901" ;; esac
exit 0
SH
  chmod +x "$STUB/it2"
  printf '#!/bin/sh\necho "osascript $*" >> "%s"\nexit 1\n' "$KLOG" > "$STUB/osascript"; chmod +x "$STUB/osascript"
  export PATH="$STUB:$PATH" IT2_BIN="$STUB/it2"
  export FIRE_ENGAGE_TIMEOUT=1 FIRE_ENGAGE_RETRY=1 FIRE_ENGAGE_INTERVAL=1 FIRE_REG_TIMEOUT=0
  # The launcher: the overnight rescue shape, minus /tmp (case 4 owns that).
  LDIR="$BATS_TEST_TMPDIR/lr-rescue"; mkdir -p "$LDIR"
  LAUNCHER_F="$LDIR/resume-${SID:0:8}.sh"
  printf '#!/bin/bash\n# Rescue launcher for a session transplanted next4 -> next2.\nexec %s next2 %s %s --model claude-opus-5-5\n' \
    "$REPO/scripts/limit-recover/lr-fire-resume.sh" "$BATS_TEST_TMPDIR" "$SID" > "$LAUNCHER_F"
  chmod +x "$LAUNCHER_F"
  PF="$BATS_TEST_TMPDIR/p.txt"; printf 'brief\n' > "$PF"
  # A capacity library whose admit answers STUB_ADMIT_RC: the seam the script already honours.
  STUBLIB="$BATS_TEST_TMPDIR/capacity-admit-stub.sh"
  cat > "$STUBLIB" <<'SH'
cc_capacity_admit() { echo "$1|$2|actor=${CC_ADMIT_ACTOR:-}|key=${CC_ADMIT_BUDGET_KEY:-}" >> "$ADMIT_CALLS"; return "${STUB_ADMIT_RC:-0}"; }
cc_capacity_admit_reason() { printf 'capacity-admit: REFUSE (stub)'; }
cc_capacity_token_mint() { printf '%s' "$BATS_TEST_TMPDIR/tok.$1"; : > "$BATS_TEST_TMPDIR/tok.$1"; }
cc_hw_budget_charge() { return 1; }
SH
  export ADMIT_CALLS="$BATS_TEST_TMPDIR/admit-calls"; : > "$ADMIT_CALLS"
}

launches() { grep -c -E ' launch |session split' "$KLOG" || true; }

@test "a REFUSED admission opens no pane: exit 9, zero kitty launches, zero splits" {
  export CC_FIRE_CAPACITY_LIB="$STUBLIB" STUB_ADMIT_RC=9 KITTY_WINDOW_ID=344
  unset IT2_WRAPPER_NO_KITTY ITERM_SESSION_ID
  run bash "$HF" --prompt-file "$PF" --launcher "$LAUNCHER_F" --cwd "$BATS_TEST_TMPDIR" --split-right --session-id 344 --no-notify-back
  echo "$output"
  [ "$status" -eq 9 ]
  [ "$(launches)" -eq 0 ] || { cat "$KLOG"; false; }
  grep -qF "handoff-fire|fire lr-fire-resume relaunch of $SID|actor=handoff-fire|key=$SID" "$ADMIT_CALLS"
  [[ "$output" == *"BEFORE any pane was opened"* ]] || false
}

@test "an ADMITTED relaunch carries LR_ADMIT_TOKEN into the pane's command, minted for that session" {
  export CC_FIRE_CAPACITY_LIB="$STUBLIB" STUB_ADMIT_RC=0 KITTY_WINDOW_ID=344
  unset IT2_WRAPPER_NO_KITTY ITERM_SESSION_ID
  run bash "$HF" --prompt-file "$PF" --launcher "$LAUNCHER_F" --cwd "$BATS_TEST_TMPDIR" --split-right --session-id 344 --no-notify-back
  echo "$output"
  [ "$(grep -c 'session split' "$KLOG")" -eq 1 ]
  grep 'session split' "$KLOG" | grep -qF "LR_ADMIT_TOKEN=$BATS_TEST_TMPDIR/tok.$SID $LAUNCHER_F"
}

@test "THE IN-PANE IDL BASIS IS token: lr-fire-resume's own gate call redeems what the fire minted" {
  # The REAL library on both sides. The fire-side admission with every box term off (this test is
  # about the HANDOVER, not about this box's load); the in-pane side called with exactly the
  # arguments lr-fire-resume.sh passes (CC_ADMIT_TOKEN from LR_ADMIT_TOKEN, CC_ADMIT_WANT_SID).
  export CC_ADMIT_LOAD_TERM=off CC_ADMIT_HEADROOM_TERM=off CC_ADMIT_SEGMENT_TERM=off CC_ADMIT_ACTIVE_TERM=off
  # shellcheck source=/dev/null
  . "$REPO/scripts/lib/capacity-admit.sh"
  local f
  for f in hf_launcher_file hf_launcher_subject hf_launcher_is_lr hf_lr_admit; do
    eval "$(sed -n "/^$f() {/,/^}/p" "$HF")"
  done
  RECYCLE=0 DRY=0 NC="nocorrect " PREFIX="CC_ACCOUNT_PINNED=1 " LAUNCHER="$LAUNCHER_F"
  CMD="cd /x && ${NC}${PREFIX}${LAUNCHER} \"\$(cat /x/p)\""
  unset LR_ADMIT_TOKEN
  hf_lr_admit 2>/dev/null
  [ -n "$HF_ADMIT_TOKEN" ] && [ -f "$HF_ADMIT_TOKEN" ] || false
  [[ "$CMD" == *"LR_ADMIT_TOKEN=$HF_ADMIT_TOKEN $LAUNCHER_F"* ]] || { echo "$CMD"; false; }
  # in the pane (lr-fire-resume.sh:864 shape), with the load term ON: the token, not the box, decides
  CC_ADMIT_LOAD_TERM=on CC_ADMIT_TOKEN="$HF_ADMIT_TOKEN" CC_ADMIT_WANT_SID="$SID" \
    cc_capacity_admit lr-fire-resume "resume $SID on next2"
  run jq -r 'select(.caller == "lr-fire-resume") | "\(.verdict) \(.basis)"' "$CC_ADMIT_IDL"
  [ "$output" = "admit token" ] || { cat "$CC_ADMIT_IDL"; false; }
}

@test "a launcher that already exports its own LR_ADMIT_TOKEN owns admission: nothing is evaluated or minted" {
  export CC_FIRE_CAPACITY_LIB="$STUBLIB"
  # shellcheck source=/dev/null  # the per-test stub library written in setup()
  . "$STUBLIB"
  local f
  for f in hf_launcher_file hf_launcher_subject hf_launcher_is_lr hf_lr_admit; do
    eval "$(sed -n "/^$f() {/,/^}/p" "$HF")"
  done
  printf 'export LR_ADMIT_TOKEN=/x/tokens/%s.abc\n' "$SID" >> "$LAUNCHER_F"
  RECYCLE=0 DRY=0 NC="" PREFIX="" LAUNCHER="$LAUNCHER_F" CMD="cd /x && $LAUNCHER_F"
  unset LR_ADMIT_TOKEN
  hf_lr_admit
  [ ! -s "$ADMIT_CALLS" ]
  [ "$CMD" = "cd /x && $LAUNCHER_F" ]
}

@test "THE FIRE BUDGET IS PER SUBJECT: two sessions' launchers never share one refusal counter" {
  local f
  for f in hf_launcher_file hf_launcher_subject _cc_fire_subject _cc_fire_budget_file; do
    eval "$(sed -n "/^$f() {/,/^}/p" "$HF")"
  done
  local l2="$LDIR/resume-${SID2:0:8}.sh"
  sed "s/$SID/$SID2/" "$LAUNCHER_F" > "$l2"
  WORKTREE="" CWD="" SESSION_ID=""
  LAUNCHER="$LAUNCHER_F"; a="$(_cc_fire_budget_file load)"
  LAUNCHER="$l2";         b="$(_cc_fire_budget_file load)"
  [ -n "$a" ] && [ -n "$b" ] || false
  [ "$a" != "$b" ]
  [[ "$a" == *"/load.sid-$SID.refusals" ]] || { echo "$a"; false; }
  # the operator's re-fire of the SAME thing meets the SAME counter (the bound still releases it)
  LAUNCHER="$LAUNCHER_F"; [ "$(_cc_fire_budget_file load)" = "$a" ]
  # and a worktree fire is keyed by its worktree
  LAUNCHER="claude4" WORKTREE="fix-x"; [[ "$(_cc_fire_budget_file headroom)" == *"/headroom.wt-fix-x.refusals" ]]
}

@test "a /tmp launcher for a session with a STRANDED record is REFUSED (exit 2) before any gate" {
  local d; d="$(mktemp -d /tmp/hf-admit-spawn.XXXXXX)"
  local l="$d/resume-${SID:0:8}.sh"; cp "$LAUNCHER_F" "$l"
  mkdir -p "$LR_STATE_DIR/$SID/bundle-20261018T070248Z"
  printf '%s\n' '{"ts":"2026-10-18T07:10:00Z","state":"recycle-armed","stage":"verdict","detail":"armed"}' \
                '{"ts":"2026-10-18T07:12:00Z","state":"STRANDED","stage":"verdict","detail":"proven=no"}' \
    > "$LR_STATE_DIR/$SID/bundle-20261018T070248Z/events.jsonl"
  run bash "$HF" --prompt-file "$PF" --launcher "$l" --cwd "$BATS_TEST_TMPDIR" --dry-run
  /bin/rm -f "$l"; /bin/rmdir "$d"
  echo "$output"
  [ "$status" -eq 2 ]
  [[ "$output" == *"STRANDED"*"lr-fleet --one ${SID:0:8}"* ]] || false
}

@test "CONTROL: the same /tmp launcher with no STRANDED record, or a newer bundle that verified, is not refused by this rule" {
  local d; d="$(mktemp -d /tmp/hf-admit-spawn.XXXXXX)"
  local l="$d/resume-${SID:0:8}.sh"; cp "$LAUNCHER_F" "$l"
  run bash "$HF" --prompt-file "$PF" --launcher "$l" --cwd "$BATS_TEST_TMPDIR" --dry-run
  local s1="$status"
  mkdir -p "$LR_STATE_DIR/$SID/bundle-20261018T070248Z" "$LR_STATE_DIR/$SID/bundle-20261018T082504Z"
  echo '{"state":"STRANDED","stage":"verdict"}' > "$LR_STATE_DIR/$SID/bundle-20261018T070248Z/events.jsonl"
  echo '{"state":"MOVED","stage":"verdict"}'    > "$LR_STATE_DIR/$SID/bundle-20261018T082504Z/events.jsonl"
  run bash "$HF" --prompt-file "$PF" --launcher "$l" --cwd "$BATS_TEST_TMPDIR" --dry-run
  /bin/rm -f "$l"; /bin/rmdir "$d"
  [ "$s1" -eq 0 ]
  [ "$status" -eq 0 ]
}
