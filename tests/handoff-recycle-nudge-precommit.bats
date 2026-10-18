#!/usr/bin/env bats
# K1, THE COMMIT MARKER (lr-wake 2026-10-18, docs/research/lr-wake-incident-2026-10-18/REPORT.md
# Wave A, RC1). The recycle watcher is detached before the confirm. Its nudge checkpoints (60/150/300 s)
# counted from its arm, and on an empty composer with claude alive the 60 s one decided `retype` and
# typed /exit — the FIRST /exit, while the foreground was still in its confirm, last read and load gate
# (80-270 s at 8-30 load per core). history.jsonl records that /exit as a typed prompt in four
# sessions (2e9ed9f2 03:38:37Z and 07:22:53Z, e52f1f63/5232121f 07:06:13Z, 22a76c8a 07:22:38Z), and
# the foreground then held and killed the watcher mid-relaunch.
#
# WHAT IS DRIVEN: the detached `__recycle` watcher itself, on a FAKE CLOCK — `date +%s` reads a counter
# that only the `sleep` shim advances, so 70 s of watcher time costs a few real seconds — against a
# stateful it2 (an empty composer; a typed /exit shows in it) and a ps that makes the pane read `cc`
# (claude 4200 under zsh 4100 on the pane's tty). The foreground is a real sleeper whose pid + start
# time ride in HF_RCY_FG_PID / HF_RCY_FG_LSTART, as recycle_fire exports them at the detach.
#
# RED on origin/main (2a636f1b8): 1 (a /exit is sent at ~60 s with no marker), 2, 3, 4 (no orphan,
# abort or yield arm exists: the watcher waits and retypes). Mutants: count the nudge clock from the
# arm again (1 red) · drop the precommit `continue` (1 red) · drop the orphan arm (2 red) · drop the
# exit-aborted arm (3 red) · start a yield in the committed state (4 red).

setup() {
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="${HF_OVERRIDE:-$REPO_SRC/scripts/handoff-fire.sh}"
  LIB="$REPO_SRC/hooks/lib/pane-modal.sh"
  [ -f "$HF" ] && [ -f "$LIB" ] || { echo "subject missing" >&2; return 1; }
  # Pinned, never ambient (M11 / MACHINE_CAPACITY_V2 §11.3), one export per line for the pin ratchet.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/no-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/no-such-heal-lock-"
  export H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H/.claude/bin" "$H/.claude/logs"; export HOME="$H"
  export CC_HANDOFF_ALARM_DIR="$H/.claude/handoff-alarms"
  export CC_PANE_MODAL_LIB="$LIB"
  export CC_NOTIFY_BIN="$H/.claude/bin/cc-notify"
  export LR_LOCKS_DIR="$BATS_TEST_TMPDIR/locks" CC_PANE_SUCCESSOR_DIR="$BATS_TEST_TMPDIR/succ"
  mkdir -p "$CC_PANE_SUCCESSOR_DIR"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$CC_NOTIFY_BIN"; chmod +x "$CC_NOTIFY_BIN"
  unset HF_RCY_FG_PID HF_RCY_FG_LSTART HF_RCY_WATCHER_LOG LR_RECORD_ID 2>/dev/null || true

  export ST="$BATS_TEST_TMPDIR/state"; mkdir -p "$ST"
  printf cc > "$ST/pane"; : > "$ST/composer"; printf 0 > "$ST/clock"; : > "$ST/sends"
  export FAKE_T0
  FAKE_T0="$(/bin/date +%s)"
  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SHIM/osascript"
  # THE FAKE CLOCK: `date +%s` is the start plus the seconds the sleeps have "taken"; every other
  # form is the real date. `sleep` takes no time and advances the counter by its argument.
  cat > "$SHIM/date" <<'SH'
#!/usr/bin/env bash
if [ "$*" = "+%s" ]; then awk -v t="$FAKE_T0" -v o="$(cat "$ST/clock")" 'BEGIN { printf "%d\n", t + o }'; exit 0; fi
exec /bin/date "$@"
SH
  cat > "$SHIM/sleep" <<'SH'
#!/usr/bin/env bash
o="$(cat "$ST/clock")"; awk -v o="$o" -v d="${1:-0}" 'BEGIN { printf "%s", o + d }' > "$ST/clock.t" && mv "$ST/clock.t" "$ST/clock"
SH
  # THE PANE: zsh 4100 owns ttys999; while $ST/pane says cc, claude 4200 is its child. Everything else
  # is the real ps, so the foreground's start time is read for real.
  cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
s="$(cat "$ST/pane")"
case " $* " in
  *" -o pid= -t ttys999 "*|*" -o tpgid= -t ttys999 "*) printf '4100\n'; exit 0 ;;
  *" -axo pid=,ppid= "*) printf '4100 1\n'; [ "$s" = cc ] && printf '4200 4100\n'; exit 0 ;;
  *" -g 4100 "*) printf '4100 /bin/zsh\n'; exit 0 ;;
  *" -p 4200 "*) [ "$s" = cc ] || exit 1; case " $* " in *comm=*) printf 'claude\n' ;; *) printf 'claude --resume\n' ;; esac; exit 0 ;;
  *" -p 4100 "*) case " $* " in *comm=*) printf '/bin/zsh\n' ;; *) printf -- '-zsh\n' ;; esac; exit 0 ;;
