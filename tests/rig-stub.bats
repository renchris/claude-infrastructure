#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # each @test is its own subshell
# tests/rig/stub-claude.py — the rig's fake Claude Code must match the real CLI where a recovery
# script probes it. Real `claude --version` prints and exits 0 with no session, no transcript and no
# registry row; the stub started a fresh session instead, whose registry row overwrote a relaunched
# pane's and hid the sid from the rig daemon (FLEET_V2 W5 N=30, clean-idle stuck IN-FLIGHT).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  STUB="$REPO/tests/rig/stub-claude.py"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/cfg"
  export CLAUDE_CONFIG_DIR="$HOME/cfg" CC_PANE_ID=77
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lr" LR_RECON_ROOT="$BATS_TEST_TMPDIR/state" TMPDIR="$BATS_TEST_TMPDIR/t"
  mkdir -p "$TMPDIR"
}

# ── W1 (B1 §9.2, M10, C12, C15): argv prompt, go_barrier ─────────────────────────────────────────
# The stub's key loop needs a tty (termios.tcgetattr), so these run it under a pty that the driver
# ends with SIGHUP (the stub exits 0 on it) once a condition holds, within a stated bound. Each one
# starts python and waits, so it skips below band 20: postland runs suites at background QoS, where
# python took minutes to start (B1 C11/F18).
need_band() { # read with ps, not python: at PRI 4 a python start is the cost being avoided
  b="$(ps -o pri= -p $$ 2>/dev/null | tr -d ' ')"
  case "$b" in ''|*[!0-9]*) skip "band unreadable ($b)" ;; esac
  [ "$b" -ge 20 ] || skip "band $b < 20 (postland background QoS)"
}
# under_pty BOUND_S LINGER_S UNTIL_SH CMD…: run CMD on a pty; once UNTIL_SH exits 0, keep it alive
# LINGER_S more (so a second, wrong write would land), then SIGHUP it. rc 0 = UNTIL_SH held in time.
under_pty() {
  /usr/bin/python3 -I -c '
import os, pty, select, signal, subprocess, sys, time
bound, linger, until, cmd = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3], sys.argv[4:]
log = open(os.environ.get("PTY_LOG", os.devnull), "ab")
pid, fd = pty.fork()
if pid == 0:
    os.execv(cmd[0], cmd)
t0, ok, end = time.time(), False, None
while time.time() - t0 < bound and (end is None or time.time() < end):
    if select.select([fd], [], [], 0.25)[0]:
        try:
            log.write(os.read(fd, 65536))
        except OSError:
            break
    if end is None and subprocess.call(["/bin/sh", "-c", until]) == 0:
        ok, end = True, time.time() + linger
os.kill(pid, signal.SIGHUP)
os.waitpid(pid, 0)
sys.exit(0 if ok else 1)' "$@"
}
stub_rig() { # a rig root, a spec for $1 with knobs $2, a work dir
  export LR_RIG="$BATS_TEST_TMPDIR/rig" LR_RIG_SPECS="$BATS_TEST_TMPDIR/rig/specs"
  mkdir -p "$LR_RIG_SPECS" "$BATS_TEST_TMPDIR/work"
  printf '{"knobs":%s}\n' "$2" > "$LR_RIG_SPECS/$1.json"
  W="$(cd "$BATS_TEST_TMPDIR/work" && pwd -P)"
}
limits() { grep -c quotaLimits "$1" 2>/dev/null || true; }
tx_of() { find "$HOME" -name "$1.jsonl" | head -1; }

@test "W1 C1 [RED on the pre-W1 stub]: --resume SID … PROMPT submits the argv prompt itself" {
  need_band
  sid=44444444-0000-4000-8000-000000000004
  stub_rig "$sid" '{}'
  python3 "$STUB" --rig-write-dead "$sid" --rig-cwd "$W" </dev/null
  tx="$(tx_of "$sid")"; [ -n "$tx" ]
  export CLAUDE_CONFIG_DIR="$HOME/.claude-next"
  run under_pty 60 0 "grep -q tok-w1c1 '$tx'" /usr/bin/python3 "$STUB" \
    --permission-mode auto --model x --effort high --resume "$sid" "continue tok-w1c1"
  [ "$status" -eq 0 ] || { tail -3 "$tx"; false; }
  # the token arrives as a USER record (the self-submit), not merely somewhere in the file
  python3 -c 'import json,sys
recs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
assert any(r.get("type") == "user" and "tok-w1c1" in json.dumps(r.get("message")) for r in recs), recs[-2:]' "$tx"
}

