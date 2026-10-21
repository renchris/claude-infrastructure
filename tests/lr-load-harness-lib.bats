#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # each @test is its own subshell
# tests/rig/load_lib.py and the live harness's pieces (B1 §9.11, LR_SUSTAINED_LOAD W4), in the land gate.
#
# The verdict logic runs on a COLLECTED fixture pair (tests/fixtures/lr-load-harness/pair: members,
# arm facts and samples, the shape `load_lib.py collect` writes); each case copies it and changes the
# one fact it is about. No case holds a wall-clock bound: the gate runs bats at utility and postland at
# background QoS, where a wall-clock test reads the band, not the code (B1 §12). Cases that start the
# stub on a pty skip below band 20 (C11). The loadgen stop case (--bg 200) is Tier-L preflight only:
# `bash tests/rig/lr-load-harness.sh preflight --selftest`.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  RIGD="$REPO/tests/rig"
  LIB="$RIGD/load_lib.py"
  export HOME="$BATS_TEST_TMPDIR/home" LR_STATE_DIR="$BATS_TEST_TMPDIR/lr" LR_RECON_ROOT="$BATS_TEST_TMPDIR/state"
  export TMPDIR="$BATS_TEST_TMPDIR/t" LR_HARNESS_DIR="$BATS_TEST_TMPDIR/h"
  mkdir -p "$HOME" "$TMPDIR" "$LR_RECON_ROOT"
  RUN="$BATS_TEST_TMPDIR/run"
  cp -R "$REPO/tests/fixtures/lr-load-harness/pair" "$RUN"
}

py() { /usr/bin/python3 -I "$@"; }
# edit FILE CODE: load FILE (JSON) as d, run CODE, write it back
edit() { py -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); exec(sys.argv[2]); json.dump(d,open(p,"w"))' "$1" "$2"; }
# members ARM CODE: run CODE on every member m of ARM (members.jsonl), in order (i = index)
members() {
  py -c 'import json,sys
p=sys.argv[1]; ms=[json.loads(l) for l in open(p)]
for i,m in enumerate(ms): exec(sys.argv[2])
open(p,"w").write("".join(json.dumps(m)+"\n" for m in ms))' "$RUN/$1/members.jsonl" "$2"
}
verdict() { # assert both arms, then pair; leaves the pair's output/status in $output/$status
  py "$LIB" assert "$RUN" cure >/dev/null || true
  [ -d "$RUN/red" ] && { py "$LIB" assert "$RUN" red >/dev/null || true; }
  run py "$LIB" pair "$RUN"
}
res() { py -c 'import json,sys; print(json.load(open(sys.argv[1]))["res"][sys.argv[2]]["v"])' "$RUN/$1/summary.json" "$2"; }
pre() { py -c 'import json,sys; print(json.load(open(sys.argv[1]))["pre"][sys.argv[2]]["ok"])' "$RUN/$1/summary.json" "$2"; }

# ── the pair verdict (§8.4, C8) ────────────────────────────────────────────────────────────────────

@test "fixture pair: the cure passes every hard row, the red arm fails T1 and H3 → POWER via outcome → PASS, exit 0" {
  verdict
  [ "$status" -eq 0 ]
  [[ "$output" == *"POWER via H3,T1 → PASS" ]] || false
  [[ "$output" == *"lanes: reconciler"* ]] || false       # F19: the lane coverage is stated
  [[ "$output" == *"cure band 31 (31/31) · load/core p50 24.0"* ]] || false # every reading carries load and band
  [ "$(res cure H3)" = PASS ] && [ "$(res red H3)" = FAIL ] && [ "$(res red T1)" = XFAIL ]
}

@test "the red arm passing everything the cure passes is SIGNAL-DEAD, exit 4" {
  cp "$RUN/cure/members.jsonl" "$RUN/red/members.jsonl"
  verdict
  [ "$status" -eq 4 ]
  [[ "$output" == *"SIGNAL-DEAD"* ]]
}

