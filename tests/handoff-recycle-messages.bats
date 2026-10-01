#!/usr/bin/env bats
# handoff-fire.sh --recycle: messages that say what the probe actually saw, and an outcome row on
# every abort (husk panes 2026-09-30, docs/research/husk-panes-2026-09-30.md root cause 9, fix F-e).
#
# THREE DEFECTS:
#   1. The terminal recycle-dead alarm asserted "the /exit landed … this pane now holds NO claude"
#      whatever its own probe had just read — including `cc` (claude STILL RUNNING) and `unknown`
#      (an abstention). rcy_dead_claim now chooses the sentence by verdict.
#   2. An UNREADABLE composer (recycle_composer_gate rc 2) was logged as recycle-held-draft with the
#      literal "<unreadable>" as the draft, and the operator was told to send or clear it. It is now
#      recycle-held-unreachable, with a message that says it is not a draft.
#   3. Several exit-1 paths after the recycle-intent row wrote no outcome row (pane 3 at 02:36:07Z: a
#      resolver rc 3 abort), so an aborted recycle was indistinguishable from one still in flight.
# The drives below are made safe by construction: fabricated pane ids no terminal owns, a recording
# it2 stub under a hermetic $HOME, and aborts that sit upstream of every keystroke.

setup() {
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_SRC/scripts/handoff-fire.sh"
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off HANDOFF_ACCOUNT_SWEEP=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/no-such-sweep-stamp.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/no-such-heal-lock-"
  export H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H/.claude/bin"
  export HOME="$H"
  export CC_HANDOFF_ALARM_DIR="$H/.claude/handoff-alarms"
  export WRAP_DOD_DIR="$BATS_TEST_TMPDIR/dod"; mkdir -p "$WRAP_DOD_DIR"
  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SHIM/osascript"; chmod +x "$SHIM/osascript"
  export PATH="$SHIM:$PATH"
  export CC_NOTIFY_BIN="$H/.claude/bin/cc-notify"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/paged.txt"\n' "$H" > "$CC_NOTIFY_BIN"; chmod +x "$CC_NOTIFY_BIN"
  export STUB_PANE="RECY-MSG-PANE"
  cat > "$H/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
case "$1 $2" in
  "session list")
    if [ "${3:-}" = --json ]; then printf '[{"id": "%s", "tty": "/dev/ttys999"}]\n' "${STUB_PANE:-RECY-MSG-PANE}"
    else printf '%s\n' "${STUB_PANE:-RECY-MSG-PANE}"; fi
    exit 0 ;;
esac
exit 0
SH
  chmod +x "$H/.claude/bin/it2"
  export IT2_BIN="$H/.claude/bin/it2"
  unset KITTY_WINDOW_ID CC_TERM CC_PANE_CMD_INTERACTIVE
  export IT2_WRAPPER_NO_KITTY=1
  CMDFILE="$BATS_TEST_TMPDIR/relaunch.cmd"; printf 'claude --permission-mode auto\n' > "$CMDFILE"
  export CMDFILE
  LOG="$H/.claude/logs/handoffs.jsonl"
  PF="$BATS_TEST_TMPDIR/brief.md"; printf 'body\n' > "$PF"
}