@test "W1 go_barrier: alive until go, then one limit death at go + die_at_s, recorded as died_at" {
  need_band
  sid=55555555-0000-4000-8000-000000000005
  stub_rig "$sid" '{"go_barrier":true,"die_at_s":1}'
  boot="$LR_RIG/tmp/boot/$sid.ok"
  # until: booted → snapshot the limit count, write go → the death arrives; linger 3 s for a repeat
  run under_pty 60 3 "[ -e '$boot' ] && { [ -e '$LR_RIG/go' ] || { grep -c quotaLimits \$(find '$HOME' -name '$sid.jsonl') > '$BATS_TEST_TMPDIR/before' || true; : > '$LR_RIG/go'; }; } && grep -q quotaLimits \$(find '$HOME' -name '$sid.jsonl')" \
    /bin/sh -c "cd '$W' && exec /usr/bin/python3 '$STUB' --session-id $sid"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/before")" = 0 ]          # no death before go
  [ "$(limits "$(tx_of "$sid")")" = 1 ]                 # exactly one, however long it lingers
  python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["died_at"] > 0' "$LR_RIG/tmp/stub/$sid.json"
}

@test "W1 C15: a member resumed on the target never dies there, even with go written and no died_at" {
  need_band
  sid=66666666-0000-4000-8000-000000000006
  stub_rig "$sid" '{"go_barrier":true,"die_at_s":0}'
  python3 "$STUB" --rig-write-dead "$sid" --rig-cwd "$W" </dev/null   # moved before it ever died
  tx="$(tx_of "$sid")"; before="$(limits "$tx")"
  : > "$LR_RIG/go"
  export CLAUDE_CONFIG_DIR="$HOME/.claude-next"
  run under_pty 60 3 "grep -q tok-c15 '$tx'" /usr/bin/python3 "$STUB" --resume "$sid" "continue tok-c15"
  [ "$status" -eq 0 ]
  [ "$(limits "$tx")" = "$before" ]
}

@test "W1 C15: with idle fan-out on, a go_barrier member boots WORKING, not idle at rest" {
  need_band
  sid=77777777-0000-4000-8000-000000000007
  stub_rig "$sid" '{"go_barrier":true,"idle_fanout":true,"die_at_s":600}'
  export PTY_LOG="$BATS_TEST_TMPDIR/screen"
  run under_pty 60 1 "[ -e '$LR_RIG/tmp/boot/$sid.ok' ]" \
    /bin/sh -c "cd '$W' && exec /usr/bin/python3 '$STUB' --session-id $sid"
  [ "$status" -eq 0 ]
  grep -q 'Working…' "$PTY_LOG"
  tx="$(tx_of "$sid")"; [ "$(limits "$tx")" = 0 ]
  [ "$(tail -1 "$tx" | python3 -c 'import json,sys; print(json.load(sys.stdin)["type"])')" = user ]
}

@test "stub --version prints the pinned version and writes no session, transcript or registry row" {
  run python3 "$STUB" --version </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^2\.1\.[0-9]+\ \(Claude\ Code\)$ ]] || { echo "$output"; false; }
  [ "$(find "$HOME" -type f | wc -l | tr -d ' ')" = 0 ] || { find "$HOME" -type f; false; }
}

# ── FLEET_V2 W6d rig additions (D1.11, D4.13) ─────────────────────────────────────────────────────

@test "reset_in_s moves the stub's limit reset from 3 h out to the knob" {
  export LR_RIG="$BATS_TEST_TMPDIR/rig" LR_RIG_SPECS="$BATS_TEST_TMPDIR/specs"
  mkdir -p "$LR_RIG_SPECS" "$BATS_TEST_TMPDIR/work"
  sid=11111111-0000-4000-8000-000000000001
  printf '{"knobs":{"reset_in_s":60}}\n' > "$LR_RIG_SPECS/$sid.json"
  run python3 "$STUB" --rig-write-dead "$sid" --rig-cwd "$BATS_TEST_TMPDIR/work" </dev/null
  [ "$status" -eq 0 ]
  tx="$(find "$HOME/.claude-next/projects" -name "$sid.jsonl")"
  at="$(tail -1 "$tx" | python3 -c 'import json,sys; print(json.load(sys.stdin)["quotaLimits"]["resetsAt"])')"
  d=$(( at - $(date +%s) ))
  [ "$d" -ge 50 ] && [ "$d" -le 70 ] || { echo "reset in ${d}s"; false; }
}