@test "power only through pass length (T2) prints PASS (power: pass-length only), exit 5" {
  cp "$RUN/cure/members.jsonl" "$RUN/red/members.jsonl"
  edit "$RUN/red/arm.json" 'd["band_log"] = [[1000.0 + 400 * i, 20] for i in range(4)]'   # 400 s passes
  verdict
  [ "$status" -eq 5 ]
  [[ "$output" == *"POWER via T2 → PASS (power: pass-length only)" ]]
}

@test "P1: a cure band.log line at 20 is NO-VERDICT band, exit 3 — never PASS, never FAIL" {
  edit "$RUN/cure/arm.json" 'd["band_log"][3][1] = 20'
  verdict
  [ "$status" -eq 3 ]
  [ "$(pre cure P1)" = False ]
  [[ "$output" == *"NO-VERDICT"* && "$output" == *"P1(band.log"* ]]
}

@test "P1: an in-path read below 31 in the cure arm (a short-lived placer) is NO-VERDICT band (F14)" {
  edit "$RUN/cure/arm.json" 'd["band_calls"][1][2] = 20'
  verdict
  [ "$status" -eq 3 ]
  [ "$(pre cure P1)" = False ]
}

@test "P2: half the census samples below the premise floor is NO-VERDICT load, exit 3" {
  py -c 'import json,sys
p=sys.argv[1]; rows=[json.loads(l) for l in open(p)]
for i,r in enumerate(rows):
    if "runq" in r and i % 2: r["load"][0] = 100.0
open(p,"w").write("".join(json.dumps(r)+"\n" for r in rows))' "$RUN/samples.jsonl"
  verdict
  [ "$status" -eq 3 ]
  [ "$(pre cure P2)" = False ]
}

@test "P2: load above the floor but no runnable base-31 thread per P-core is still NO-VERDICT load" {
  py -c 'import json,sys
p=sys.argv[1]; rows=[json.loads(l) for l in open(p)]
for r in rows:
    if "runq" in r: r["runq"]["31"] = 2
open(p,"w").write("".join(json.dumps(r)+"\n" for r in rows))' "$RUN/samples.jsonl"
  verdict
  [ "$status" -eq 3 ]
}

@test "a reaper TERM of an arm process during the run is NO-VERDICT reaper, exit 3" {
  printf '{"reason":"reaper","t":1500}\n' > "$RUN/abort.json"
  verdict
  [ "$status" -eq 3 ]
  [[ "$output" == *"NO-VERDICT (aborted: reaper"* ]] || false
  [ "$(pre cure P0)" = False ] && [ "$(pre red P0)" = False ]
}

@test "P3: a fault that did not fire takes that member's rows out, and over 20% unfired is NO-VERDICT" {
  members cure 'm["fault_fired"] = False if i == 1 else m["fault_fired"]'
  verdict
  [ "$status" -eq 3 ]
  [ "$(pre cure P3)" = False ]
  n="$(py -c 'import json,sys; print(json.load(open(sys.argv[1]))["res"]["H6"]["n"])' "$RUN/cure/summary.json")"
  [ "$n" = 1 ]                                            # only the member whose fault fired is judged
}

@test "targets: T4 failing is XFAIL[A6] and passing is XPASS; neither fails the pair" {
  members cure 'm["self_claim"] = 1 if i == 0 else 0'
  verdict
  [ "$status" -eq 0 ]
  [ "$(res cure T4)" = XFAIL ]
  [ "$(res cure T2)" = XPASS ]
  [[ "$output" == *"T4 XFAIL[A6]"* ]]
}

@test "member scope: a scoped H3 failure is XFAIL under its owner and does not fail the cure arm" {
  members cure 'm["scope"] = {"H3": "target:A6"} if i == 0 else {}; m["closed_at"] = 9999.0 if i == 0 else m["closed_at"]'
  verdict
  [ "$status" -eq 0 ]
  [ "$(res cure 'H3[A6]')" = XFAIL ]
  [ "$(res cure H3)" = PASS ]
}

