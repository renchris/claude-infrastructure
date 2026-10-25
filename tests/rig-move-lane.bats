#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # each @test is its own subshell
# The rig's move lane, D2a switch file and deaf-kitty fault (LR_SUSTAINED_LOAD W4b; B1 §16 A7), at
# fixture level, in the land gate: no kitty, no daemon, no live pane. The poller stand-in runs the
# REAL `lr-reset-poller.sh --move-kick` of this checkout against a throwaway arm root with a fake batch
# runner; kitty-slow runs against a fake kitty that only prints. No case holds a wall-clock bound
# beyond waiting for a detached child's first line (B1 §12: the gate runs at utility).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  RIGD="$REPO/tests/rig"
  R="$BATS_TEST_TMPDIR/rig"
  mkdir -p "$R"/{bin,state,home,tmp,lr/move/requests,faults}
  export HOME="$R/home" LR_STATE_DIR="$R/lr" LR_RECON_ROOT="$R/state" TMPDIR="$R/tmp/" LR_RIG="$R"
  ln -s "$RIGD/shims/launchctl" "$R/bin/launchctl"
  ln -s "$RIGD/shims/osascript" "$R/bin/osascript"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
}

py() { /usr/bin/python3 -I "$@"; }
rl() { /usr/bin/python3 -I "$RIGD/rig_lib.py" "$@"; }
# a queued batch exactly as `cc-lr move` leaves it: move/<b>/plan.json, then move/requests/<b>.json
queue() {
  mkdir -p "$LR_STATE_DIR/move/$1"
  printf '{"batch":"%s","rows":[]}\n' "$1" > "$LR_STATE_DIR/move/$1/plan.json"
  printf '{"kind":"move-batch","batch":"%s"}\n' "$1" > "$LR_STATE_DIR/move/requests/$1.json"
}
# the batch runner the kick detaches: one line per start, and nothing else
fake_runner() {
  # shellcheck disable=SC2016  # the stub body carries a literal $1/$$ on purpose
  printf '#!/bin/bash\nprintf "%%s\\t%%s\\n" "$1" "$$" >> "%s/state/runner.log"\n' "$R" > "$R/bin/fake-batch"
  chmod +x "$R/bin/fake-batch"
  export LR_MOVE_BATCH_BIN="$R/bin/fake-batch"
}
standin() { # one pass of the stand-in under the arm's env, the way lr-recon-rig.sh runs it
  env -i PATH="$R/bin:/usr/bin:/bin" LR_RIG="$LR_RIG" HOME="$HOME" LR_STATE_DIR="$LR_STATE_DIR" \
    LR_RECON_ROOT="$LR_RECON_ROOT" TMPDIR="$TMPDIR" LR_MOVE_BATCH_BIN="${LR_MOVE_BATCH_BIN:-}" \
    LR_RIG_STANDIN_ONCE=1 /bin/bash "$RIGD/poller-standin" "$R/" "$POLLER"
}
runner_lines() { # waits for the detached runner's first line (it is the kick's child, not ours)
  local i=0
  while [ ! -s "$R/state/runner.log" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
  grep -c . "$R/state/runner.log" 2>/dev/null || echo 0
}

# ── the move-lane driver: tests/rig/poller-standin ─────────────────────────────────────────────────

@test "stand-in: one pass runs the real --move-kick, which claims the batch by link and starts it once" {
  fake_runner; queue B1
  run standin
  [ "$status" -eq 0 ]
  [ "$(runner_lines)" -eq 1 ]
  [ "$(cut -f1 "$R/state/runner.log")" = B1 ]
  [ -f "$LR_STATE_DIR/move/B1/request.claimed.json" ]          # the claim is the request, linked
  [ ! -e "$LR_STATE_DIR/move/requests/B1.json" ]               # and the queue entry is gone
  grep -q "MOVE-BATCH started pid" "$HOME/.reso/limit-recover/poller.log"
  [ "$(cut -f2,3 "$R/state/poller-standin.log")" = "$(printf 'kick\t0')" ]
}

@test "stand-in: a repeated request for a claimed batch is dropped, never started twice" {
  fake_runner; queue B1
  standin; [ "$(runner_lines)" -eq 1 ]
  printf '{"kind":"move-batch","batch":"B1"}\n' > "$LR_STATE_DIR/move/requests/B1.json"
  run standin
  [ "$status" -eq 0 ]
  grep -q "MOVE-SKIP B1 was already claimed" "$HOME/.reso/limit-recover/poller.log"
  [ ! -e "$LR_STATE_DIR/move/requests/B1.json" ]
  [ "$(grep -c . "$R/state/runner.log")" -eq 1 ]
}

@test "stand-in: two stand-ins kicking one request at once start it exactly once (the link claim)" {
  fake_runner; queue B1
  standin & a=$!
  standin & b=$!
  wait "$a"; wait "$b"
  [ "$(runner_lines)" -eq 1 ]
  sleep 1   # a second start, had there been one, is a detached child too: give it the same chance
  [ "$(grep -c . "$R/state/runner.log")" -eq 1 ]
}

@test "stand-in: with nothing queued it kicks nothing" {
  fake_runner
  run standin
  [ "$status" -eq 0 ]
  [ ! -e "$R/state/poller-standin.log" ]
  [ ! -e "$R/state/runner.log" ]
}

@test "stand-in: refuses a root its env does not name, or a state dir outside it, and kicks nothing" {
  fake_runner; queue B1
  LR_RIG="$BATS_TEST_TMPDIR/other" run standin
  [ "$status" -eq 2 ]
  [[ "$output" == *"is not $R"* ]] || false
  LR_STATE_DIR="$BATS_TEST_TMPDIR/real-lr" run standin
  [ "$status" -eq 2 ]
  [[ "$output" == *"outside $R"* ]] || false
  [ -e "$LR_STATE_DIR/move/requests/B1.json" ] && [ ! -e "$R/state/runner.log" ]
}

# ── the shims: log their argv, do nothing ─────────────────────────────────────────────────────────

@test "shims: launchctl and osascript log their argv, print nothing and exit 0" {
  run env -i PATH=/usr/bin:/bin LR_RIG="$R" "$R/bin/launchctl" kickstart -k gui/501/com.reso.lr-reset-poller
  [ "$status" -eq 0 ] && [ -z "$output" ] || false
  run env -i PATH=/usr/bin:/bin LR_RIG="$R" "$R/bin/osascript" -e 'tell application "kitty" to activate'
  [ "$status" -eq 0 ] && [ -z "$output" ] || false
  [ "$(cut -f2- "$R/state/shims.log" | sed -n 1p)" = "$(printf 'launchctl\tkickstart -k gui/501/com.reso.lr-reset-poller')" ]
  [ "$(cut -f2 "$R/state/shims.log" | sed -n 2p)" = osascript ]
}

# ── the D2a switch file ───────────────────────────────────────────────────────────────────────────

@test "idle_fanout_switch: env on AND the arm's recon/idle-fanout.on is created" {
  printf '{"idle_fanout_switch": true, "groups": []}\n' > "$R/m.json"
  run rl switches "$R/m.json" "$R"
  [ "$status" -eq 0 ] && [ "$output" = on ] || false
  [ -f "$R/state/idle-fanout.on" ]
}

@test "idle_fanout (env only) creates no switch file; neither key reads off" {
  printf '{"idle_fanout": true, "groups": []}\n' > "$R/m.json"
  run rl switches "$R/m.json" "$R"
  [ "$output" = on ] && [ ! -e "$R/state/idle-fanout.on" ] || false
  printf '{"groups": []}\n' > "$R/m.json"
  run rl switches "$R/m.json" "$R"
  [ "$output" = off ] && [ ! -e "$R/state/idle-fanout.on" ]
}

@test "idle_fanout_switch boots go_barrier members WORKING exactly as idle_fanout does (C15)" {
  run py -c 'import json,sys; sys.path.insert(0,sys.argv[1]); import rig_lib
f = json.load(open(sys.argv[2])); assert f.get("idle_fanout_switch") and not f.get("idle_fanout")
ms = rig_lib.expand(f)
print(sum(1 for m in ms if m["knobs"].get("idle_fanout")), len(ms))' "$RIGD" "$RIGD/faults/guarantee30.json"
  [ "$status" -eq 0 ]
  [ "$output" = "30 30" ]
}

# ── kitty_ls_fail: a deaf kitty, inside its window only ───────────────────────────────────────────

fake_kitty() { # a "real" kitty and kitten that only print, so nothing reaches the operator's kitty
  mkdir -p "$R/fk"
  # shellcheck disable=SC2016  # the stub body carries a literal ${0##*/} and $* on purpose
  printf '#!/bin/bash\necho "REAL ${0##*/} $*"\n' > "$R/fk/kitty"; cp "$R/fk/kitty" "$R/fk/kitten"
  chmod +x "$R/fk/kitty" "$R/fk/kitten"
  export LR_RIG_REAL_KITTY="$R/fk/kitty"
}
lsf() { # BASE_OFFSET FROM FOR → the table rig_lib writes from a matrix, BASE = now + offset
  printf '{"kitty_ls_fail": {"from": %s, "for": %s}, "groups": []}\n' "$2" "$3" > "$R/m.json"
  rl kitty-ls-fail "$R/m.json" "$R" "$(( $(date +%s) + $1 ))" >/dev/null
}

@test "kitty_ls_fail: inside the window the daemon's full kitten @ ls exits 1 and is logged" {
  fake_kitty; lsf -10 0 120
  run "$RIGD/kitten-slow" @ --to unix:/tmp/none ls
  [ "$status" -eq 1 ]
  [[ "$output" == *"rig fault kitty_ls_fail"* ]] || false
  [ "$(cut -f2- "$R/state/kitty-delay.log")" = "$(printf -- '-\tls-fail\tls')" ]
}

@test "kitty_ls_fail: before and after its window, the full ls reaches kitty" {
  fake_kitty; lsf 100 0 120
  run "$RIGD/kitten-slow" @ --to unix:/tmp/none ls
  [ "$status" -eq 0 ] && [ "$output" = "REAL kitten @ --to unix:/tmp/none ls" ] || false
  lsf -1000 0 60
  run "$RIGD/kitten-slow" @ --to unix:/tmp/none ls
  [ "$status" -eq 0 ] && [ "$output" = "REAL kitten @ --to unix:/tmp/none ls" ] || false
  [ ! -e "$R/state/kitty-delay.log" ]
}

@test "kitty_ls_fail: inside the window a --match ls and an actuator's kitty-slow ls still reach kitty" {
  fake_kitty; lsf -10 0 120
  run "$RIGD/kitten-slow" @ --to unix:/tmp/none ls --match id:7
  [ "$status" -eq 0 ] && [ "$output" = "REAL kitten @ --to unix:/tmp/none ls --match id:7" ] || false
  run "$RIGD/kitty-slow" @ --to unix:/tmp/none ls
  [ "$status" -eq 0 ] && [ "$output" = "REAL kitty @ --to unix:/tmp/none ls" ] || false
  [ ! -e "$R/state/kitty-delay.log" ]
}

@test "kitty_ls_fail: the table is go-relative epochs; a matrix without the key writes an empty one" {
  printf '{"kitty_ls_fail": {"from": 60, "for": 480}, "groups": []}\n' > "$R/m.json"
  run rl kitty-ls-fail "$R/m.json" "$R" 1000
  [ "$(cat "$R/faults/kitty-ls-fail.tsv")" = "$(printf '1060\t1540')" ]
  run rl kitty-ls-fail "$RIGD/faults/move9.json" "$R" 1000
  [ "$output" = "kitty ls fail: none" ] && [ ! -s "$R/faults/kitty-ls-fail.tsv" ]
}

# ── move_batch: rows, queueing and T5 ─────────────────────────────────────────────────────────────

@test "move_batch: extra rows are idle panes on their own account, members keep their batch index" {
  run py -c 'import json,sys; sys.path.insert(0,sys.argv[1]); import rig_lib
f = json.load(open(sys.argv[2]))
rig_lib.extra_specs(f, sys.argv[3] + "/specs-extra.json")
json.dump(rig_lib.expand(f), open(sys.argv[3] + "/specs.json", "w"))' "$RIGD" "$RIGD/faults/move9.json" "$R"
  [ "$status" -eq 0 ] && [ "$output" = 1 ] || false
  run rl pane-rows "$R"
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 10 ]
  [ "$(printf '%s\n' "$output" | awk -F'\t' '$1 == 200 { print $4 }')" = .claude-tertiary ]
  [ "$(printf '%s\n' "$output" | awk -F'\t' '$1 == 1 { print $4 }')" = .claude-next ]
  run py -c 'import json,sys
x = json.load(open(sys.argv[1] + "/specs-extra.json"))[0]; m = json.load(open(sys.argv[1] + "/specs.json"))
print(x["move_batch"], x["knobs"]["idle"], x["knobs"]["kitty_delay_k"], [s["move_batch"] for s in m if s["group"] == "t5-subject"])' "$R"
  [ "$output" = "0 True 12 [1]" ]
}

