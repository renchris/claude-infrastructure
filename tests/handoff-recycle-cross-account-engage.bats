#!/usr/bin/env bats
# W7e — a cross-account resume that ANSWERS is not a dead recycle.
#
# THE INCIDENT (2026-10-01 ~20:32Z). Sessions 89bdedfa and 8e18da3f were moved from
# .claude-quaternary to .claude-tertiary by lr-fire-resume. The launcher logged READY-NOT-SEEN and
# typed no prompt, so the run token never reached the transcript and the token-gated oracle
# (resume_engaged with $4) was rc 1 for all 180 s. The target copy meanwhile held real
# claude-opus-5-5 turns 35-60 s after the relaunch, and the watcher paged HANDOFF-RECYCLE-DEAD
# ("alive at an empty composer") over two sessions that were working.
#
# These cases drive the REAL __recycle watcher over the argv recycle_fire sends (the shape
# tests/lr-fire-resume-submit.bats:861 uses), with the source and target as two config dirs.

setup() {
  export CC_ADMIT_GATE=off CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/absent-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/absent-heal-"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfgdir"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_HANDOFF_ALARM_DIR="$BATS_TEST_TMPDIR/alarms"

  SLUG="-Users-x-thing"; SID="aaaa1111-0000-4000-8000-000000000001"
  SRC="$BATS_TEST_TMPDIR/src-account"; CFG="$BATS_TEST_TMPDIR/target-account"
  mkdir -p "$SRC/projects/$SLUG" "$CFG/projects/$SLUG"
  SRC_TX="$SRC/projects/$SLUG/$SID.jsonl"; TX="$CFG/projects/$SLUG/$SID.jsonl"
  T0="2026-09-19T21:02:00"
  TOK="run:aaaa1111:20260919T210200:9f3c2b71"
  # The transplanted history both copies share: a real turn from BEFORE the relaunch.
  OLD_TURN='{"type":"assistant","timestamp":"2026-09-19T21:01:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"before the limit"}]}}'
  NEW_TURN='{"type":"assistant","timestamp":"2026-09-19T21:02:40.000Z","message":{"role":"assistant","model":"claude-opus-5-5","content":[{"type":"text","text":"checking what is still in flight"}]}}'
  MAIL='{"type":"user","timestamp":"2026-09-19T21:02:30.000Z","message":{"role":"user","content":"<task-notification><summary>peer mail</summary></task-notification>"}}'
  watcher_setup
}

watcher_setup() {
  # The phase-aware `ps`, pane stub and run dir are tests/lr-fire-resume-submit.bats:803-858's.
  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  export PS_COUNT_FILE="$BATS_TEST_TMPDIR/ps-count"; rm -f "$PS_COUNT_FILE"
  cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
args="$*"
case "$args" in *pgid=*) printf '%s\n' "4242"; exit 0 ;; esac
case "$args" in *lstart=*) printf 'Tue Sep 29 10:00:00 2026\n'; exit 0 ;; esac
c="${PS_COUNT_FILE:?}"
if [ "${args#*-o pid= -t}" != "$args" ]; then
  n=$(( $(cat "$c" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$c"
else
  n=$(cat "$c" 2>/dev/null || echo 0)
fi
phase=alive; [ "$n" -le "${PS_DEAD_CALLS:-2}" ] && phase=shell
case "$args" in
  *"-o pid= -t"*)   printf '100\n'; [ "$phase" = alive ] && printf '200\n' ;;
  *"-o tpgid= -t"*) printf '100\n'; [ "$phase" = alive ] && printf '100\n' ;;
  *"-o comm= -t"*)  if [ "$phase" = alive ]; then printf 'claude\n'; else printf -- '-zsh\n'; fi ;;
  *pid=,ppid=*)     printf '100 1\n'; [ "$phase" = alive ] && printf '200 100\n' ;;
  *"pid=,comm= -g"*) printf '100 /bin/zsh\n' ;;
  *"-p 200"*)       printf '/Users/chrisren/.claude-220/node_modules/.bin/claude\n' ;;
  *"-p 100"*)       printf '/bin/zsh\n' ;;
esac
exit 0
SH
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SHIM/osascript"
  chmod +x "$SHIM/ps" "$SHIM/osascript"
  unset KITTY_WINDOW_ID; export IT2_WRAPPER_NO_KITTY=1; unset CC_TERM
  mkdir -p "$HOME/.claude/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$HOME/ccnotify-calls.log"\nexit 0\n' \
    > "$HOME/.claude/bin/cc-notify"
  PANE="RECY-PANE"; export STUB_PANE="$PANE"
  cat > "$HOME/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "session list")
    if [ "${3:-}" = --json ]; then printf '[{"id": "%s", "tty": "/dev/ttys999"}]\n' "${STUB_PANE:-RECY-PANE}"
    else printf '%s\n' "${STUB_PANE:-RECY-PANE}"; fi
    exit 0 ;;
  "session send") txt="${!#}"; [ "${#txt}" -gt 3 ] && printf '%s' "$txt" > "$HOME/it2-screen" ;;
  "session read") cat "$HOME/it2-screen" 2>/dev/null ;;
