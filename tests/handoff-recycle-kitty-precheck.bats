#!/usr/bin/env bats
# Pane-lifecycle fixes 2026-10-01, item 4 (docs/plans/pane-lifecycle-fixes-2026-10-01.md; evidence
# docs/research/recycle-unreachable-2026-10-01.md and the 2026-10-01 live capture in
# docs/research/husk-panes-2026-09-30.md).
#
# On 2026-10-01 eight --recycle runs aborted on a kitty control socket that did not answer, each after
# minutes (pane 19: 12.5 min, 11.7 of them before its intent row, unattributed). Now:
#   a. the self pane's tty comes from this process's own ancestry once the pane is PROVEN ours;
#   b. every recycle row carries `phases` (name@seconds) and `elapsed_s`;
#   c. one up-front probe (~15 s) holds the recycle BEFORE the intent row: `recycle-held-wedged` plus
#      an operator step when the accept queue is full (only a kitty restart clears that), else
#      `recycle-held-unreachable`;
#   d. a held recycle leaves a durable `recycle` row in the pane-close queue.

setup() {
  command -v jq >/dev/null || skip "jq required"
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_SRC/scripts/handoff-fire.sh"
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/no-such-sweep-stamp.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/no-such-heal-lock-"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"
  export CC_HANDOFF_ALARM_DIR="$HOME/.claude/handoff-alarms"
  export WRAP_DOD_DIR="$BATS_TEST_TMPDIR/dod"; mkdir -p "$WRAP_DOD_DIR"
  export CC_PANE_CLOSE_QUEUE_DIR="$BATS_TEST_TMPDIR/pcq"
  export CC_BACKLOG_BIN="$BATS_TEST_TMPDIR/backlog-stub"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/backlog-calls.log"\n' "$BATS_TEST_TMPDIR" > "$CC_BACKLOG_BIN"
  chmod +x "$CC_BACKLOG_BIN"
  # kitty identity, a socket path nothing listens on, and a netstat capture standing in for the box.
  unset KITTY_WINDOW_ID KITTY_LISTEN_ON KITTY_PID CC_PANE_CMD_INTERACTIVE
  export CC_TERM=kitty
  SOCK="$BATS_TEST_TMPDIR/kitty-610"
  export CC_TERM_KITTY_TO="unix:$SOCK"
  export CC_HF_NETSTAT_FILE="$BATS_TEST_TMPDIR/netstat.txt"
  LOG="$HOME/.claude/logs/handoffs.jsonl"
  PF="$BATS_TEST_TMPDIR/brief.md"; printf 'body\n' > "$PF"
}

netstat_capture() { # $1=queued rows on the socket with unread data
  { echo "Active LOCAL (UNIX) domain sockets"
    echo "Address Type Recv-Q Send-Q Inode Conn Refs Nextref rxbytes txbytes rhiwat shiwat pid epid state options gencnt flags flags1 usecnt rtncnt fltrs Addr"
    echo "a0 stream 0 0 9b64 0 0 0 0 0 8192 8192 610 0 00000 2 b56a 8000 0 1 0 000000 $SOCK"
    local i; for ((i = 0; i < $1; i++)); do
      echo "q$i stream 101 0 0 0 0 0 0 0 8192 8192 0 0 00102 0 bccc 8001 0 2 0 000000 $SOCK"
    done
    echo "z9 stream 101 0 0 0 0 0 0 0 8192 8192 0 0 00102 0 bccc 8001 0 2 0 000000 /tmp/some-other.sock"
  } > "$CC_HF_NETSTAT_FILE"
}
recycle() { run env timeout 90 bash "$HF" --prompt-file "$PF" --launcher claude-test --session-id 77 --recycle "$@"; }
classes() { jq -r '.class' "$LOG" 2>/dev/null || true; }
row_of() { jq -c --arg c "$1" 'select(.class == $c)' "$LOG" | tail -1; }

# ── c + d, end to end ────────────────────────────────────────────────────────────────────────────