xf() { local pat; pat='/^'"$1"'() {/,/^}/p'; eval "$(sed -n "$pat" "$HF")"; }
alarms() { cat "$CC_HANDOFF_ALARM_DIR"/*.json 2>/dev/null || true; }
classes() { jq -r '.class' "$LOG" 2>/dev/null || true; }

@test "rcy_dead_claim cc: the /exit did NOT land and the session is alive — never 'holds NO claude'" {
  xf rcy_dead_claim
  run rcy_dead_claim cc 600 'claude3 --resume x'
  [[ "$output" == *"did NOT land"* ]] || false
  [[ "$output" == *"STILL RUNNING"* ]] || false
  [[ "$output" != *"holds NO claude"* ]] || false
  [[ "$output" != *"claude3 --resume x"* ]] || false     # no relaunch line over a live session
}

@test "rcy_dead_claim shell: the /exit landed, the pane holds no claude, relaunch it here" {
  xf rcy_dead_claim
  run rcy_dead_claim shell 600 'claude3 --resume x'
  [[ "$output" == *"holds NO claude"* ]] || false
  [[ "$output" == *"Relaunch manually in that pane: claude3 --resume x"* ]] || false
}

@test "rcy_dead_claim unknown: an ABSTENTION, never the claim that claude exited" {
  xf rcy_dead_claim
  run rcy_dead_claim unknown 600 'claude3 --resume x'
  [[ "$output" == *"ABSTENTION"* ]] || false
  [[ "$output" != *"holds NO claude"* ]] || false
  [[ "$output" == *"Relaunch manually only if it is at a shell prompt"* ]] || false
}

@test "the recycle-dead ALARM for an unreadable pane carries the abstention, not 'holds NO claude'" {
  HF_RECYCLE_SHELL_WAIT_S=3 run bash "$HF" __recycle "$STUB_PANE" "$BATS_TEST_TMPDIR/no-such-tty" "$CMDFILE" "$BATS_TEST_TMPDIR"
  [ "$status" -ne 0 ]
  run alarms
  [[ "$output" == *"HANDOFF-RECYCLE-DEAD"* ]] || false
  [[ "$output" == *"ABSTENTION"* ]] || false
  [[ "$output" != *"holds NO claude"* ]] || false
}

@test "rcy_composer_unreadable: an unreadable composer is recycle-held-unreachable, and says it is NOT a draft" {
  emit_recycle_event() { printf '%s|%s\n' "$1" "$4" >> "$BATS_TEST_TMPDIR/rows"; }
  xf rcy_composer_unreadable
  SID=P1 CMD=claude3 run rcy_composer_unreadable gate
  [[ "$output" == *"NOT a draft"* ]] || false
  [[ "$output" != *"Clear/send the draft"* ]] || false
  SID=P1 CMD=claude3 run rcy_composer_unreadable fresh
  [[ "$output" == *"not a draft"* ]] || false
  run cat "$BATS_TEST_TMPDIR/rows"
  [ "$(grep -c '^recycle-held-unreachable|' "$BATS_TEST_TMPDIR/rows")" -eq 2 ]
  [ "$(grep -c '^recycle-held-draft' "$BATS_TEST_TMPDIR/rows")" -eq 0 ]
}

@test "no recycle path turns an unreadable composer into a '<unreadable>' draft any more" {
  # Both composer-gate sites used to assign rcy_cg_c="<unreadable>" and emit recycle-held-draft.
  run grep -c 'rcy_cg_c="<unreadable>"' "$HF"
  [ "$output" = 0 ]
}

@test "hf_recycle_last_read: an unreadable composer refuses with reason 'unreachable', not 'draft'" {
  recycle_composer_gate() { return 2; }
  xf hf_recycle_last_read
  if RCY_REMOTE=0 RCY_IT2=x SID=P1 hf_recycle_last_read; then false; fi
  [ "$HF_LR_REASON" = unreachable ]
}

@test "an aborted recycle whose pane the resolver says is GONE leaves an outcome row" {
  run env ITERM_SESSION_ID="w1t0p0:AAAAAAAA-0000-0000-0000-0000000000FE" timeout 90 \
      bash "$HF" --prompt-file "$PF" --launcher claude-test --recycle
  [ "$status" -ne 0 ]
  run classes
  [[ "$output" == *"recycle-intent"* ]] || false
  [[ "$output" == *"recycle-refused-no-pane"* ]] || false
}

@test "a resolver that never answers (rc 3) leaves recycle-held-unreachable — pane 3, 02:36:07Z" {
  printf '99\n' > "$BATS_TEST_TMPDIR/ttyfail"
  run env ITERM_SESSION_ID="w1t0p0:AAAAAAAA-0000-0000-0000-0000000000FD" HANDOFF_TTY_FAIL_FILE="$BATS_TEST_TMPDIR/ttyfail" \
      HANDOFF_TTY_RETRIES=1 timeout 90 bash "$HF" --prompt-file "$PF" --launcher claude-test --recycle
  [ "$status" -ne 0 ]
  [[ "$output" == *"resolver CANNOT TELL"* ]] || false
  run classes
  [[ "$output" == *"recycle-held-unreachable"* ]] || false
}

@test "the reconciler maps the new held reason to a re-probed composer hold" {
  run python3 -c "import sys; sys.path.insert(0, '$REPO_SRC/scripts/limit-recover'); from lr_recon import settle; print(settle.RCY_HELD_SUB.get('unreachable'))"
  [ "$output" = HOLD-COMPOSER ]
}