esac
exit 0
SH
  chmod +x "$HOME/.claude/bin/cc-notify" "$HOME/.claude/bin/it2"
  CMDF="$BATS_TEST_TMPDIR/cmd.sh"; printf 'cd /tmp && claude-x\n' > "$CMDF"
  RUNDIR="$BATS_TEST_TMPDIR/run"; mkdir -p "$RUNDIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_PROJECTS_DIRS="$BATS_TEST_TMPDIR/proj"; mkdir -p "$CC_PROJECTS_DIRS"
  export CC_ADMIT_IDL="$BATS_TEST_TMPDIR/absent-idl.jsonl"
}

run_watcher() { # $1 = the target cfg handed at argv position 10
  local -a argv
  mapfile -t argv < <(printf '%s\n' __recycle "$PANE" /dev/ttys999 "$CMDF" /tmp OLD-SID "" "" "" \
                        "$1" "$SID" "$T0" "" "$RUNDIR" "$TOK")
  run env HOME="$HOME" PATH="$SHIM:$PATH" IT2_BIN="$HOME/.claude/bin/it2" \
      PS_DEAD_CALLS=2 RCY_ENGAGE_TIMEOUT=3 RCY_ENGAGE_INTERVAL=1 \
      RCY_BOOT_PANE_EVERY=1 RCY_BOOT_IVL_S=0.2 RCY_BOOT_WAIT_S=20 \
      bash "$HF" "${argv[@]}"
}

rows() { cat "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null; }
dead_alarms() { grep -l 'HANDOFF-RECYCLE-DEAD' "$CC_HANDOFF_ALARM_DIR"/*.json 2>/dev/null | wc -l | tr -d ' '; }

@test "RED-PROOF cross-account: the launcher typed no prompt, the TARGET copy answers → ENGAGED, no dead page" {
  printf '%s\n' "$OLD_TURN" > "$SRC_TX"
  printf '%s\n' "$OLD_TURN" "$MAIL" "$NEW_TURN" > "$TX"
  printf '{"state":"READY-NOT-SEEN","stage":"inject","detail":"prompt NOT typed"}\n' > "$RUNDIR/events.jsonl"
  run_watcher "$CFG"
  [ "$status" -eq 0 ] || { echo "a session answering on its target was failed: $output"; false; }
  [[ "$output" == *"ENGAGEMENT CONFIRMED BY TRANSCRIPT in $PANE"* ]] || { echo "$output"; false; }
  [[ "$output" == *"READY-NOT-SEEN"* ]] || { echo "the line hid that no prompt was typed: $output"; false; }
  [[ "$output" != *"never engaged"* ]] || { echo "$output"; false; }
  rows | grep -F '"class":"recycle-engaged"' | grep -F 'without the relaunch prompt' >/dev/null \
    || { echo "no recycle-engaged row naming the proof:"; rows; false; }
  ! rows | grep -F '"class":"recycle-dead"' >/dev/null || { echo "a recycle-dead row was written:"; rows; false; }
  [ "$(dead_alarms)" = 0 ] || { echo "HANDOFF-RECYCLE-DEAD paged over a working session"; false; }
}

@test "RED-PROOF cross-account: a fresh turn in the SOURCE copy only is not engagement → still dead" {
  # The watcher must read the account the session was moved TO. A post-relaunch turn left in the
  # source copy (a stub the retired store re-created) is not this relaunch answering.
  printf '%s\n' "$OLD_TURN" "$NEW_TURN" > "$SRC_TX"
  printf '%s\n' "$OLD_TURN" > "$TX"
  run_watcher "$CFG"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"RECYCLE FAILED — never engaged"* ]] || { echo "$output"; false; }
  [[ "$output" != *"ENGAGEMENT CONFIRMED"* ]] || { echo "the source copy was read as the target: $output"; false; }
  rows | grep -F '"class":"recycle-dead"' >/dev/null || { echo "no recycle-dead row:"; rows; false; }
  [ "$(dead_alarms)" = 1 ] || { echo "a silent target was not paged: $(dead_alarms)"; false; }
}

@test "RED-PROOF cross-account: no readable target transcript → UNKNOWN, never recycle-dead" {
  printf '%s\n' "$OLD_TURN" "$NEW_TURN" > "$SRC_TX"
  local empty="$BATS_TEST_TMPDIR/target-with-no-copy"; mkdir -p "$empty/projects"
  run_watcher "$empty"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"engagement UNKNOWN: could not read transcript"* ]] || { echo "$output"; false; }
  [[ "$output" != *"never engaged"* ]] || { echo "an unread file was reported as a silent session: $output"; false; }
  rows | grep -F '"class":"recycle-unverified"' | grep -F 'unknown — could not read transcript' >/dev/null \
    || { echo "no unknown row:"; rows; false; }
  ! rows | grep -F '"class":"recycle-dead"' >/dev/null || { echo "a recycle-dead row was written:"; rows; false; }
  [ "$(dead_alarms)" = 0 ] || { echo "HANDOFF-RECYCLE-DEAD paged over an unread transcript"; false; }
}