# ── hard rows read from the world (S8, C3-C5, F25) ─────────────────────────────────────────────────

@test "H2 by outcome: an ESCALATED member whose expect is ENGAGED fails the cure arm, exit 1" {
  members cure 'm["escalated"] = (i == 0)'
  verdict
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL (cure: H2)" ]]
}

@test "H6: a retry later than the 2nd pass boundary after the daemon's own promise fails" {
  members cure '
if i == 1: m["attempts"][1]["t_spawn"] = m["attempts"][0]["nea"] + 25'
  verdict
  [ "$status" -eq 1 ]
  [ "$(res cure H6)" = FAIL ]
}

@test "H6: an admission wait named by an event between the promise and the retry moves the bound" {
  members cure '
if i == 1:
    m["attempts"][1]["t_spawn"] = m["attempts"][0]["nea"] + 25
    m["admit_waits"] = [m["attempts"][0]["nea"] + 20]   # a boot-slot wait: the 2nd boundary after it is later'
  verdict
  [ "$status" -eq 0 ]
  [ "$(res cure H6)" = PASS ]
}

@test "H7: one submit token in two user records fails the cure arm (a double-delivered prompt)" {
  members cure 'm["tokens_dup"] = ["run:11111111:20261021T090000Z:deadbeef"] if i == 0 else []'
  verdict
  [ "$status" -eq 1 ]
  [ "$(res cure H7)" = FAIL ]
}

@test "H9: two live holders of one sid, or a transcript live in two stores, fails the cure arm" {
  members cure 'm["holders"] = 2 if i == 0 else 1'
  verdict
  [ "$status" -eq 1 ]
  [ "$(res cure H9)" = FAIL ]
  members cure 'm["holders"] = 1; m["stores"] = 2 if i == 1 else 1'
  verdict
  [ "$(res cure H9)" = FAIL ]
}

@test "H8: a draft cleared or sent fails; a draft still held passes" {
  members cure 'm["draft_ok"] = False if i == 0 else None'
  verdict
  [ "$(res cure H8)" = FAIL ]
  members cure 'm["draft_ok"] = True if i == 0 else None'
  verdict
  [ "$(res cure H8)" = PASS ]
}

@test "H4: a hard hold that paged by entry + max age + 2 passes passes; one whose window closed first is NO-VERDICT" {
  edit "$RUN/cure/arm.json" 'd["band_log"] = [[1000.0 + 10 * i, 31] for i in range(300)]'   # passes to 3990
  members cure '
if i == 0:
    m.update(expect="HOLD-DRAFT", terminal=None, closed_via=None, held_since=1200.0, paged_at=2105.0)'
  verdict
  [ "$(res cure H4)" = PASS ]
  members cure '
if i == 0: m["paged_at"] = None'
  verdict
  [ "$(res cure H4)" = FAIL ]
  edit "$RUN/cure/arm.json" 'd["band_log"] = [[1000.0 + 10 * i, 31] for i in range(80)]'    # ends at 1790
  verdict
  [ "$(res cure H4)" = NO-VERDICT ]
}

@test "H1: a load hold in the cure arm fails it; in the typed-relaunch arm it is reported, not judged" {
  members cure 'm["load_holds"] = 1 if i == 0 else 0'
  verdict
  [ "$status" -eq 1 ]
  [ "$(res cure H1)" = FAIL ]
  edit "$RUN/cure/arm.json" 'd["typed_relaunch"] = True'
  verdict
  [ "$(res cure H1)" = REPORT ]
}

# ── production first (S7) ──────────────────────────────────────────────────────────────────────────

