#!/usr/bin/env bats
# shellcheck disable=SC2329  # every stub here is invoked by the functions extracted from handoff-fire.sh
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
  eval "$(sed -n '/^hf_recycle_kitty_precheck() {/,/^}/p;/^hf_recycle_kitty_probe() {/,/^}/p;/^hf_self_kitty_tty() {/,/^}/p;/^hf_phase() {/,/^}/p;/^hf_kprobe_connect_say() {/,/^}/p;/^hf_kprobe_detail() {/,/^}/p;/^kitty_socket_accepting() {/,/^}/p;/^hf_bounded_s() {/,/^}/p' "$HF")"
  export HF_TIMEOUT_BIN=""
}

# A real AF_UNIX socket at $1, bound RELATIVE (the test dir is past Darwin's 104-byte sun_path cap):
# listening=1 keeps a listener alive in the background, listening=0 binds and exits (a leftover file).
fixture_socket() { # $1=path $2=listening (1|0)
  ( cd "$(dirname "$1")" && /usr/bin/python3 -c '
import os, socket, sys, time
d, b = os.path.split(os.path.abspath(sys.argv[1])); os.chdir(d)
s = socket.socket(socket.AF_UNIX); s.bind(b)
if sys.argv[2] == "1":
    s.listen(5)
open(sys.argv[1] + ".ready", "w").close()
if sys.argv[2] == "1":
    time.sleep(60)
' "$(basename "$1")" "$2" ) >/dev/null 2>&1 3>&- &
  [ "$2" = 1 ] && echo "$!" >> "$BATS_TEST_TMPDIR/listeners.pid"
  # Wait for the marker written AFTER listen(): the socket file appears at bind(), and a connect in
  # between is refused. Up to 300 s: at load ~64/core one python start-up took ~130 s (2026-10-18).
  local n=0; while [ ! -e "$1.ready" ] && [ "$n" -lt 3000 ]; do sleep 0.1; n=$((n + 1)); done
  [ "$2" = 1 ] || wait "$!" 2>/dev/null || true
  [ -e "$1.ready" ] || { echo "fixture socket $1 never became ready" >&2; return 1; }
}
teardown() {
  local p
  if [ -f "$BATS_TEST_TMPDIR/listeners.pid" ]; then
    while read -r p; do kill "$p" 2>/dev/null || true; done < "$BATS_TEST_TMPDIR/listeners.pid"
  fi
  return 0
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

# ── K2 (lr-inplace-immediacy 2026-10-18): the probe says WHICH failure it was ─────────────────────
# 43e6eb4b held on "did not accept a connection (0 queued)": one rc for five causes, and a 0 that a
# failed netstat would also have printed. RED on the unfixed tree: every failure exited 1, and a
# failing netstat read 0.

@test "K2 kitty_socket_accepting: 0 listening · 3 refused (a leftover file) · 4 no such socket · 5 another OSError" {
  load_units
  d="$BATS_TEST_TMPDIR/k"; mkdir -p "$d"
  fixture_socket "$d/live" 1
  fixture_socket "$d/dead" 0
  rc=0; kitty_socket_accepting "unix:$d/live" || rc=$?; [ "$rc" = 0 ] || { echo "listening: rc=$rc"; false; }
  rc=0; kitty_socket_accepting "unix:$d/dead" || rc=$?; [ "$rc" = 3 ] || { echo "refused: rc=$rc"; false; }
  rc=0; kitty_socket_accepting "unix:$d/absent" || rc=$?; [ "$rc" = 4 ] || { echo "absent: rc=$rc"; false; }
  # A basename past Darwin's 104-byte sun_path cap: connect raises a plain OSError, not a refusal.
  long="$(printf 'x%.0s' $(seq 1 120))"
  rc=0; kitty_socket_accepting "unix:$d/$long" || rc=$?; [ "$rc" = 5 ] || { echo "other: rc=$rc"; false; }
  rc=0; kitty_socket_accepting "tcp:localhost:1" || rc=$?; [ "$rc" = 1 ] || { echo "not probed: rc=$rc"; false; }
}

@test "K2 the precheck names the connect failure, and its bound firing reads 'could not tell'" {
  load_units
  kitty_identity() { return 0; }
  kt() { return 1; }
  netstat_capture 2
  for c in 3:"connection refused" 4:"no such socket" 5:"failed another way" 124:"bound fired (rc 124), so it could not tell" 137:"bound fired (rc 137)"; do
    CRC="${c%%:*}"; kitty_socket_accepting() { return "$CRC"; }
    rc=0; hf_recycle_kitty_precheck || rc=$?
    [ "$rc" = 1 ] || { echo "rc $CRC: precheck rc=$rc"; false; }
    [[ "$HF_KPROBE_WHY" == *"${c#*:}"* ]] || { echo "rc $CRC: $HF_KPROBE_WHY"; false; }
    [ "$(hf_kprobe_detail)" = "connect_rc=$CRC ls_rc=- queue=2" ] || { echo "rc $CRC: $(hf_kprobe_detail)"; false; }
  done
  kitty_socket_accepting() { return 0; }
  rc=0; hf_recycle_kitty_precheck || rc=$?
  [ "$rc" = 1 ] && [ "$(hf_kprobe_detail)" = "connect_rc=0 ls_rc=1 queue=2" ] || { hf_kprobe_detail; false; }
}

@test "K2 a failing netstat reads '?', never 0, and '?' is never full" {
  load_units
  unset CC_HF_NETSTAT_FILE
  shim="$BATS_TEST_TMPDIR/nsbin"; mkdir -p "$shim"
  printf '#!/bin/bash\nexit 1\n' > "$shim/netstat"; chmod +x "$shim/netstat"
  PATH="$shim:$PATH" run hf_kitty_queue_depth "unix:$SOCK"
  [ "$output" = "?" ] || { echo "a failed netstat read '$output'"; false; }
  # The precheck: unknown is not STUCK (rc 1, not 2) and says so.
  kitty_identity() { return 0; }
  kitty_socket_accepting() { return 3; }
  rc=0; PATH="$shim:$PATH" hf_recycle_kitty_precheck || rc=$?
  [ "$rc" = 1 ] || { echo "rc=$rc $HF_KPROBE_WHY"; false; }
  [[ "$HF_KPROBE_WHY" == *"queue unreadable: netstat failed"* ]] || { echo "$HF_KPROBE_WHY"; false; }
  [[ "$(hf_kprobe_detail)" == *"queue=?"* ]] || false
  # kq_deaf: an unread queue is not provably deaf, so sample is never even asked.
  printf '#!/bin/bash\necho called >> "%s/sample-calls"\necho "Thread_1 main"\n' "$BATS_TEST_TMPDIR" > "$shim/sample"; chmod +x "$shim/sample"
  rc=0; out="$(PATH="$shim:$PATH" CC_KQ_SAMPLE_BIN="$shim/sample" kq_deaf "unix:$SOCK" 610)" || rc=$?
  [ "$rc" = 1 ] || { echo "kq_deaf rc=$rc: $out"; false; }
  [[ "$out" == *"unreadable (netstat failed): not provably deaf"* ]] || { echo "$out"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/sample-calls" ] || { echo "sampled kitty over an unread queue"; false; }
}

@test "K2 the held row names the connect rc, the ls rc and the queue reading" {
  netstat_capture 3
  # Unbounded connect: on a loaded box python's start-up alone outlasts the 3 s bound, and the row
  # then honestly says rc 124 — measured while writing this case. The absent socket is what is pinned.
  # A longer outer bound than recycle()'s 90 s, for the same reason: at load ~57/core this run was killed.
  run env CC_KITTY_CONNECT_TIMEOUT_S=0 timeout 300 bash "$HF" --prompt-file "$PF" --launcher claude-test --session-id 77 --recycle
  [ "$status" -eq 1 ] || { echo "status=$status $output"; false; }
  r="$(row_of recycle-held-unreachable)"
  [[ "$(jq -r .detail <<<"$r")" == *"no such socket (rc 4)"*"[connect_rc=4 ls_rc=- queue=3 tries=1]"* ]] || { echo "$r"; false; }
}

# ── K1 (lr-inplace-immediacy 2026-10-18): a DETACHED caller asks again before it holds ───────────────
# 43e6eb4b held on one 3 s probe after ~13 min of work; the same kitty answered 48 s later. RED on the
# unfixed tree: hf_recycle_kitty_probe does not exist, and the recycle asked exactly once.

@test "K1 refused twice, then answering: a detached caller proceeds on the 3rd attempt; an interactive one holds after 1" {
  load_units
  kitty_identity() { return 0; }
  kt() { return 0; }
  netstat_capture 2
  CNT="$BATS_TEST_TMPDIR/connects"; : > "$CNT"
  kitty_socket_accepting() { echo x >> "$CNT"; [ "$(wc -l < "$CNT")" -ge 3 ] || return 3; }
  rc=0; LR_INPLACE_AWAIT=0 HF_KPROBE_SLEEP_SCALE=0 hf_recycle_kitty_probe 2>"$BATS_TEST_TMPDIR/err" || rc=$?
  [ "$rc" = 0 ] || { echo "rc=$rc $HF_KPROBE_WHY"; cat "$BATS_TEST_TMPDIR/err"; false; }
  [ "$HF_KPROBE_TRIED" = 3 ] || { echo "tried=$HF_KPROBE_TRIED"; false; }
  [ "$(grep -c 'asking again in' "$BATS_TEST_TMPDIR/err")" = 2 ] || { cat "$BATS_TEST_TMPDIR/err"; false; }
  grep -q 'asking again in 10s' "$BATS_TEST_TMPDIR/err" || { cat "$BATS_TEST_TMPDIR/err"; false; }
  : > "$CNT"
  rc=0; hf_recycle_kitty_probe 2>/dev/null || rc=$?
  [ "$rc" = 1 ] && [ "$HF_KPROBE_TRIED" = 1 ] && [ "$(wc -l < "$CNT" | tr -d ' ')" = 1 ] \
    || { echo "interactive: rc=$rc tried=$HF_KPROBE_TRIED connects=$(wc -l < "$CNT")"; false; }
}

@test "K1 STUCK holds at once even when detached; 5 attempts, the budget and HF_KPROBE_TRIES bound the asking" {
  load_units
  kitty_identity() { return 0; }
  kitty_socket_accepting() { return 3; }
  # shellcheck disable=SC2034  # dynamic scope: the extracted probe reads both
  local HF_KPROBE_SLEEP_SCALE=0 LR_INPLACE_AWAIT=0
  netstat_capture 128
  rc=0; hf_recycle_kitty_probe 2>/dev/null || rc=$?
  [ "$rc" = 2 ] || { echo "stuck: rc=$rc tried=$HF_KPROBE_TRIED"; false; }
  [ "$HF_KPROBE_TRIED" = 1 ] || { echo "stuck: rc=$rc tried=$HF_KPROBE_TRIED"; false; }
  netstat_capture 2
  rc=0; hf_recycle_kitty_probe 2>/dev/null || rc=$?
  [ "$rc" = 1 ] || { echo "5 max: rc=$rc tried=$HF_KPROBE_TRIED"; false; }
  [ "$HF_KPROBE_TRIED" = 5 ] || { echo "5 max: rc=$rc tried=$HF_KPROBE_TRIED"; false; }
  [[ "$HF_KPROBE_WHY" == *"after 5 attempt(s) over"* ]] || { echo "$HF_KPROBE_WHY"; false; }
  # Budget 12 s: attempt 2 starts at +5, attempt 3 at +15 would pass it, so 2 attempts.
  rc=0; HF_KPROBE_BUDGET_S=12 hf_recycle_kitty_probe 2>/dev/null || rc=$?
  [ "$HF_KPROBE_TRIED" = 2 ] || { echo "budget: tried=$HF_KPROBE_TRIED"; false; }
  rc=0; HF_KPROBE_TRIES=1 hf_recycle_kitty_probe 2>/dev/null || rc=$?
  [ "$HF_KPROBE_TRIED" = 1 ] || { echo "TRIES=1: tried=$HF_KPROBE_TRIED"; false; }
  rc=0; LR_INPLACE_AWAIT=1 HF_KPROBE_TRIES=3 hf_recycle_kitty_probe 2>/dev/null || rc=$?
  [ "$HF_KPROBE_TRIED" = 3 ] || { echo "TRIES=3 interactive: tried=$HF_KPROBE_TRIED"; false; }
}

@test "K1 end to end: a detached recycle asks 5 times before its held row; the row says so" {
  netstat_capture 3
  # The budget is lifted here because it measures the wall clock, and at load ~64/core it honestly
  # stopped this run after 2 attempts (137 s); the budget itself is pinned by the unit case above.
  run env HF_KPROBE_BUDGET_S=100000 HF_KPROBE_SLEEP_SCALE=0 LR_INPLACE_AWAIT=0 \
    timeout 600 bash "$HF" --prompt-file "$PF" --launcher claude-test --session-id 77 --recycle
  [ "$status" -eq 1 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"kitty probe 4/5"*"asking again in 40s"* ]] || { echo "$output"; false; }
  r="$(row_of recycle-held-unreachable)"
  [[ "$(jq -r .detail <<<"$r")" == *"after 5 attempt(s)"*"tries=5]"* ]] || { echo "$r"; false; }
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