esac
exec /bin/ps "$@"
SH
  chmod +x "$SHIM/osascript" "$SHIM/date" "$SHIM/sleep" "$SHIM/ps"
  export PATH="$SHIM:$PATH"

  # it2: the composer is a file. A typed line lands in it, a CR submits it (claude stays alive unless
  # EXIT_ON_CR=1), Ctrl-U/DEL clear it. Every send is recorded, %q-quoted, one per line.
  export STUB_PANE="K1-PANE"
  cat > "$H/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "session list")
    if [ "${3:-}" = --json ]; then printf '[{"id": "%s", "tty": "/dev/ttys999"}]\n' "$STUB_PANE"
    else printf '%s\n' "$STUB_PANE"; fi
    exit 0 ;;
  "session read") printf 'history\n────────────────────\n❯ %s\n────────────────────\n' "$(cat "$ST/composer")"; exit 0 ;;
  "session send")
    p="${!#}"; printf 'send %q\n' "$p" >> "$ST/sends"
    case "$p" in
      $'\r') if [ "$(cat "$ST/composer")" = /exit ] && [ "${EXIT_ON_CR:-0}" = 1 ]; then printf shell > "$ST/pane"; fi
             : > "$ST/composer" ;;
      $'\x15'|$'\x7f'*|$'\e') : > "$ST/composer" ;;
      *) printf '%s' "$(cat "$ST/composer")$p" > "$ST/composer" ;;
    esac
    exit 0 ;;
esac
exit 0
SH
  chmod +x "$H/.claude/bin/it2"

  export CMDFILE="$BATS_TEST_TMPDIR/handoff-recycle-cmd-K1"; printf 'claude --resume x\n' > "$CMDFILE"
  export HF_RECYCLE_SHELL_POLL_S=3 HF_RECYCLE_SHELL_WAIT_S=400 CC_RECYCLE_BGWORK_EVERY_S=15
  # The foreground, alive until a case kills it, and its identity as recycle_fire hands it over.
  /bin/sleep 600 >/dev/null 2>&1 3>&- & FG=$!
  echo "$FG" > "$BATS_TEST_TMPDIR/fg.pid"
  eval "$(sed -n '/^_hf_lstart() {/,/^}/p' "$HF")"
  export HF_RCY_FG_PID="$FG" HF_RCY_FG_LSTART
  HF_RCY_FG_LSTART="$(PATH=/usr/bin:/bin _hf_lstart "$FG")"
  [ -n "$HF_RCY_FG_LSTART" ] || { echo "could not read the foreground's start time" >&2; return 1; }
  WLOG="$BATS_TEST_TMPDIR/watcher.log"
}

teardown() {
  local p
  for p in watcher fg; do
    [ -f "$BATS_TEST_TMPDIR/$p.pid" ] && { kill "$(cat "$BATS_TEST_TMPDIR/$p.pid")" 2>/dev/null || true; }
  done
  return 0
}

start_watcher() {
  bash "$HF" __recycle "$STUB_PANE" /dev/ttys999 "$CMDFILE" "$BATS_TEST_TMPDIR" sid-before > "$WLOG" 2>&1 3>&- &
  echo $! > "$BATS_TEST_TMPDIR/watcher.pid"
}
clock() { awk '{ printf "%d", $1 }' "$ST/clock"; }
rows_of() { grep "\"class\":\"$1\"" "$H/.claude/logs/handoffs.jsonl" 2>/dev/null; }
exit_sends() { grep -cxF 'send /exit' "$ST/sends" || true; }
# wait_for <real-seconds> <condition…> — polls on the REAL clock, never the fake one.
wait_for() {
  local n=0 max=$(( $1 * 4 )); shift
  while ! "$@"; do
    n=$((n + 1)); [ "$n" -lt "$max" ] || return 1
    /bin/sleep 0.25
  done
}
clock_past() { [ "$(clock)" -ge "$1" ]; }
row_seen() { [ -n "$(rows_of "$1")" ]; }
watcher_gone() { ! kill -0 "$(cat "$BATS_TEST_TMPDIR/watcher.pid")" 2>/dev/null; }
show() { echo "--- clock $(clock)s"; echo "--- sends"; cat "$ST/sends"; echo "--- watcher"; cat "$WLOG"; echo "--- rows"; cat "$H/.claude/logs/handoffs.jsonl" 2>/dev/null; }