@test "production gate: an idle PARKED-REBOOT row and an engaged row in its confirmation window proceed; an open limited BACKOFF row is NO-VERDICT" {
  P="$BATS_TEST_TMPDIR/prod"; mkdir -p "$P/sessions"
  printf '{"sid":"aaaaaaaa-1","kind":"idle","phase":"PRE-MOVE","substate":"PARKED-REBOOT","terminal":null}\n' > "$P/sessions/aaaaaaaa-1.json"
  printf '{"sid":"cccccccc-3","kind":"limited","phase":"PRE-MOVE","substate":"HOLD-DRAFT","terminal":null}\n' > "$P/sessions/cccccccc-3.json"
  printf '{"sid":"dddddddd-4","kind":"limited","phase":"EXITED","substate":null,"terminal":{"outcome":"ENGAGED"}}\n' > "$P/sessions/dddddddd-4.json"
  printf '{"sid":"ffffffff-6","kind":"limited","phase":"ENGAGED","substate":null,"terminal":null,"close":{"via":"ENGAGED"}}\n' > "$P/sessions/ffffffff-6.json"
  run py "$LIB" prod-gate "$P"
  [ "$status" -eq 0 ]
  printf '{"sid":"bbbbbbbb-2","kind":"limited","phase":"PRE-MOVE","substate":"BACKOFF","terminal":null}\n' > "$P/sessions/bbbbbbbb-2.json"
  run py "$LIB" prod-gate "$P"
  [ "$status" -eq 3 ]
  [[ "$output" == "NO-VERDICT production-busy: bbbbbbbb PRE-MOVE/BACKOFF"* ]]
}

@test "S7: production holding a record for a rig sid is reported (rc 1)" {
  P="$BATS_TEST_TMPDIR/prod"; mkdir -p "$P/sessions"
  printf '[{"sid":"eeeeeeee-5"}]\n' > "$BATS_TEST_TMPDIR/specs.json"
  run py "$LIB" prod-sids "$P" "$BATS_TEST_TMPDIR/specs.json"
  [ "$status" -eq 0 ]
  printf '{"sid":"eeeeeeee-5","kind":"limited","terminal":null}\n' > "$P/sessions/eeeeeeee-5.json"
  run py "$LIB" prod-sids "$P" "$BATS_TEST_TMPDIR/specs.json"
  [ "$status" -eq 1 ]
}

@test "lock: a live owner refuses a second run (NO-VERDICT lock); a dead owner's lock is taken over" {
  /bin/sleep 300 & owner=$!
  run py "$LIB" lock acquire "$BATS_TEST_TMPDIR/lock" run-a "$owner"
  [ "$status" -eq 0 ]
  run py "$LIB" lock acquire "$BATS_TEST_TMPDIR/lock" run-b "$$"
  [ "$status" -eq 3 ]
  [[ "$output" == "NO-VERDICT lock: run run-a"* ]] || false
  kill "$owner"; wait "$owner" 2>/dev/null || true
  run py "$LIB" lock acquire "$BATS_TEST_TMPDIR/lock" run-b "$$"
  [ "$status" -eq 0 ]
  grep -q '"run": "run-b"' "$BATS_TEST_TMPDIR/lock/owner.json"
}

# ── run length and the matrices (F13, C1) ──────────────────────────────────────────────────────────

@test "run length is derived from the matrix: guarantee9 needs go + 3780 s (busy 300 + 780 + 2·900 + 900)" {
  run py -c 'import json,sys; sys.path.insert(0,sys.argv[1]); import load_lib; print(int(load_lib.max_t_done(json.load(open(sys.argv[2])))))' "$RIGD" "$RIGD/faults/guarantee9.json"
  [ "$status" -eq 0 ]
  [ "$output" = 3780 ]
}

