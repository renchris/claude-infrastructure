#!/usr/bin/env bats
# capacity-alarm-no-hang.bats — a `ps` that never returns cannot stop capacity-alarm writing its row
# (incident 2026-10-25, ~/incident-2026-10-25/solution/DESIGN.md C8, lane B half).
#
# That morning 23 `ps` sat asleep in a devfs lookup for hours. Every ps read in capacity-alarm.sh now
# runs under zone_bounded with its output in a FILE (a bound around a pipe bounds nothing), the
# multi-pid argv[0] read passes -x, and the /dev pty glob runs only in a bounded child or not at all.
# Every run below is wrapped in `perl -e '$SIG{ALRM} = "DEFAULT"; alarm N; exec'` (the reset matters: an inherited
# SIG_IGN for ALRM makes the bare form a no-op, and one hung run here outlived it), so a regression fails instead of hanging.

load helpers/cc-stub

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  ALARM="$REPO/scripts/capacity-alarm.sh"
  [ -f "$ALARM" ] || false
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME/.claude/logs"
  export CC_CAP_LOG="$D/cap.jsonl" CC_PAGES_DIR="$D/pages" CC_CAP_PAGE=off
  # Every ambient rung pinned neutral and every slow side read off — the pins tests/capacity-alarm.bats
  # documents; this suite owns only the ps bound and the pty source.
  export CC_CAP_LOAD_WARN_PER_CORE=9999 CC_CAP_LOAD_ALARM_PER_CORE=9999 CC_CAP_WARN_GB=0 CC_CAP_ALARM_GB=0 \
         CC_CAP_PRESSURE_WARN=9999 CC_CAP_PRESSURE_ALARM=9999 CC_CAP_PROC_WARN_GB=999999 \
         CC_CAP_SEG_WARN_PCT=999999 CC_CAP_SEG_ALARM_PCT=999999 CC_CAP_COAL_WARN=999999 \
         CC_CAP_COAL_ALARM=999999 CC_CAP_SWAP_DELTA_MB=999999 CC_CAP_SWAPFILE_WARN=999999 \
         CC_CAP_SWAPFILE_ALARM=999999 CC_CAP_KALLOC_WARN_GB=999999 CC_CAP_KALLOC_ALARM_GB=999999 \
         CC_CAP_KALLOC=off CC_CAP_ATTRIB=off CC_CAP_COAL_FP=0
  export CC_CAP_LOCKWATCH_STATE="$D/state.json"
  STUB="$D/stub"; mkdir -p "$STUB"
  : > "$D/reap.pids"; : > "$D/ps.calls"
  # top(1) prints nothing, so the top-procs read falls through to the ps fallback this suite owns.
  cc_stub "$STUB" top "$(printf '#!/bin/bash\nexit 0\n')"
  export CC_CAP_TOP="$STUB/top"
}

teardown() {
  local p
  while read -r p; do
    case "$p" in ''|*[!0-9]*) continue ;; esac
    kill -KILL "$p" 2>/dev/null || true       # the stub sleeps this suite started; no tty, no session
  done < "$D/reap.pids"
}

run_alarm() { # one appending run, bounded from outside
  run perl -e '$SIG{ALRM} = "DEFAULT"; alarm 120; exec @ARGV' -- env PATH="$STUB:$PATH" CC_CAP_PS="$STUB/ps" "$@" /bin/bash "$ALARM" --json
}
row() { tail -1 "$CC_CAP_LOG"; }

@test "a ps that NEVER returns: the run still appends exactly one parseable row, flagged argv_blind" {
  cc_stub "$STUB" ps - <<SH
#!/bin/bash
echo "\$\$" >> "$D/reap.pids"
echo "\$*" >> "$D/ps.calls"
exec sleep 1000
SH
  t0="$(date +%s)"
  run_alarm CC_CAP_PS_TIMEOUT_S=2
  [ "$status" -ne 142 ] || false                               # 142 = our outer alarm: it HUNG
  [ $(( $(date +%s) - t0 )) -lt 100 ] || false
  [ "$(wc -l < "$CC_CAP_LOG" | tr -d ' ')" -eq 1 ] || false
  row | jq -e . > /dev/null || false
  row | jq -e '.argv_blind == true' > /dev/null || false
  [ -s "$D/ps.calls" ] || false                                # positive control: ps was reached
}

@test "a ps that answers: argv_blind is false, and no multi-pid -p read ever omits -x" {
  cc_stub "$STUB" ps - <<SH
#!/bin/bash
echo "\$*" >> "$D/ps.calls"
case "\$*" in
  *-p\ *,*) case " \$* " in *" -x "*) ;; *) echo "MULTI-PID-WITHOUT-X \$*" >> "$D/ps.bad"; exit 99 ;; esac ;;
esac
case "\$*" in
  *command=*) printf '  501 /usr/bin/a\n  502 /usr/bin/b\n' ;;
  *rss=,comm=*) printf '  501 900000 /usr/bin/a\n  502 800000 /usr/bin/b\n' ;;
  *) exec /bin/ps "\$@" ;;
esac
SH
  run_alarm
  [ "$(wc -l < "$CC_CAP_LOG" | tr -d ' ')" -eq 1 ] || false
  row | jq -e '.argv_blind == false' > /dev/null || false
  [ ! -e "$D/ps.bad" ] || { cat "$D/ps.bad"; false; }
  grep -q 'command=' "$D/ps.calls" || false                    # the argv[0] read did run
  grep -q -- '-x -o pid=,command= -p 501,502' "$D/ps.calls" || false
}

@test "ptys: a FRESH lockwatch state.json is read (no /dev walk); a stale one falls back to the bounded glob" {
  cc_stub "$STUB" ps "$(printf '#!/bin/bash\nexec /bin/ps "$@"\n')"
  printf '{"v":1,"level":0,"ptys":42,"canary":{"zsh_ms":9}}\n' > "$D/state.json"
  run_alarm
  row | jq -e '.ptys_used == 42 and .ptys_src == "lockwatch"' > /dev/null || false
  touch -t "$(date -v-10M +%Y%m%d%H%M)" "$D/state.json"
  run_alarm
  row | jq -e '.ptys_src == "glob" and (.ptys_used | type) == "number"' > /dev/null || false
}