@test "move_batch: the queue is the operator's cc-lr move, origin in its env; LR_RIG_MOVE_SLOTS wins" {
  run py -c 'import json,sys; sys.path.insert(0,sys.argv[1]); import rig_lib
b = rig_lib.batches(json.load(open(sys.argv[2])))[0]
print(" ".join(rig_lib.queue_argv("/tmp/lrh-x-cure", b, ["s1", "s2"], "/T")[6:]))' "$RIGD" "$RIGD/faults/shed-e1.json"
  [ "$output" = "/usr/bin/env CC_LR_MOVE_ORIGIN=shed /T/bin/cc-lr move --sids s1,s2 --to next4 --slots 1 --until-idle 600 --wait 0 --target-unverified" ]
  LR_RIG_MOVE_SLOTS=4 run py -c 'import json,sys; sys.path.insert(0,sys.argv[1]); import rig_lib
b = rig_lib.batches(json.load(open(sys.argv[2])))[0]
a = rig_lib.queue_argv("/tmp/lrh-x-red", b, ["s1"], "/T"); print(a[a.index("--slots") + 1])' "$RIGD" "$RIGD/faults/shed-e1.json"
  [ "$output" = 4 ]
}

@test "move_batch: the drive queues each batch at go + at, once, and attributes it to its batch dir" {
  mkdir -p "$R/T/bin"
  # a cc-lr that does what the real one leaves on disk: a plan naming the rows, and the request
  cat > "$R/T/bin/cc-lr" <<'EOF'
#!/bin/bash
sids=$3 b="B-$$"; mkdir -p "$LR_STATE_DIR/move/$b"
printf '%s\n' "$sids" | tr , '\n' | /usr/bin/python3 -c 'import json,sys; print(json.dumps({"origin": sys.argv[1], "slots": 1, "rows": [{"sid": l.strip()} for l in sys.stdin]}))' "${CC_LR_MOVE_ORIGIN:-}" > "$LR_STATE_DIR/move/$b/plan.json"
printf '%s\n' "$*" >> "$LR_RIG/state/cc-lr.argv"; exit 1
EOF
  chmod +x "$R/T/bin/cc-lr"
  printf 'export LR_RIG=%s HOME=%s LR_STATE_DIR=%s PATH=/usr/bin:/bin\n' "$R" "$HOME" "$LR_STATE_DIR" > "$R/env.sh"
  printf '[{"n":1,"sid":"m1","move_batch":null},{"n":2,"sid":"m2","move_batch":0}]\n' > "$R/specs.json"
  printf '[{"n":200,"sid":"x1","move_batch":0}]\n' > "$R/specs-extra.json"
  printf '{"groups":[],"move_batch":{"rows":1,"groups":["g"],"slots":1,"at":30,"origin":"shed"}}\n' > "$R/m.json"
  LR_RIG_REPO="$R/T" run py -c 'import json,sys,time; sys.path.insert(0,sys.argv[1]); import rig_lib
q = rig_lib.MoveQueue(sys.argv[2], json.load(open(sys.argv[3])))
q.step(1000.0, 1029.0); assert not q.live and not q.done, "queued before go + at"
q.step(1000.0, 1030.0)
for _ in range(300):
    if q.done: break
    time.sleep(0.1); q.step(1000.0, 1031.0)
q.step(1000.0, 1040.0); assert not q.live, "re-queued a batch already queued"
print(json.dumps(q.done[0]["sids"]), q.done[0]["plan_origin"], q.done[0]["rc"], q.done[0]["batch"].startswith("B-"))' "$RIGD" "$R" "$R/m.json"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | tail -1)" = '["x1", "m2"] shed 1 True' ]
  [ "$(grep -c . "$R/state/cc-lr.argv")" -eq 1 ]                       # once, never re-queued
  [ "$(cut -f2- "$R/state/faults.log" | cut -f1,2)" = "$(printf 'x1\tmove_batch\nm2\tmove_batch')" ]
  grep -q '"batch": "B-' "$R/state/move-batches.json"
}

