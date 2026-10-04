#!/usr/bin/env bats
# capacity-attrib.bats — the libproc attribution pass (scripts/lib/capacity-attrib.py) and its wiring
# into capacity-alarm.sh rung 4. Design: docs/research/concurrency-scale-2026-10-04/d-telemetry-gaps.md §2.
#
# The two properties that make the numbers worth anything, each proven with a process this suite owns
# and drives through a known sequence (file handshakes, never timing guesses):
#   1. CPU spent by a child that is born, works and is REAPED between two ticks is still credited to its
#      session. That is the whole reason for the pass: a ps/top snapshot never sees that child.
#   2. A child that had already burned CPU before tick A and is reaped before tick B is NOT re-credited
#      to its parent (the reap correction, §2.3). Without it the parent's child counter jumps by the
#      child's whole lifetime and the session reads ~0.8 s it did not spend in the interval.
# The fixture session is registered the way Claude Code registers one: a sessions/<pid>.json naming the
# pid and its procStart, found through CC_CAP_ATTRIB_ROOTS_GLOB.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  PASS="$REPO/scripts/lib/capacity-attrib.py"
  ALARM="$REPO/scripts/capacity-alarm.sh"
  D="$BATS_TEST_TMPDIR"
  export CC_CAP_ATTRIB_LOG="$D/attrib.jsonl" CC_CAP_ATTRIB_STATE="$D/attrib.state"
  export CC_CAP_ATTRIB_ROOTS_GLOB="$D/cfg/sessions/*.json"
  mkdir -p "$D/cfg/sessions" "$D/bin"
  export HOME="$D/home"; mkdir -p "$HOME/.claude/logs"   # the alarm's own logs and pages stay in the sandbox
  ROOT_PID=""
}

teardown() {
  # only processes this test started: the fixture root and its children
  if [ -n "$ROOT_PID" ]; then pkill -P "$ROOT_PID" 2>/dev/null || true; kill "$ROOT_PID" 2>/dev/null || true; fi
}

wait_for() { # <path> — up to 120 s; a loaded box can take many seconds to give 0.8 CPU-s
  local i=0
  while [ ! -e "$1" ] && [ "$i" -lt 1200 ]; do sleep 0.1; i=$((i + 1)); done
  [ -e "$1" ]
}

register_root() { # <pid> <sid>
  local start
  # LC_ALL=C: Claude Code writes procStart as `Sun Oct  4 ...`; an en_CA ps prints `Sun  4 Oct ...`.
  start="$(LC_ALL=C ps -o lstart= -p "$1" | sed 's/^ *//; s/ *$//')"
  jq -nc --argjson pid "$1" --arg sid "$2" --arg st "$start" --arg cwd "$D" \
    '{pid:$pid, sessionId:$sid, procStart:$st, kind:"interactive", cwd:$cwd}' > "$D/cfg/sessions/$1.json"
}

BURN='import time,sys,os
t = time.process_time()
while time.process_time() - t < float(sys.argv[1]): pass
open(sys.argv[2], "w").write(str(os.getpid()))
while len(sys.argv) > 3 and not os.path.exists(sys.argv[3]): time.sleep(0.05)'

tick() { run python3 "$PASS"; [ "$status" -eq 0 ]; }

session_field() { # <sid> <field> — fails (prints nothing, rc 1) when the session is not on the row, so
  # a missing root can never compare as 0 and pass a "less than" assertion vacuously
  tail -1 "$CC_CAP_ATTRIB_LOG" | jq -er --arg s "$1" --arg f "$2" '.sessions[] | select(.sid == $s) | .[$f]'
}

@test "a child born, working and reaped between two ticks is credited to its session" {
  # The root waits for go, runs a 0.6 CPU-s child to completion (bash reaps it), then idles. The trailing
  # `; true` keeps bash from exec-ing its last command: exec RESETS a process's reaped-child counters
  # (measured here, 2026-10-04), so an exec'd root would lose the very CPU this test looks for.
  bash -c 'while [ ! -e "$1/go" ]; do sleep 0.05; done; python3 -c "$2" 0.6 "$1/burned"; sleep 300; true' \
    _ "$D" "$BURN" &
  ROOT_PID=$!
  register_root "$ROOT_PID" sid-reaped
  tick
  [ "$(tail -1 "$CC_CAP_ATTRIB_LOG" | jq -r .accounting)" = baseline ]
  touch "$D/go"
  wait_for "$D/burned"
  sleep 0.5                                   # let bash reap the child (it exec's sleep right after)
  tick
  [ "$(tail -1 "$CC_CAP_ATTRIB_LOG" | jq -r .accounting)" = ok ]
  c="$(session_field sid-reaped cpu_s)"; awk -v c="$c" 'BEGIN { exit !(c >= 0.45) }'
  c="$(session_field sid-reaped child_s)"; awk -v c="$c" 'BEGIN { exit !(c >= 0.45) }'
}