@test "STUCK socket (accept queue full): held before the intent row, operator step filed, owed row written" {
  netstat_capture 128
  recycle
  [ "$status" -eq 1 ] || { echo "rc=$status"; echo "$output"; false; }
  [[ "$output" == *"control socket is STUCK"* ]] || { echo "$output"; false; }
  run classes
  [[ "$output" == *"recycle-held-wedged"* ]] || { echo "$output"; false; }
  [[ "$output" != *"recycle-intent"* ]] || { echo "an intent row was written for a recycle that never started"; false; }
  grep -qF "needs restart kitty (control socket stuck: queue full) --class needs-human --falsifier test ! -S $SOCK" "$BATS_TEST_TMPDIR/backlog-calls.log"
  [ -s "$CC_PANE_CLOSE_QUEUE_DIR/recycle-77.json" ] || { ls -la "$CC_PANE_CLOSE_QUEUE_DIR"; false; }
  [[ "$(jq -r .argv "$CC_PANE_CLOSE_QUEUE_DIR/recycle-77.json")" == *"--recycle"* ]] || false
  [ "$(jq -r .kitty_sock "$CC_PANE_CLOSE_QUEUE_DIR/recycle-77.json")" = "$SOCK" ] || false
}

@test "NOT ANSWERING, queue not full: recycle-held-unreachable, no operator step, owed row written" {
  netstat_capture 3
  recycle
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"kitty is not answering"* ]] || { echo "$output"; false; }
  [[ "$output" == *"run it bare"* ]] || false
  run classes
  [[ "$output" == *"recycle-held-unreachable"* ]] || false
  [[ "$output" != *"recycle-intent"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/backlog-calls.log" ] || { echo "filed an operator step for a merely slow kitty"; false; }
  [ -s "$CC_PANE_CLOSE_QUEUE_DIR/recycle-77.json" ] || false
}

@test "b: the held row carries per-phase timing" {
  netstat_capture 128
  recycle
  r="$(row_of recycle-held-wedged)"
  [[ "$(jq -r .phases <<<"$r")" == *"gates@"*"kitty-probe@"* ]] || { echo "$r"; false; }
  [[ "$(jq -r '.elapsed_s | type' <<<"$r")" == number ]] || { echo "$r"; false; }
}

@test "--dry-run only reports a deaf kitty: no row, no operator step, no owed row" {
  netstat_capture 128
  recycle --dry-run
  [[ "$output" == *"a real run would be HELD here"* ]] || { echo "$output"; false; }
  run classes
  [[ "$output" != *"recycle-held-wedged"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/backlog-calls.log" ] || false
  [ ! -e "$CC_PANE_CLOSE_QUEUE_DIR/recycle-77.json" ] || false
}

@test "CONTROL: CC_RECYCLE_KITTY_PRECHECK=0 restores the old path (no up-front hold)" {
  netstat_capture 128
  recycle_off() { run env CC_RECYCLE_KITTY_PRECHECK=0 timeout 90 bash "$HF" --prompt-file "$PF" --launcher claude-test --session-id 77 --recycle; }
  recycle_off
  run classes
  [[ "$output" != *"recycle-held-wedged"* ]] || false
}

# ── units ────────────────────────────────────────────────────────────────────────────────────────

load_units() {
  # hf_kitty_queue_depth moved to scripts/lib/kitty-queue.sh (W3 P5); the subject sources it from there.
  . "$REPO_SRC/scripts/lib/kitty-queue.sh"
  eval "$(sed -n '/^hf_recycle_kitty_precheck() {/,/^}/p;/^hf_self_kitty_tty() {/,/^}/p;/^hf_phase() {/,/^}/p' "$HF")"
}

@test "queue depth counts only rows ON this socket that hold unread data" {
  load_units; netstat_capture 5
  [ "$(hf_kitty_queue_depth "unix:$SOCK")" = 5 ] || false   # the listener (Recv-Q 0) and another socket do not count
}

@test "precheck: answering ⇒ 0 · refused + small queue ⇒ 1 · refused + full queue ⇒ 2" {
  load_units
  kitty_identity() { return 0; }
  kitty_socket_accepting() { [ "${ACC:-0}" = 1 ]; }
  kt() { [ "${LS_OK:-0}" = 1 ]; }
  netstat_capture 2
  ACC=1 LS_OK=1; rc=0; hf_recycle_kitty_precheck || rc=$?; [ "$rc" = 0 ] || false
  ACC=1 LS_OK=0; rc=0; hf_recycle_kitty_precheck || rc=$?; [ "$rc" = 1 ] || false
  [[ "$HF_KPROBE_WHY" == *"did not answer"* ]] || false
  ACC=0; rc=0; hf_recycle_kitty_precheck || rc=$?; [ "$rc" = 1 ] || false
  netstat_capture 128
  ACC=0; rc=0; hf_recycle_kitty_precheck || rc=$?; [ "$rc" = 2 ] || false
  [[ "$HF_KPROBE_WHY" == *"accept queue is full"* ]] || false
}

@test "a: the self tty is the tty of the ancestor whose parent is \$KITTY_PID, not the caller's" {
  load_units
  shim="$BATS_TEST_TMPDIR/psbin"; mkdir -p "$shim"
  # ancestry: $$ → 900 (claude, ttys030 under expect) → 800 (window root, ttys016) → kitty 700
  cat > "$shim/ps" <<SH
#!/bin/bash
pid="" want=""
while [ \$# -gt 0 ]; do case "\$1" in -p) pid="\$2"; shift 2 ;; -o) want="\$2"; shift 2 ;; *) shift ;; esac; done
case "\$want:\$pid" in
  ppid=:$$) echo 900 ;; ppid=:900) echo 800 ;; ppid=:800) echo 700 ;;
  tty=:900) echo ttys030 ;; tty=:800) echo ttys016 ;;