@test "fake --place answers stay only when RIG_PLACE_STAY=1 and the source is uncovered" {
  export LR_RECON_ROOT="$BATS_TEST_TMPDIR/state"; mkdir -p "$LR_RECON_ROOT" "$HOME/.claude" "$BATS_TEST_TMPDIR/facts"
  printf '{"accounts":[{"name":"next","config_dir":"%s/a"},{"name":"next2","config_dir":"%s/b"}]}\n' "$HOME" "$HOME" > "$HOME/.claude/accounts.json"
  printf '{"sid":"s1","src":"next","w":1}\n' > "$BATS_TEST_TMPDIR/m.jsonl"
  FAKE="$REPO/tests/rig/fake-claude-accounts.py"
  run python3 "$FAKE" --place --movers "$BATS_TEST_TMPDIR/m.jsonl" --facts "$BATS_TEST_TMPDIR/facts"
  [ "$(printf '%s' "$output" | python3 -c 'import json,sys; print(json.load(sys.stdin)["s1"]["acct"])')" = next2 ]
  RIG_PLACE_STAY=1 run python3 "$FAKE" --place --movers "$BATS_TEST_TMPDIR/m.jsonl" --facts "$BATS_TEST_TMPDIR/facts"
  [ "$(printf '%s' "$output" | python3 -c 'import json,sys; r=json.load(sys.stdin)["s1"]; print(r["acct"], r["reason"])')" = "next stay" ]
  printf '{"acct":"next","scope":"5h","resets_at":%d}\n' $(( $(date +%s) + 3600 )) > "$BATS_TEST_TMPDIR/facts/next.5h.json"
  RIG_PLACE_STAY=1 run python3 "$FAKE" --place --movers "$BATS_TEST_TMPDIR/m.jsonl" --facts "$BATS_TEST_TMPDIR/facts"
  [ "$(printf '%s' "$output" | python3 -c 'import json,sys; print(json.load(sys.stdin)["s1"]["acct"])')" = next2 ]
}

@test "the held-team case derives an IN-PLACE line; the existing matrices are unchanged" {
  LIB="$REPO/tests/rig/rig_lib.py"
  run python3 "$LIB" expected "$REPO/tests/rig/faults/held-team.json"
  [[ "$output" == "CLOSED 3/3 (ENGAGED 0, MOVED 0, IN-PLACE 3) · "* ]] || { echo "$output"; false; }
  run python3 "$LIB" expected "$REPO/tests/rig/faults/matrix30.json"
  [[ "$output" == "CLOSED 24/30 (ENGAGED 21, MOVED 3) · "* ]] || { echo "$output"; false; }
}

@test "a planted member is a live teammate by lr-team.sh, and the rig teardown pattern reaps it" {
  RIG="$BATS_TEST_TMPDIR/rig"; mkdir -p "$RIG/bin"
  lead=22222222-0000-4000-8000-000000000002
  pid="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import rig_lib; print(rig_lib._spawn_member(sys.argv[2], sys.argv[3]))' "$REPO/tests/rig" "$RIG" "$lead")"
  snap="$(LC_ALL=C ps -o pid=,stat=,args= -p "$pid")"
  kill "$pid" 2>/dev/null || true
  run bash -c 'source "$1"; lr_team_members "$2" "$3"' _ "$REPO/scripts/limit-recover/lr-team.sh" "$lead" "$snap"
  [ "$output" = 1 ] || { echo "snap: $snap"; false; }
  [[ "$snap" == *"$RIG/bin/claude"* ]]
}

@test "the launch-log audit counts an in-place cohort's typed continues, and is still not blind" {
  R="$BATS_TEST_TMPDIR/state"; mkdir -p "$R"
  sid=33333333-0000-4000-8000-000000000003
  printf '[{"sid":"%s","fold":false}]\n' "$sid" > "$BATS_TEST_TMPDIR/specs.json"
  : > "$R/launch.log"
  run python3 -c 'import sys,json; sys.path.insert(0, sys.argv[1]); import rig_lib; sys.exit(rig_lib.audit(sys.argv[2], json.load(open(sys.argv[3])), ""))' "$REPO/tests/rig" "$R" "$BATS_TEST_TMPDIR/specs.json"
  [ "$status" -eq 1 ]  # nothing logged: no verdict
  printf '1\t%s\trecon-C\tspawn\tpid=9\tattempt=1\trecord=r\n' "$sid" > "$R/launch.log"
  run python3 -c 'import sys,json; sys.path.insert(0, sys.argv[1]); import rig_lib; sys.exit(rig_lib.audit(sys.argv[2], json.load(open(sys.argv[3])), ""))' "$REPO/tests/rig" "$R" "$BATS_TEST_TMPDIR/specs.json"
  [ "$status" -eq 0 ]
  [[ "$output" == "launch-log audit: 1 lines · "* ]]
}