@test "a child that burned BEFORE tick A and is reaped before tick B is not re-credited (reap correction)" {
  # The child burns 0.8 CPU-s, signals, then waits for exit; bash reaps it only after tick A.
  bash -c 'python3 -c "$2" 0.8 "$1/burned" "$1/exit"; sleep 300; true' _ "$D" "$BURN" &
  ROOT_PID=$!
  register_root "$ROOT_PID" sid-corrected
  wait_for "$D/burned"
  tick                                        # A: the child is alive holding ~0.8 s of its own CPU
  child="$(cat "$D/burned")"
  touch "$D/exit"
  local i=0
  while kill -0 "$child" 2>/dev/null && [ "$i" -lt 600 ]; do sleep 0.1; i=$((i + 1)); done
  ! kill -0 "$child" 2>/dev/null || false
  sleep 0.3
  tick                                        # B: bash's child counter now holds the whole 0.8 s
  [ "$(tail -1 "$CC_CAP_ATTRIB_LOG" | jq -r .accounting)" = ok ]
  c="$(session_field sid-corrected cpu_s)"; awk -v c="$c" 'BEGIN { exit !(c < 0.4) }'
}

@test "the row carries the host budget and the positive control, and unseen is reported" {
  tick; sleep 1; tick
  run jq -e '(.host.busy_s | type) == "number" and (.unseen_s | type) == "number"
             and (.accounting == "ok" or .accounting == "overflow") and (.el_s > 0)
             and (.forks_per_s | type) == "number" and (.self_cpu_s | type) == "number"' \
    <(tail -1 "$CC_CAP_ATTRIB_LOG")
  [ "$status" -eq 0 ]
}

@test "stdout is the rung-4 feed: three '<pid> <mb> <name>' lines by footprint" {
  run python3 "$PASS" --no-write
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -cE '^[0-9]+ [0-9]+ .+')" -eq 3 ]
  [ ! -e "$CC_CAP_ATTRIB_LOG" ] && [ ! -e "$CC_CAP_ATTRIB_STATE" ]   # --no-write writes nothing
}

@test "a state older than the gap bound yields a baseline row, never a delta across the gap" {
  tick
  jq -c '.ts -= 100000' "$CC_CAP_ATTRIB_STATE" > "$D/s" && mv "$D/s" "$CC_CAP_ATTRIB_STATE"
  tick
  [ "$(tail -1 "$CC_CAP_ATTRIB_LOG" | jq -r .accounting)" = baseline ]
}

@test "the eval body is recovered from the Bash tool's argv, quotes undone" {
  run python3 -c 'import importlib.util,sys
s=importlib.util.spec_from_file_location("ca",sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
argv2 = "source /x/snap.sh 2>/dev/null || true && { builtin unalias x; } || true && eval " + chr(39) + "echo " + chr(39) + chr(34) + chr(39) + chr(34) + chr(39) + "s" + chr(39) + " < /dev/null && pwd -P >| /tmp/c"
print(m.eval_body(argv2))' "$PASS"
  [ "$status" -eq 0 ]
  [ "$output" = "echo 's" ]
}

# ── wiring into capacity-alarm.sh ───────────────────────────────────────────────────────────────
@test "capacity-alarm feeds rung 4 from the pass, writes the attrib row, and says so (top_src)" {
  run env CC_CAP_LOG="$D/cap.jsonl" CC_CAP_KALLOC=off CC_CAP_COAL_FP=0 CC_CAP_PAGE=off \
    /bin/bash "$ALARM" --json
  [[ "$output" =~ \"top_src\":\"attrib\" ]] || false
  [[ "$output" =~ \"top_procs\":\[\{\"pid\": ]] || false
  [ "$(wc -l < "$CC_CAP_ATTRIB_LOG")" -eq 1 ] && [ -s "$CC_CAP_ATTRIB_STATE" ]
}

@test "--no-append leaves the live delta state untouched" {
  run env CC_CAP_LOG="$D/cap.jsonl" CC_CAP_KALLOC=off CC_CAP_COAL_FP=0 CC_CAP_PAGE=off \
    /bin/bash "$ALARM" --json --no-append
  [[ "$output" =~ \"top_src\":\"attrib\" ]] || false
  [ ! -e "$CC_CAP_ATTRIB_LOG" ] && [ ! -e "$CC_CAP_ATTRIB_STATE" ]
}

@test "a pass that yields nothing falls back to top(1), then to ps — never a blank rung" {
  # a python that refuses only the attribution pass, so every other python reader still works
  # shellcheck disable=SC2016  # the stub's own program
  printf '#!/bin/bash\ncase "$1" in *capacity-attrib.py) exit 1 ;; esac\nexec python3 "$@"\n' > "$D/bin/py"
  chmod +x "$D/bin/py"
  printf '#!/bin/bash\necho "  PID  MEM   COMMAND"\necho "4242 1200M fixture-top"\n' > "$D/bin/top"
  chmod +x "$D/bin/top"
  run env CC_CAP_LOG="$D/cap.jsonl" CC_CAP_KALLOC=off CC_CAP_COAL_FP=0 CC_CAP_PAGE=off \
    CC_CAP_PYTHON="$D/bin/py" CC_CAP_TOP="$D/bin/top" /bin/bash "$ALARM" --json --no-append
  [[ "$output" =~ \"top_src\":\"top\" ]] || false
  [[ "$output" =~ fixture-top ]] || false
  run env CC_CAP_LOG="$D/cap.jsonl" CC_CAP_KALLOC=off CC_CAP_COAL_FP=0 CC_CAP_PAGE=off \
    CC_CAP_PYTHON="$D/bin/py" CC_CAP_TOP=/nonexistent/top /bin/bash "$ALARM" --json --no-append
  [[ "$output" =~ \"top_src\":\"ps\" ]] || false
  [[ "$output" =~ \"top_procs\":\[\{\"pid\": ]] || false
}
