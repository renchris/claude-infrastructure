#!/usr/bin/env bats
# handoff-fire.sh --recycle: THE INTENT ROW (2026-08-17, backlog 112d13aa0018 arm (c)).
#
# THE DEFECT. Every recycle class — recycle-engaged / recycle-unverified / recycle-dead — is emitted
# from inside the detached `__recycle` re-exec. So the only recycles that ever reached
# handoffs.jsonl were the ones that got far enough to detach a watcher AND have that watcher reach a
# verdict. An attempt that died before the detach left no row of ANY class, which makes the
# announced-vs-fired rate unmeasurable in both directions: a recycle that was never attempted and one
# that was attempted and lost are byte-identical in the store — both are silence. The filing row's
# own words: "until (c) lands no claim about recycle compliance is verifiable in either direction."
#
# WHY THIS SUITE DRIVES A REAL (NON-DRY) RECYCLE, WHICH NO OTHER RECYCLE SUITE DOES. `--dry-run`
# returns before recycle_fire is ever called, so a dry test cannot observe this row at all. The drive
# below is made safe by CONSTRUCTION rather than by flags: the pane id is a fabricated UUID that no
# terminal owns, so `as_tty` resolves nothing and recycle_fire aborts at its first exit path — which
# is upstream of every keystroke, every detach, and every /exit. Nothing is typed anywhere. That
# abort is also precisely the state under test: an attempt that died before the detach.

setup() {
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_SRC/scripts/handoff-fire.sh"
  [ -f "$HF" ] || { echo "subject missing: $HF" >&2; return 1; }

  # M11: the environment is PINNED, not ambient — the capacity/headroom gates read the box's real
  # loadavg and memory, so leaving them live makes this suite's verdict a function of machine load.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP=off
  # The account sweep is off above, but its three seams default to REAL machine paths — the stamp in
  # /tmp, the operator's deployed claude-accounts, and the shared heal-lock prefix. A suite that
  # leaves them unpinned reads live fleet state (test-hermeticity-lint 5a/5b). An ABSENT path is the
  # right pin here: every one of these sensors fails open on a miss.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/no-such-sweep-stamp.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/no-such-heal-lock-"

  export H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H/.claude/bin"
  export HOME="$H"
  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SHIM/osascript"
  chmod +x "$SHIM/osascript"
  export PATH="$SHIM:$PATH"

  # An it2 that enumerates NOTHING. The pane the drive names cannot be resolved, so recycle_fire
  # aborts before it can act on any terminal — see the header.
  cat > "$H/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
case "$1 $2" in
  "session list") [ "${3:-}" = --json ] && printf '[]\n'; exit 0 ;;
esac
exit 0
SH
  chmod +x "$H/.claude/bin/it2"
  export IT2_BIN="$H/.claude/bin/it2"

  # PIN THE TERMINAL, same reason as tests/handoff-recycle-engagement.bats: handoff-fire's primitives
  # branch on it, and an inherited KITTY_* from the developer's own pane would send an iTerm2 UUID
  # into kitty's numeric id space and change which code path this suite measures.
  unset KITTY_WINDOW_ID; unset CC_TERM; export IT2_WRAPPER_NO_KITTY=1
  # This repo INJECTS this into every pane it launches, so leaving it set would make the suite behave
  # one way from a fired pane and another from a bare shell (memory: the hermeticity lint says never
  # reach for the allowlist — unset the variable instead).
  unset CC_PANE_CMD_INTERACTIVE

  PANE_UUID="AAAAAAAA-0000-0000-0000-0000000000FF"
  export SID_ENV="w1t0p0:$PANE_UUID"
  PF="$BATS_TEST_TMPDIR/brief.md"; printf 'body\n' > "$PF"
  LOG="$H/.claude/logs/handoffs.jsonl"
}

drive_recycle() { # a real --recycle that cannot resolve its pane → aborts before the detach
  run env ITERM_SESSION_ID="$SID_ENV" timeout 90 \
      bash "$HF" --prompt-file "$PF" --launcher claude-test --recycle
}

@test "an attempt that dies BEFORE the detach still leaves a row — the denominator that did not exist" {
  drive_recycle
  # The abort is the state under test: recycle_fire got as far as resolving the pane and gave up.
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -q "not found in iTerm2"
  [ -f "$LOG" ] || { echo "no handoffs.jsonl at all — the attempt left NOTHING"; false; }
  grep -q '"class":"recycle-intent"' "$LOG" \
    || { echo "no recycle-intent row for an attempt that aborted pre-detach:"; cat "$LOG"; false; }
  # ...and no OUTCOME row was invented for a recycle whose outcome nothing observed. An intent row
  # that also claimed a verdict would be worse than the silence it replaces.
  ! grep -qE '"class":"recycle-(engaged|dead|unverified)"' "$LOG" \
    || { echo "an outcome row appeared for an attempt that never detached a watcher:"; cat "$LOG"; false; }
}

@test "the intent row asserts nothing about engagement — the field is ABSENT, never false" {
  # The emitter's own header records why: hard-coding engaged:false on a row nothing has measured
  # publishes a measured-negative into the engagement rate's numerator. `engaged` is omitted entirely
  # when null, so its ABSENCE is the assertion.
  drive_recycle
  grep '"class":"recycle-intent"' "$LOG" | tail -1 \
    | jq -e 'has("engaged")|not' >/dev/null \
    || { echo "the intent row carries an engaged verdict it never measured:"; grep '"class":"recycle-intent"' "$LOG"; false; }
}

@test "the intent row carries firing_sid — the join key the outcome rows structurally cannot have" {
  # Outcome rows are emitted from the detached __recycle re-exec, where FIRING_SID is never assigned,
  # so every one of them carries firing_sid:null by construction. This row runs in the PARENT. That
  # asymmetry is what lets a census pair an attempt with its outcome instead of counting two piles.
  drive_recycle
  grep '"class":"recycle-intent"' "$LOG" | tail -1 \
    | jq -e --arg p "$PANE_UUID" '.firing_sid==$p and .target_pane==$p and .gate=="recycle"' >/dev/null \
    || { echo "intent row is missing its parent-side identity:"; grep '"class":"recycle-intent"' "$LOG"; false; }
}