# ── W1 rig safety (B1 review S1-S4, S9) ── none of these touches kitty or the real launchd ──────────
RIGLIB() { python3 "$REPO/tests/rig/rig_lib.py" "$@"; }

@test "W1 S9: the rig refuses a root with .., a near-miss arm root, and any other path, before acting" {
  # a dead socket: even a guard regression (a mutant) cannot reach the operator's kitty from here
  export CC_TERM_KITTY_TO="$BATS_TEST_TMPDIR/no-kitty.sock"
  for r in /tmp/lrh-a-red/../x /tmp/lrh-a-cure-x /tmp/lrh--red "$BATS_TEST_TMPDIR/elsewhere" /tmp/lr-rig/; do
    LR_RIG_ROOT="$r" run /bin/bash "$REPO/tests/rig/lr-recon-rig.sh" --n 3 --faults "$REPO/tests/rig/faults/smoke3.json"
    [ "$status" -eq 2 ] || { echo "$r → $status: $output"; false; }
    [[ "$output" == *"refusing root"* ]] || { echo "$r: $output"; false; }
  done
  [ ! -e "$BATS_TEST_TMPDIR/elsewhere" ]
}

@test "W1 S2: kill-verified signals only the (pid, lstart, argv) it recorded" {
  R="$BATS_TEST_TMPDIR/rig"; mkdir -p "$R"
  /bin/bash -c 'exec -a "$0/holder" /bin/sleep 120' "$R" & good=$!
  /bin/sleep 120 & other=$!
  echo "$good" > "$R/good.pid"; RIGLIB record-id "$R/good.pid"
  # a pidfile whose recorded lstart is not the live process's: the pid was reused, never signal it
  echo "$other" > "$R/stale.pid"
  printf '{"pid": %d, "lstart": "Thu Jan  1 00:00:00 1970"}\n' "$other" > "$R/stale.pid.id"
  echo "$other" > "$R/norec.pid"                      # no identity recorded at all
  echo "$other" > "$R/noroot.pid"; RIGLIB record-id "$R/noroot.pid"   # right lstart, argv not the rig's
  # the rig's own argv but another lstart: the pid was reused by a process that happens to match
  echo "$good" > "$R/reused.pid"
  printf '{"pid": %d, "lstart": "Thu Jan  1 00:00:00 1970"}\n' "$good" > "$R/reused.pid.id"
  run RIGLIB kill-verified "$R" "$R/reused.pid" TERM; [ "$status" -eq 1 ]
  kill -0 "$good"
  run RIGLIB kill-verified "$R" "$R/stale.pid" TERM;  [ "$status" -eq 1 ]
  run RIGLIB kill-verified "$R" "$R/norec.pid" TERM;  [ "$status" -eq 1 ]
  run RIGLIB kill-verified "$R" "$R/noroot.pid" TERM; [ "$status" -eq 1 ]
  kill -0 "$other"
  # recorded under one locale, verified under another (the supervisor runs under env.sh's LANG):
  # lstart reads "Tue 20 Oct" in en_GB and "Tue Oct 20" in en_US, and must still match
  echo "$good" > "$R/good.pid"; LC_ALL=en_GB.UTF-8 RIGLIB record-id "$R/good.pid"
  LC_ALL=en_US.UTF-8 run RIGLIB kill-verified "$R" "$R/good.pid" TERM; [ "$status" -eq 0 ]
  wait "$good" 2>/dev/null || true
  if kill -0 "$good" 2>/dev/null; then false; fi
  kill "$other"
}