@test "expand: die_spread_s draws each death from the seed, a member's own death wins, the boot bin reaches the rest" {
  run py -c 'import json,sys; sys.path.insert(0,sys.argv[1]); import rig_lib
f=json.load(open(sys.argv[2])); a=rig_lib.expand(f); b=rig_lib.expand(f)
assert [s["knobs"].get("die_at_s") for s in a] == [s["knobs"].get("die_at_s") for s in b]
late=[s for s in a if s["group"]=="late-death"][0]["knobs"]; assert "die_at_s" not in late and late["busy_for_s"]==300
assert all(0 <= s["knobs"].get("die_at_s",0) <= 120 for s in a)
slow=[s for s in a if s["group"]=="slow-boot"][0]["knobs"]; assert slow["boot_delay_s"]==[190,300] and slow["boot_delay_bin"]["p90"]==212
assert all("boot_delay_bin" in s["knobs"] for s in a)
assert [s for s in a if s["group"]=="restart-mid-actuation"][0]["scope"]=={"H3":"target:A6","H6":"target:A6"}
print(len(a))' "$RIGD" "$RIGD/faults/guarantee9.json"
  [ "$status" -eq 0 ]
  [ "$output" = 10 ]
  run py -c 'import json,sys; sys.path.insert(0,sys.argv[1]); import rig_lib; print(len(rig_lib.expand(json.load(open(sys.argv[2])))))' "$RIGD" "$RIGD/faults/guarantee30.json"
  [ "$output" = 30 ]
}

@test "kitty-faults: windows.sid and the knobs make the wrapper's delay and send-text failure tables" {
  R="$BATS_TEST_TMPDIR/rig"; mkdir -p "$R"
  printf '[{"sid":"s1","knobs":{"kitty_delay_s":[2,15],"kitty_delay_k":3}},{"sid":"s2","knobs":{"send_text_fail_n":2}},{"sid":"s3","knobs":{}}]\n' > "$R/specs.json"
  printf '41\ts1\n42\ts2\n43\ts3\n' > "$R/windows.sid"
  run py "$RIGD/rig_lib.py" kitty-faults "$R"
  [ "$status" -eq 0 ]
  [ "$(cat "$R/faults/kitty-delay.tsv")" = "$(printf '41\t2\t15\t3')" ]
  [ "$(cat "$R/faults/kitty-fail.tsv")" = "$(printf '42\t2')" ]
}

# ── the fault wrapper (bash only: no python, valid at any band) ────────────────────────────────────

@test "kitty-slow: send_text_fail_n fails exactly N send-text calls for that window, then passes through" {
  export LR_RIG="$BATS_TEST_TMPDIR/rig" LR_RIG_REAL_KITTY=/bin/echo
  mkdir -p "$LR_RIG/faults" "$LR_RIG/state"
  printf '7\t2\n' > "$LR_RIG/faults/kitty-fail.tsv"
  rcs=""
  for _ in 1 2 3 4; do
    r=0; /bin/bash "$RIGD/kitty-slow" @ --to unix:/x send-text --match id:7 hi >/dev/null 2>&1 || r=$?
    rcs="$rcs$r"
  done
  [ "$rcs" = 1100 ]
  run /bin/bash "$RIGD/kitty-slow" @ --to unix:/x ls --match=id:7
  [ "$status" -eq 0 ]                                     # not send-text: never failed
  [ "$(grep -c fail "$LR_RIG/state/kitty-delay.log")" = 2 ]
  run /bin/bash "$RIGD/kitty-slow" @ send-text --match id:8 hi   # another window: untouched
  [ "$status" -eq 0 ]
}