# ── the T5 subject: stub knob idle_then_limit (tests/rig-stub.bats's pty idiom and band skip) ─────

need_band() { # read with ps, not python: at PRI 4 a python start is the cost being avoided
  b="$(ps -o pri= -p $$ 2>/dev/null | tr -d ' ')"
  case "$b" in ''|*[!0-9]*) skip "band unreadable ($b)" ;; esac
  [ "$b" -ge 20 ] || skip "band $b < 20 (postland background QoS)"
}
under_pty() { # BOUND LINGER UNTIL CMD… → rc 0 once UNTIL holds (then LINGER s more), 1 at BOUND
  /usr/bin/python3 -I -c '
import atexit, os, pty, select, signal, subprocess, sys, time
bound, linger, until, cmd = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3], sys.argv[4:]
pid, fd = pty.fork()
if pid == 0:
    os.execv(cmd[0], cmd)
# Every exit path (atexit, and a TERM/ALRM/INT/HUP to this driver) reaps: a hangup to the child, a
# grace that keeps draining, then SIGKILL to its whole group WHILE THE MASTER IS OPEN, master last
# (incident 2026-10-25: a pty child left alive under a closed master wedged /dev).
def reap(grace=5.0, sink=None, done=[]):
    if done:
        return
    done.append(1)
    try:
        os.kill(pid, signal.SIGHUP)
    except OSError:
        pass
    t = time.time() + grace
    while time.time() < t:
        try:
            if os.waitpid(pid, os.WNOHANG)[0]:
                break
        except OSError:
            break
        if select.select([fd], [], [], 0.05)[0]:
            try:
                d = os.read(fd, 65536)
                if sink is not None:
                    sink(d)
            except OSError:
                time.sleep(0.05)
    try:
        os.killpg(pid, signal.SIGKILL)
    except OSError:
        pass
    try:
        os.waitpid(pid, 0)
    except OSError:
        pass
    os.close(fd)