@test "1 [RED] no exit-committed marker for 70 s: not one /exit is typed; with the marker, exactly one gated retype" {
  start_watcher
  wait_for 240 clock_past 70 || { show; false; }
  [ "$(exit_sends)" = 0 ] || { echo "a /exit was typed before the commit:"; show; false; }
  rows_of recycle-nudge-precommit | grep -q 'decision=precommit at 6[0-9]s' || { show; false; }
  [ -z "$(rows_of recycle-nudge-retype)" ] || { show; false; }

  date +%s > "$CMDFILE.exit-committed"
  local t_mark; t_mark="$(clock)"
  wait_for 240 row_seen recycle-nudge-retype || { show; false; }
  [ "$(exit_sends)" = 1 ] || { echo "want exactly one /exit"; show; false; }
  # Gated: read back exactly, THEN the CR — the CR is the very next send.
  grep -A1 -xF 'send /exit' "$ST/sends" | tail -1 | grep -qxF "send \$'\\r'" || { show; false; }
  rows_of recycle-nudge-retype | grep -q 'read back exactly, CR sent' || { show; false; }
  # The checkpoint counted from the marker, not from the arm.
  [ $(( $(clock) - t_mark )) -ge 60 ] || { echo "retyped $(( $(clock) - t_mark ))s after the marker"; show; false; }
  grep -q '→ commit: the foreground wrote exit-committed' "$WLOG" || { show; false; }
}

@test "2 [RED] the foreground dies with no marker: the watcher hands a confirmed source back and stands down" {
  # The confirm's operands, as recycle_fire_commit writes them beside the cmdfile.
  printf '%s\n' "2e9ed9f2-0000-4000-8000-000000000332" "$H/.claude-next" "$H/.claude-tertiary" > "$CMDFILE.confirmed"
  cat > "$BATS_TEST_TMPDIR/lr-transplant.sh" <<'SH'
#!/usr/bin/env bash
printf 'transplant %s\n' "$*" >> "$ST/transplant.log"
exit 0
SH
  chmod +x "$BATS_TEST_TMPDIR/lr-transplant.sh"
  export HF_LR_TRANSPLANT="$BATS_TEST_TMPDIR/lr-transplant.sh"
  kill "$FG"; wait "$FG" 2>/dev/null || true
  start_watcher
  wait_for 240 watcher_gone || { show; false; }
  [ "$(exit_sends)" = 0 ] || { show; false; }
  grep -q -- '--phase unconfirm --sid 2e9ed9f2-0000-4000-8000-000000000332' "$ST/transplant.log" || { show; cat "$ST/transplant.log" 2>/dev/null; false; }
  rows_of recycle-watcher-orphaned | grep -q 'unconfirm rc 0' || { show; false; }
  grep -q 'recycle ORPHANED' "$WLOG" || { show; false; }
}

@test "3 [RED] the foreground held before its commit (exit-aborted): the watcher stands down, nothing typed" {
  start_watcher
  wait_for 240 clock_past 20 || { show; false; }
  date +%s > "$CMDFILE.exit-aborted"
  wait_for 240 watcher_gone || { show; false; }
  [ "$(exit_sends)" = 0 ] || { show; false; }
  [ ! -s "$ST/sends" ] || { echo "a key was sent:"; show; false; }
  row_seen recycle-watcher-stood-down || { show; false; }
}

@test "4 [RED] a yield (claude exited before the commit) is waited out with no nudge at all" {
  start_watcher
  date +%s > "$CMDFILE.exit-yielded"
  wait_for 240 clock_past 170 || { show; false; }
  [ ! -s "$ST/sends" ] || { echo "a key was sent after a yield:"; show; false; }
  [ -z "$(rows_of recycle-nudge-retype)" ] || { show; false; }
  [ -z "$(rows_of recycle-nudge-cr)" ] || { show; false; }
  grep -q '→ commit: the foreground wrote exit-yielded' "$WLOG" || { show; false; }
}