@test "kitty-slow: with no fault table it execs the real binary with the arguments unchanged" {
  export LR_RIG="$BATS_TEST_TMPDIR/rig" LR_RIG_REAL_KITTY=/bin/echo
  mkdir -p "$LR_RIG"
  run /bin/bash "$RIGD/kitty-slow" @ --to unix:/x send-text --match "id:7" "a b"
  [ "$status" -eq 0 ]
  [ "$output" = "@ --to unix:/x send-text --match id:7 a b" ]
  K="$BATS_TEST_TMPDIR/app"; mkdir -p "$K"
  printf '#!/bin/sh\necho kitty "$@"\n' > "$K/kitty"; printf '#!/bin/sh\necho kitten "$@"\n' > "$K/kitten"; chmod +x "$K/kitty" "$K/kitten"
  run env LR_RIG_REAL_KITTY="$K/kitty" /bin/bash "$RIGD/kitten-slow" @ ls
  [ "$output" = "kitten @ ls" ]                                  # invoked as kitten-slow: the sibling kitten
}

# ── the fake placer (C1) ───────────────────────────────────────────────────────────────────────────

@test "fake placer: the seat model refuses at KMAX, --unassign frees the seat, the band is read in the call path" {
  R="$BATS_TEST_TMPDIR/rig"
  py "$RIGD/rig_lib.py" home "$R"
  export HOME="$R/home" LR_RECON_ROOT="$R/state"; mkdir -p "$LR_RECON_ROOT"
  export RIG_PLACE_KMAX=8 RIG_PLACE_OCCUPIED='{"next2":8,"next3":8,"next4":7}'
  printf '{"sid":"m1","src":"next","w":1,"assign_id":"m1"}\n' > "$BATS_TEST_TMPDIR/mv.jsonl"
  place() { py "$RIGD/fake-claude-accounts.py" --place --lane general --recovery --movers "$BATS_TEST_TMPDIR/mv.jsonl" --facts "$R/facts" --json; }
  run place
  [ "$status" -eq 0 ]
  [[ "$output" == *'"acct": "next4"'* ]] || false
  printf '{"acct":"next4","id":"x1","sid":"m9","w":1,"ttl_s":900}\n' > "$BATS_TEST_TMPDIR/as.jsonl"
  py "$RIGD/fake-claude-accounts.py" --assign-many "$BATS_TEST_TMPDIR/as.jsonl"
  run place
  [[ "$output" == *'"reason": "no-eligible"'* ]] || false
  py "$RIGD/fake-claude-accounts.py" --unassign x1
  run place
  [[ "$output" == *'"acct": "next4"'* ]] || false
  awk -F'\t' '$4=="placer" && $3 ~ /^[0-9]+$/ {n++} END {exit !(n >= 3)}' "$LR_RECON_ROOT/band-calls.log"
}

# ── the harness CLI: refusals that come before anything is read or created ─────────────────────────

@test "the harness refuses top-up load until the operator allows it (packet 4eee30ac4de4), and --kitty private" {
  run /bin/bash "$RIGD/lr-load-harness.sh" run --matrix "$RIGD/faults/guarantee9.json" --bg-topup 50
  [ "$status" -eq 2 ]
  [[ "$output" == *"packet 4eee30ac4de4"* ]] || false
  run /bin/bash "$RIGD/lr-load-harness.sh" run --matrix "$RIGD/faults/guarantee9.json" --df-topup 4
  [ "$status" -eq 2 ]
  run /bin/bash "$RIGD/lr-load-harness.sh" run --matrix "$RIGD/faults/guarantee9.json" --kitty private
  [ "$status" -eq 2 ]
  [[ "$output" == *"75bb72581c54"* ]] || false
  [ ! -e "$LR_HARNESS_DIR/last" ]
}

@test "a caller below band 31 is NO-VERDICT band:caller-clamped, exit 3, and creates nothing" {
  b="$(ps -o pri= -p $$ 2>/dev/null | tr -d ' ')"
  case "$b" in ''|*[!0-9]*) skip "band unreadable" ;; esac
  [ "$b" -ge 20 ] || skip "band $b < 20 (postland background QoS)"
  run /usr/sbin/taskpolicy -c utility /bin/bash "$RIGD/lr-load-harness.sh" run --matrix "$RIGD/faults/guarantee9.json"
  [ "$status" -eq 3 ]
  [[ "$output" == "NO-VERDICT band:caller-clamped"* ]] || false
  [ ! -e "$LR_HARNESS_DIR/last" ]
  [ -z "$(ls -A "$LR_HARNESS_DIR" 2>/dev/null)" ]
}