atexit.register(reap)
for s in (signal.SIGTERM, signal.SIGALRM, signal.SIGINT, signal.SIGHUP):
    signal.signal(s, lambda n, f: sys.exit(128 + n))
t0, ok, end = time.time(), False, None
while time.time() - t0 < bound and (end is None or time.time() < end):
    if select.select([fd], [], [], 0.25)[0]:
        try:
            os.read(fd, 65536)
        except OSError:
            break
    if end is None and subprocess.call(["/bin/sh", "-c", until]) == 0:
        ok, end = True, time.time() + linger
reap(5.0, None)
sys.exit(0 if ok else 1)' "$@"
}
stub_at_rest() { # SID KNOBS → boot the stub behind an open go barrier; linger 4 s past its boot
  export LR_RIG_SPECS="$R/specs" CLAUDE_CONFIG_DIR="$HOME/cfg" CC_PANE_ID=77
  mkdir -p "$LR_RIG_SPECS" "$CLAUDE_CONFIG_DIR" "$R/work"; : > "$R/go"
  printf '{"knobs":%s}\n' "$2" > "$LR_RIG_SPECS/$1.json"
  under_pty 60 4 "[ -e '$R/tmp/boot/$1.ok' ]" \
    /bin/sh -c "cd '$R/work' && exec /usr/bin/python3 '$RIGD/stub-claude.py' --session-id $1"
}
tx_of() { find "$HOME" -name "$1.jsonl" | head -1; }