esac
SH
  chmod +x "$shim/ps"
  PATH="$shim:$PATH" KITTY_PID=700 run hf_self_kitty_tty
  [ "$output" = /dev/ttys016 ] || { echo "got '$output'"; false; }
  PATH="$shim:$PATH" KITTY_PID=12345 run hf_self_kitty_tty
  [ -z "$output" ] || { echo "a kitty pid that is not an ancestor produced '$output'"; false; }
}

@test "d: an owed row is spent by the next recycle that arms its watcher" {
  eval "$(sed -n '/^sc_pcq_load() {/,/^}/p;/^hf_recycle_owed_record() {/,/^}/p;/^hf_recycle_owed_clear() {/,/^}/p' "$HF")"
  cc_sid_for_pane() { printf 'sid-77'; }
  export HF_INVOKED_ARGS="--recycle " CC_PCQ_LIB="$REPO_SRC/scripts/lib/pane-close-queue.sh"
  hf_recycle_owed_record 77 "test" 2>/dev/null
  [ -s "$CC_PANE_CLOSE_QUEUE_DIR/recycle-77.json" ] || false
  hf_recycle_owed_clear 77
  [ ! -e "$CC_PANE_CLOSE_QUEUE_DIR/recycle-77.json" ] || false
}

@test "ONE WEDGE, ONE ROW: boot-resume's deaf page files the stuck-kitty row under the same step, class and falsifier" {
  # cc-backlog folds a re-file of the same step into the same row. If either title drifts, one wedged
  # kitty becomes two operator rows (W3 P5).
  title='restart kitty (control socket stuck: queue full)'
  grep -qF "hf_backlog_needs \"$title\" --class needs-human" "$HF"
  grep -qF "needs \"$title\" --class needs-human" "$REPO_SRC/scripts/boot-resume.sh"
  grep -qF -- '--falsifier "test ! -S $HF_KPROBE_SOCK"' "$HF"
  grep -qF -- '--falsifier "test ! -S $sock"' "$REPO_SRC/scripts/boot-resume.sh"
}
