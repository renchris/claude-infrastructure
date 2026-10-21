#!/usr/bin/env bats
# lr-recon-telemetry.bats — B6, wave W6 of docs/plans/LR_SUSTAINED_LOAD_IMPL.md: the reconciler's own
# telemetry (lr_recon/telemetry.py) and its one readout, `cc-lr status --rail`.
#
# T14: the unit suite runs under /usr/bin/python3 (3.9.6, the plist's interpreter), and the COUNT is
# asserted, not only the absence of failures ("Gate refusal ≠ gate result"). T15: the readout on
# fixtures written here by the real Telemetry writer (never *.log, which .gitignore ignores): an
# empty root is NO DATA rc 1, a low band is WARN, a fresh heartbeat over a stalled log is "telemetry
# stopped", and the --json keys are stable for agents and the load harness.
#
# HERMETIC: HOME, LR_STATE_DIR, LR_RECON_ROOT and TMPDIR live in BATS_TEST_TMPDIR. Every census and
# priority read is injected; nothing reads the live box, types anywhere or loads a job.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LR="$REPO/bin/cc-lr"
  export LR_DIR="$REPO/scripts/limit-recover"
  export HOME="$BATS_TEST_TMPDIR/home" TMPDIR="$BATS_TEST_TMPDIR/tmp"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export LR_RECON_ROOT="$LR_STATE_DIR/recon"
  mkdir -p "$HOME" "$TMPDIR" "$LR_RECON_ROOT/sessions"
  export LR_KITTEN_BIN=/usr/bin/false
}

# fixture <low-pid-or-0> <heartbeat pass_seq offset> <heartbeat age s> <log age s>: two passes
# written by the real writer with injected reads, then a heartbeat.
fixture() {
  touch "$TMPDIR/kitty-$$"
  PYTHONPATH="$LR_DIR" /usr/bin/python3 -I -c '
import json, os, sys, time
sys.path.insert(0, os.environ["LR_DIR"])
from lr_recon import telemetry, types as T
low, dseq, hb_age, log_age = (int(x) for x in sys.argv[1:5])
now = time.time()
clk = {"w": now - log_age, "m": 0.0}
paths = T.Paths.from_env()
t = telemetry.Telemetry(paths, env={}, wall=lambda: clk["w"], mono=lambda: clk["m"],
    thread_time=lambda: 0.0, read_pri=lambda pid=None: 20 if low and pid == low else 31,
    census=lambda: {"run": {"31": 4, "4": 9}, "thr": 40, "procs": 3, "of": 5},
    kitty_pri=lambda pid: (47, 47), loadavg=lambda: (150.0, 0, 0), thermal=lambda: 1,
    pressure=lambda: 1, kitty_glob=os.path.join(os.environ["TMPDIR"], "kitty-*"))
t.start(None, [])
procs = {low: T.ProcRow(low, 1, "S", "Tue Sep 29 11:19:17 2026", "/bin/bash /x/lr-move-worker.sh")} if low else {}
for i in range(2):
    t.pass_begin(i + 1)
    t.observed(T.Snapshot(wall=0.0, uptime_raw=0.0, procs=procs))
    t.gate("may", "backoff")
    clk["m"] += 31.0  # a full row each: a 2 s pass folds into the 300 s quiet row
    t.pass_end({"mode": "act", "open": 0}, None)
    t.box()
hb = {"pid": 4321, "lstart": "", "progress": 9, "wall": now - hb_age, "uptime_raw": 0.0,
      "progress_wall": now - hb_age, "phase": "idle", "phase_at": now, "pass_seq": 2 + dseq, "pass_at": 0.0}
json.dump(hb, open(paths.heartbeat, "w"))
' "$@"
}

@test "T14: the unit suite passes under /usr/bin/python3 (3.9), count asserted" {
  run /bin/bash -c 'cd "$LR_DIR" && /usr/bin/python3 -m unittest lr_recon.tests.test_telemetry 2>&1'
  [ "$status" -eq 0 ]
  n="$(printf '%s\n' "$output" | sed -n 's/^Ran \([0-9][0-9]*\) tests* in .*/\1/p')"
  [ -n "$n" ] && [ "$n" -ge 46 ] || false
  printf '%s\n' "$output" | grep -qx 'OK'
  /usr/bin/python3 -c 'import sys; assert sys.version_info[:2] == (3, 9), sys.version'
}

@test "T15: an empty root is NO DATA, rc 1, and never ok" {
  run "$LR" status --rail
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "reconciler: NO DATA"* ]] || false
  [[ "$output" != *"rail: ok"* ]]
}

@test "T15: a healthy fixture is ok, scoped to the reconciler, and names what it does not cover" {
  fixture 0 0 1 1
  run "$LR" status --rail
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "reconciler: ok — "* ]] || false
  [[ "${lines[1]}" == "not covered: move lane, boot-resume"* ]] || false
  [[ "$output" == *"gates  may:backoff 2"* ]] || false
  [[ "$output" == *"runnable by base priority 4:9 31:4 of 40 threads"* ]]
}

@test "T15: a rail process below 31 is WARN with its role, pid and band" {
  fixture 41234 0 1 1
  run "$LR" status --rail
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "reconciler: WARN — move-worker 41234 reads priority 20, below 31"* ]]
}

@test "T15: a fresh heartbeat over a log two passes behind and 20 min old is 'telemetry stopped'" {
  fixture 0 3 1 1200
  run "$LR" status --rail
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "reconciler: NO DATA — telemetry stopped (pass 5, newest row at pass 2"* ]]
}

@test "T15: a stale heartbeat is daemon down, never ok" {
  fixture 0 0 120 1
  run "$LR" status --rail
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "reconciler: NO DATA — daemon down"* ]]
}

@test "T15: --json keys are stable; --root reads another tree; --since narrows the window" {
  fixture 0 0 1 1
  mv "$LR_RECON_ROOT" "$BATS_TEST_TMPDIR/other"
  run "$LR" status --rail --json --since 30m --root "$BATS_TEST_TMPDIR/other"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin)
want = {"verdict", "scope", "reasons", "window_s", "daemon", "band", "box", "passes", "phases",
        "children", "gates", "admits", "spawns", "counters", "open", "other_lane", "closed",
        "telemetry", "not_covered"}
assert want <= set(d), sorted(want - set(d))
assert d["verdict"] == "ok" and d["scope"] == "reconciler" and d["window_s"] == 1800.0, d
assert d["gates"] == {"may:backoff": 2}, d["gates"]
'
}

@test "cc-lr status --rail refuses an unknown argument, rc 3, and usage names it" {
  run "$LR" status --rail --bogus
  [ "$status" -eq 3 ]
  run "$LR" status --help
  [[ "$output" == *"cc-lr status --rail [--since 1h|30m|90s] [--json] [--history] [--root DIR]"* ]]
}