@test "stub idle_then_limit: at rest from boot, then at go + die_at_s a user turn that hits the limit" {
  need_band
  sid=77777777-0000-4000-8000-0000000000b5
  run stub_at_rest "$sid" '{"go_barrier":true,"idle":true,"idle_then_limit":true,"die_at_s":2}'
  [ "$status" -eq 0 ]
  tx="$(tx_of "$sid")"
  [ "$(grep -c quotaLimits "$tx")" -eq 1 ]
  # the record before the limit is the turn's prompt: a session at rest is limited only by a turn
  [ "$(tail -2 "$tx" | head -1 | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["type"])')" = user ]
  /usr/bin/python3 -c 'import json,sys; assert json.load(open(sys.argv[1])).get("died_at")' "$R/tmp/stub/$sid.json"
}

@test "stub idle without idle_then_limit stays at rest past go + die_at_s (the knob is what kills it)" {
  need_band
  sid=77777777-0000-4000-8000-0000000000b6
  run stub_at_rest "$sid" '{"go_barrier":true,"idle":true,"die_at_s":2}'
  [ "$status" -eq 0 ]
  [ "$(grep -c quotaLimits "$(tx_of "$sid")")" -eq 0 ]
}

# T5 fixtures: one member queued in batch 1 that turned limited at 1000.0, its record, its result row
t5_fixture() { # VERDICT REASON RELEASE_DELAY_S OUTCOME
  printf '[{"n":9,"sid":"subj-0001","move_batch":1,"knobs":{}},{"n":1,"sid":"m1","move_batch":null,"knobs":{}}]\n' > "$R/specs.json"
  mkdir -p "$R/tmp/stub" "$R/state/sessions" "$R/lr/move/B2"
  local died=$(( $(date +%s) - 600 ))   # ONE clock read: the release mtime is died + delay exactly
  printf '{"died_at": %s}\n' "$died" > "$R/tmp/stub/subj-0001.json"
  printf '{"sid":"subj-0001","terminal":{"outcome":"%s"}}\n' "$4" > "$R/state/sessions/subj-0001.json"
  if [ -n "$1" ]; then
    printf '{"sid":"subj-0001","verdict":"%s","reason":"%s"}\n' "$1" "$2" > "$R/lr/move/B2/subj-0001.json"
    touch -t "$(date -r $(( died + $3 )) +%Y%m%d%H%M.%S)" "$R/lr/move/B2/subj-0001.json"
  fi
}
T5_OK="became-limited: its last record is now a limit error, so it owes a turn this lane does not type; nothing touched. Hands-off recovery is on and the reconciler is live, so the reconciler recovers it; watch it: cc-lr status subj-000"
t5v() { py -c 'import json,sys; print(json.load(open(sys.argv[1]))["t5"]["v"])' "$R/rig-result.json"; }