# ── the stub's new knobs (pty; skip below band 20) ─────────────────────────────────────────────────

need_band() {
  b="$(ps -o pri= -p $$ 2>/dev/null | tr -d ' ')"
  case "$b" in ''|*[!0-9]*) skip "band unreadable ($b)" ;; esac
  [ "$b" -ge 20 ] || skip "band $b < 20 (postland background QoS)"
}
under_pty() { # BOUND_S UNTIL_SH CMD…: run CMD on a pty until UNTIL_SH holds, then SIGHUP it
  py -c '
import os, pty, select, signal, subprocess, sys, time
bound, until, cmd = float(sys.argv[1]), sys.argv[2], sys.argv[3:]
log = open(os.environ.get("PTY_LOG", os.devnull), "ab")
pid, fd = pty.fork()
if pid == 0:
    os.execv(cmd[0], cmd)
t0, ok = time.time(), False
while time.time() - t0 < bound:
    if select.select([fd], [], [], 0.25)[0]:
        try:
            log.write(os.read(fd, 65536))
        except OSError:
            break
    if subprocess.call(["/bin/sh", "-c", until]) == 0:
        ok = True
        break
os.kill(pid, signal.SIGHUP)
# keep draining: an exiting child blocks in tty drain while its output sits unread (a deadlock)
for _ in range(400):
    if select.select([fd], [], [], 0.05)[0]:
        try:
            log.write(os.read(fd, 65536))
        except OSError:
            pass
    if os.waitpid(pid, os.WNOHANG)[0]:
        break
else:
    os.kill(pid, signal.SIGKILL)
    os.waitpid(pid, 0)
sys.exit(0 if ok else 1)' "$@"
}

@test "stub death knobs: a late death writes its partial before the limit, the goal-meta record sits 1 s before it, the heavy lead's subagents fall in the window" {
  need_band
  sid=77777777-0000-4000-8000-000000000007
  export LR_RIG="$BATS_TEST_TMPDIR/rig" LR_RIG_SPECS="$BATS_TEST_TMPDIR/rig/specs" CLAUDE_CONFIG_DIR="$HOME/cfg"
  mkdir -p "$LR_RIG_SPECS" "$BATS_TEST_TMPDIR/work" "$HOME/cfg"
  printf '{"knobs":{"go_barrier":true,"busy_for_s":2,"goal_meta_after_limit":true,"heavy_lead_subagents":3,"composer_unreadable_s":30}}\n' > "$LR_RIG_SPECS/$sid.json"
  W="$(cd "$BATS_TEST_TMPDIR/work" && pwd -P)"
  : > "$LR_RIG/go"
  export PTY_LOG="$BATS_TEST_TMPDIR/pty.log"
  # until: the garbled frame (a fixture row, no input box) has reached the pty, which die() paints last
  run under_pty 120 "grep -q subagents_written '$LR_RIG/tmp/stub/$sid.json' 2>/dev/null && grep -q '▒░ ▒▒ ░▒▒' '$PTY_LOG'" \
    /bin/sh -c "cd '$W' && exec /usr/bin/python3 '$RIGD/stub-claude.py' --session-id $sid"
  [ "$status" -eq 0 ]
  tx="$(find "$HOME/cfg" -name "$sid.jsonl" | head -1)"
  py -c 'import json,sys,os,time,glob
rows=[json.loads(l) for l in open(sys.argv[1])]
kinds=[("limit" if "quotaLimits" in r else "meta" if r.get("isMeta") else r.get("type")) for r in rows]
i=kinds.index("limit"); assert kinds[i-1]=="assistant", kinds          # the partial, then the limit
assert kinds[i+1]=="meta", kinds                                       # written after the limit…
iso=lambda r: time.mktime(time.strptime(r["timestamp"][:19],"%Y-%m-%dT%H:%M:%S")) + float(r["timestamp"][19:23] or 0)
assert iso(rows[i]) - iso(rows[i-1]) >= 1.5, (rows[i-1]["timestamp"], rows[i]["timestamp"])  # the partial predates the death (stamped at go)
assert rows[i+1]["timestamp"] < rows[i]["timestamp"], (rows[i+1]["timestamp"], rows[i]["timestamp"])  # …stamped before it
st=json.load(open(sys.argv[2])); d=st["died_at"]
assert st["busy_until"] >= d and st["garble_until"] >= d + 29
subs=glob.glob(os.path.join(os.path.dirname(sys.argv[1]), sys.argv[3], "subagents", "*.jsonl")); assert len(subs)==3
assert all(d - 600 <= os.path.getmtime(p) <= d for p in subs)' "$tx" "$LR_RIG/tmp/stub/$sid.json" "$sid"
  grep -q "stub	fresh" "$LR_RECON_ROOT/band-calls.log"          # the band, read in the call path
}