@test "W1 S3: the sweep takes a process naming the root, never one naming a sibling root" {
  R="$BATS_TEST_TMPDIR/rig"; mkdir -p "$R"
  /bin/bash -c 'exec -a "$0/member" /bin/sleep 120' "$R" & mine=$!
  /bin/bash -c 'exec -a "$0/member" /bin/sleep 120' "${R}2" & sibling=$!
  # a real session's prompt can name the root on argv; it is never a rig process
  /bin/bash -c 'exec -a /opt/fake/bin/claude /usr/bin/perl -e "sleep 120" "$0/in-a-prompt"' "$R" & session=$!
  sleep 1
  run RIGLIB sweep "$R" TERM "$BATS_TEST_TMPDIR/result.json"
  [ "$status" -eq 0 ] || { echo "$output"; cat "$BATS_TEST_TMPDIR/result.json"; false; }
  wait "$mine" 2>/dev/null || true
  if kill -0 "$mine" 2>/dev/null; then false; fi
  kill -0 "$sibling"; kill "$sibling"
  kill -0 "$session"; kill "$session"
  [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["leftovers"])' "$BATS_TEST_TMPDIR/result.json")" = "[]" ]
}

@test "W1 S1: containment is a rig pane sharing an OS window with a non-rig pane, nothing else" {
  R=/tmp/lrh-t1-cure
  ok='[{"id":1,"tabs":[{"windows":[{"id":10,"cwd":"/tmp/lrh-t1-cure/work"},{"id":11,"cwd":"/private/tmp/lrh-t1-cure/work/s01"}]}]},{"id":2,"tabs":[{"windows":[{"id":20,"cwd":"/Users/x"}]}]},{"id":3,"tabs":[{"windows":[{"id":30,"cwd":"/tmp/lrh-t1-cure/work/s02"}]}]}]'
  bad='[{"id":2,"tabs":[{"windows":[{"id":20,"cwd":"/Users/x"},{"id":21,"cwd":"/tmp/lrh-t1-cure/work/s01"}]}]}]'
  other_arm='[{"id":4,"tabs":[{"windows":[{"id":40,"cwd":"/tmp/lrh-t1-red/work/s01"},{"id":41,"cwd":"/tmp/lrh-t1-cure/work/s01"}]}]}]'
  run RIGLIB containment "$R" <<< "$ok";        [ "$status" -eq 0 ]; [ -z "$output" ]
  run RIGLIB containment "$R" <<< "$bad";       [ "$status" -eq 3 ]
  [[ "$output" == "os-window 2: rig 21 beside 20" ]] || false
  run RIGLIB containment "$R" <<< "$other_arm"; [ "$status" -eq 3 ]
  run RIGLIB containment "$R" <<< "not json";   [ "$status" -eq 0 ]   # no reading, not a breach
}

@test "W1 S4: the launchctl and osascript shims log their argv and do nothing" {
  export LR_RIG="$BATS_TEST_TMPDIR/rig"; mkdir -p "$LR_RIG/state"
  run "$REPO/tests/rig/shims/launchctl" kickstart "gui/$(id -u)/com.reso.lr-reset-poller"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run "$REPO/tests/rig/shims/osascript" -e 'tell application "kitty" to activate'
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$LR_RIG/state/shims.log" | tr -d ' ')" = 2 ]
  grep -q $'\tlaunchctl\tkickstart gui/' "$LR_RIG/state/shims.log"
  # and the rig links them first on its PATH, and points cc-lr's poller label nowhere
  # shellcheck disable=SC2016  # the literal line in the rig script
  grep -q 'ln -sf "$HERE/shims/$s" "$RIG/bin/$s"' "$REPO/tests/rig/lr-recon-rig.sh"
  grep -q 'CC_LR_POLLER_LABEL=rig.invalid' "$REPO/tests/rig/lr-recon-rig.sh"
}

@test "W1 smoke3: go_barrier reaches every member's knobs, and the derived line is ENGAGED 3/3" {
  run RIGLIB expected "$REPO/tests/rig/faults/smoke3.json"
  [[ "$output" == "ENGAGED 3/3 · "* ]] || { echo "$output"; false; }
  RIGLIB expand "$REPO/tests/rig/faults/smoke3.json" "$BATS_TEST_TMPDIR/specs.json"
  python3 -c 'import json,sys
s = json.load(open(sys.argv[1]))
assert len(s) == 3 and all(m["knobs"] == {"die_at_s": 5, "go_barrier": True} for m in s), s' "$BATS_TEST_TMPDIR/specs.json"
  # a legacy matrix gets nothing new: no barrier, so no idle_fanout knob either
  RIGLIB expand "$REPO/tests/rig/faults/matrix30.json" "$BATS_TEST_TMPDIR/m30.json"
  python3 -c 'import json,sys
assert not any("go_barrier" in m["knobs"] or "idle_fanout" in m["knobs"] for m in json.load(open(sys.argv[1])))' "$BATS_TEST_TMPDIR/m30.json"
}