@test "T5 PASS: let go as became-limited within the bound, handed to the reconciler, and driven" {
  t5_fixture NOTMOVED "$T5_OK" 40 ENGAGED
  run rl t5 "$R"
  [ "$status" -eq 0 ]
  [[ "$output" == "T5 move lane: PASS · 1 queued member(s) turned limited" ]] || false
  [ "$(t5v)" = PASS ]
}

@test "T5 FAIL: held through the slot wait (let go long after its limit)" {
  t5_fixture NOTMOVED "$T5_OK" 400 ENGAGED
  run rl t5 "$R"
  [[ "$output" == *"FAIL"*"let go 400s after its limit (bound 120s)"* ]] || false
  [ "$(t5v)" = FAIL ]
}

@test "T5 FAIL: still held (no release row), not became-limited, no hand-over, or not driven" {
  t5_fixture "" "" 0 ENGAGED
  run rl t5 "$R"
  [[ "$output" == *"no release: the lane still holds it"* ]] || false
  t5_fixture NOTMOVED "slot-wait: no move slot freed in 600s" 40 ENGAGED
  run rl t5 "$R"
  [[ "$output" == *"not let go as became-limited"* ]] || false
  t5_fixture NOTMOVED "became-limited: … Recover it: cc-lr recover subj-000" 40 ENGAGED
  run rl t5 "$R"
  [[ "$output" == *"without handing it to the reconciler"* ]] || false
  t5_fixture NOTMOVED "$T5_OK" 40 IMPOSSIBLE
  run rl t5 "$R"
  [[ "$output" == *"not driven by the reconciler (outcome IMPOSSIBLE)"* ]] || false
  [ "$(t5v)" = FAIL ]
}