@test "stub boot draws: slow_boots takes the range first, then the bin's lognormal, each recorded" {
  sid=88888888-0000-4000-8000-000000000008
  export LR_RIG="$BATS_TEST_TMPDIR/rig" LR_RIG_SPECS="$BATS_TEST_TMPDIR/rig/specs"
  mkdir -p "$LR_RIG_SPECS"
  printf '{"knobs":{"boot_delay_s":[190,300],"slow_boots":1,"boot_delay_bin":{"median":46,"p90":212,"cap":300}}}\n' > "$LR_RIG_SPECS/$sid.json"
  run py -c 'import importlib.util,sys
s=importlib.util.spec_from_file_location("stub", sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
sess=m.Session(sys.argv[2], "/tmp/none", "/tmp")
ds=[m.boot_delay(sess) for _ in range(40)]
assert 190 <= ds[0] <= 300, ds[0]
assert all(0 < x <= 300 for x in ds[1:])
assert sorted(ds[1:])[19] < 190                     # the bin median (46 s) is far below the slow range
assert len(sess.state()["boots"]) == 40
print("ok")' "$RIGD/stub-claude.py" "$sid"
  [ "$status" -eq 0 ]
  [ "$output" = ok ]
}

@test "stub: a limited ACCOUNT refuses every session's next turn (go_barrier), so the limit is never contradicted" {
  export LR_RIG="$BATS_TEST_TMPDIR/rig" LR_RIG_SPECS="$BATS_TEST_TMPDIR/rig/specs"
  mkdir -p "$LR_RIG_SPECS" "$HOME/cfg-b/projects/-x"
  for s in 1 2; do printf '{"knobs":{"go_barrier":true}}\n' > "$LR_RIG_SPECS/9999999$s-0000-4000-8000-00000000000$s.json"; done
  run py -c 'import importlib.util,sys,os,json,time
s=importlib.util.spec_from_file_location("stub", sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
cfg=sys.argv[2]
def turn(sid):
    sess=m.Session(sid, cfg, "/x"); sess.mark(home_cfg="/elsewhere"); t=m.Tui(sess, resumed=True); t.submit("continue")
    return [("limit" if "quotaLimits" in json.loads(l) else json.loads(l).get("type")) for l in open(sess.tx)]
assert turn("99999991-0000-4000-8000-000000000001")[-1] == "assistant"      # the account is not limited yet
m.mark_limited(cfg, time.time() + 600)
assert turn("99999992-0000-4000-8000-000000000002")[-1] == "limit"          # now every session on it is
print("ok")' "$RIGD/stub-claude.py" "$HOME/cfg-b" >/dev/null
  [ "$status" -eq 0 ]
}