@test "T5 NO-VERDICT when no queued member turned limited (the fault did not fire)" {
  t5_fixture NOTMOVED "$T5_OK" 40 ENGAGED
  printf '{}\n' > "$R/tmp/stub/subj-0001.json"
  run rl t5 "$R"
  [[ "$output" == "T5 move lane: NO-VERDICT · 0 queued member(s) turned limited" ]]
}

@test "load_lib reads the rig's T5: XPASS/XFAIL while target:A7, NO-VERDICT without a move batch" {
  RUN="$BATS_TEST_TMPDIR/run"; cp -R "$REPO/tests/fixtures/lr-load-harness/pair" "$RUN"
  res5() { py -c 'import json,sys; r=json.load(open(sys.argv[1]))["res"]["T5"]; print(r["v"], r["mode"], r["n"])' "$RUN/cure/summary.json"; }
  py "$RIGD/load_lib.py" assert "$RUN" cure >/dev/null || true
  [ "$(res5)" = "NO-VERDICT target:A7 0" ]
  # collect carries the arm root's rig-result.json t5 into arm.json (an otherwise empty arm root)
  C="$BATS_TEST_TMPDIR/collect"; cp -R "$REPO/tests/fixtures/lr-load-harness/pair" "$C"
  mkdir -p "$R/arm"; printf '{"t5": {"v": "PASS", "n": 1, "fail": []}}\n' > "$R/arm/rig-result.json"
  py -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["arms"]["cure"]["root"]=sys.argv[2]; json.dump(d,open(p,"w"))' "$C/meta.json" "$R/arm"
  py "$RIGD/load_lib.py" collect "$C" cure >/dev/null || true
  [ "$(py -c 'import json,sys; print(json.load(open(sys.argv[1]))["t5"]["v"])' "$C/cure/arm.json")" = PASS ]
  py -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["t5"]={"v":"PASS","n":1,"fail":[]}; json.dump(d,open(p,"w"))' "$RUN/cure/arm.json"
  py "$RIGD/load_lib.py" assert "$RUN" cure >/dev/null || true
  [ "$(res5)" = "XPASS target:A7 1" ]
  py -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["t5"]={"v":"FAIL","n":1,"fail":["x"]}; json.dump(d,open(p,"w"))' "$RUN/cure/arm.json"
  py "$RIGD/load_lib.py" assert "$RUN" cure >/dev/null || true
  [ "$(res5)" = "XFAIL target:A7 1" ]
}

@test "the W4b matrices expand, and each one's expected line is all ENGAGED" {
  for m in move9 shed-e1 kitty-deaf; do
    run rl expected "$RIGD/faults/$m.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "ENGAGED "* ]] || { echo "$m: $output"; false; }
  done
  run py -c 'import json,sys; sys.path.insert(0,sys.argv[1]); import rig_lib
for m in ("move9", "shed-e1", "kitty-deaf", "guarantee30"):
    f = json.load(open(sys.argv[2] + "/" + m + ".json"))
    print(m, len(rig_lib.expand(f)), sum(b["rows"] for b in rig_lib.batches(f)))' "$RIGD" "$RIGD/faults"
  [ "$output" = "$(printf 'move9 9 1\nshed-e1 9 4\nkitty-deaf 6 0\nguarantee30 30 4')" ]
}
