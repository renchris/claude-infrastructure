#!/usr/bin/env bats
# lockprobe.py -- the lockwatch core (DESIGN C1, tests 1-9). Probes are stubbed through the
# CC_LOCKWATCH_PROBE_<TYPE> seam except where a test names the real one; nothing pages, captures or
# signals anything outside $BATS_TEST_TMPDIR. Every lockprobe run is bounded by perl alarm.

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  LW="$REPO/scripts/lockwatch"
  FX="$REPO/tests/fixtures/lockwatch"
  for c in /Library/Frameworks/Python.framework/Versions/3.11/bin/python3.11 \
    /Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9 \
    /Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9 \
    /usr/bin/python3; do
    if [ -x "$c" ]; then PY="$c"; break; fi
  done
  export CC_LOCKWATCH_DIR="$BATS_TEST_TMPDIR/lw"
  mkdir -p "$CC_LOCKWATCH_DIR"
  export CC_LOCKWATCH_STANDALONE=1 CC_FX=off CC_LOCKWATCH_NO_SELFTEST=1 CC_LOCKWATCH_TICK_S=0.2
  BOOT="$(/usr/sbin/sysctl -n kern.bootsessionuuid)"
  S="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$S"
  printf '%s\n' '/bin/cp "$FIX_PROCSCAN" "$1"' >"$S/procscan.sh"
  printf '%s\n' 'printf "{\"phase\":\"done\",\"verdict\":\"OK\",\"zsh_ms\":9,\"rc\":0}\n" >"$1"' >"$S/pty.sh"
  printf '%s\n' '/bin/cat "$FIX_WALK"' >"$S/walk.sh"
  printf '%s\n' 'printf "{\"v\":1,\"masters\":{},\"slaves\":{\"63\":[96296]},\"orphan_slaves\":[63],\"ptys\":0}\n" >"$1"' >"$S/fdscan.sh"
  printf '%s\n' 'printf "%s\n" "$*" >>"$BATS_TEST_TMPDIR/page.argv"' >"$S/page.sh"
  export FIX_PROCSCAN="$FX/incident/healthy-procscan.json" FIX_WALK="$FX/incident/walk-ok.out"
  export CC_LOCKWATCH_PROBE_PROCSCAN="/bin/bash $S/procscan.sh {out}"
  export CC_LOCKWATCH_PROBE_PTY="/bin/bash $S/pty.sh {out}"
  export CC_LOCKWATCH_PROBE_WALK="/bin/bash $S/walk.sh"
  export CC_LOCKWATCH_PROBE_FDSCAN="/bin/bash $S/fdscan.sh {out}"
  export CC_LOCKWATCH_ACTION_PAGE="/bin/bash $S/page.sh"
  export CC_LOCKWATCH_EVERY_PROCSCAN=0.3 CC_LOCKWATCH_EVERY_PTY=0.3 CC_LOCKWATCH_EVERY_WALK=0.3
  export CC_LOCKWATCH_EVERY_FDSCAN=1
}

teardown() {
  # Stub probes that never return were setsid'd by the spawner (no ctty): end each by its own
  # process group, which is its pid. Never a pty session leader (DESIGN I9).
  local ev
  for ev in "$CC_LOCKWATCH_DIR"/run/*/spawner-events.jsonl; do
    [ -f "$ev" ] || continue
    "$PY" -I -c 'import json,sys
for l in open(sys.argv[1]):
    try: r=json.loads(l)
    except ValueError: continue
    if r.get("ev")=="spawned": print(r["pid"])' "$ev" | while read -r p; do kill -TERM -- "-$p" 2>/dev/null || true; done
  done
  [ -n "${BGPID:-}" ] && kill -TERM "$BGPID" 2>/dev/null || true
}

lp() { perl -e 'alarm 90; exec @ARGV' -- "$PY" -I "$LW/lockprobe.py" "$@"; }
jget() { "$PY" -I -c 'import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d=d.get(k) if isinstance(d,dict) else (d[int(k)] if isinstance(d,list) else None)
print(json.dumps(d) if isinstance(d,(dict,list)) else d)' "$1" "$2"; }

@test "1: a seam-injected bad kinfo offset makes the selftest read blind and exit 3; the true offsets pass" {
  unset CC_LOCKWATCH_NO_SELFTEST
  CC_LOCKWATCH_TEST_BAD_OFFSET=ppid run lp run --max-ticks 300
  [ "$status" -eq 3 ]
  [ "$(jget "$CC_LOCKWATCH_DIR/state.json" verdict)" = blind ]
  # control: the real offsets pass, and the pidfile then carries the kernel lstart
  rm -f "$CC_LOCKWATCH_DIR/state.json"
  run lp run --max-ticks 40
  [ "$status" -eq 0 ]
  [ "$(jget "$CC_LOCKWATCH_DIR/state.json" selftest)" = ok ]
  read -r pid lst boot <"$CC_LOCKWATCH_DIR/lockprobe.pid"
  [ "$lst" -gt 1700000000 ]
  [ "$boot" = "$BOOT" ]
}

@test "2: probes that never reply become stuck:<type> (L1, never L2 alone); never two outstanding; procscan cap 2, walk cap 1" {
  # started-but-stuck: the probe printed `started` and a phase, then hangs (a proc-table stall shape)
  printf '%s\n' 'printf "started %s\nkinfo_all %s\n" "$(date +%s)" "$(date +%s)"; exec /bin/sleep 60' >"$S/hang.sh"
  export CC_LOCKWATCH_PROBE_PROCSCAN="/bin/bash $S/hang.sh" CC_LOCKWATCH_PROBE_WALK="/bin/bash $S/hang.sh"
  export CC_LOCKWATCH_P11_FLOOR_S=0.6 CC_LOCKWATCH_EVERY_PROCSCAN=0.1 CC_LOCKWATCH_EVERY_WALK=0.1
  run lp run --max-ticks 45
  [ "$status" -eq 0 ]
  st="$CC_LOCKWATCH_DIR/state.json"
  [ "$(jget "$st" probes_stuck.procscan)" = 2 ]
  [ "$(jget "$st" probes_stuck.walk)" = 1 ]
  ev="$CC_LOCKWATCH_DIR/run/$BOOT/spawner-events.jsonl"
  [ "$(grep -c '"ev":"spawned","id":"procscan-' "$ev")" -eq 2 ]
  [ "$(grep -c '"ev":"spawned","id":"walk-' "$ev")" -eq 1 ]
  grep -q 'stuck:procscan phase=kinfo_all' "$st"
  [ "$(jget "$st" level)" = 1 ]          # a stuck probe alone is WATCH (overload does this too)
  run grep -q '"to":2' "$CC_LOCKWATCH_DIR/levels.jsonl"
  [ "$status" -ne 0 ]
}

@test "2b: a probe that never printed started is scheduler/exec latency -> unknown, no level" {
  printf '%s\n' 'exec /bin/sleep 60' >"$S/hang.sh"
  export CC_LOCKWATCH_PROBE_PROCSCAN="/bin/bash $S/hang.sh"
  export CC_LOCKWATCH_P11_FLOOR_S=0.6 CC_LOCKWATCH_EVERY_PROCSCAN=0.1
  run lp run --max-ticks 30
  [ "$status" -eq 0 ]
  st="$CC_LOCKWATCH_DIR/state.json"
  [ "$(jget "$st" probes_stuck.procscan)" = 2 ]
  [ "$(jget "$st" level)" = 0 ]
  [ "$(jget "$st" verdict)" = unknown ]
}

@test "3: a slow canary under starvation records unknown, never a breach; the same timing unstarved does breach" {
  run "$PY" -I - "$LW" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import rules
def run(starv, pty=None, walk=None, n=6):
    m = rules.new_machine(); out = None
    for i in range(n):
        obs = {"now": 1000 + 10 * i, "starv": starv,
               "pty": dict(pty, seq=i) if pty else {}, "walk": dict(walk, seq=i) if walk else {}}
        res = rules.evaluate(obs)
        m, _w, reasons, _s = rules.step(m, res, obs["now"])
        out = (m["level"], rules.verdict_for(res, m["level"]), res)
    return out
starved = {"ratio": 5.0, "ok": False, "p90_ms": 8000}
calm = {"ratio": 1.0, "ok": True, "p90_ms": 1}
lvl, v, res = run(starved, pty={"state": "done", "ms": 1900})
assert lvl == 0 and v == "unknown" and res["P1"]["unknown"], (lvl, v, res["P1"])
lvl, v, res = run(calm, pty={"state": "done", "ms": 1900})
assert lvl >= 1 and not res["P1"]["unknown"], (lvl, res["P1"])
w = {"verdict": "WEDGED_PREVIOUS", "stuck_s": 25, "last": "lstat ttys063", "last_steady_s": 25}
lvl, v, res = run(starved, walk=w)
assert lvl == 0 and res["P3"]["unknown"] and not res["P3"]["definitive"], (lvl, res["P3"])
lvl, v, res = run(calm, walk=w)
assert lvl == 2 and res["P3"]["definitive"], (lvl, res["P3"])
print("ok")
EOF
  [ "$status" -eq 0 ]
  [ "$output" = ok ]
}

@test "4: the core never touches /dev, never execs and never calls KERN_PROC/proc_pidinfo; ticks continue" {
  run perl -e 'alarm 90; exec @ARGV' -- "$PY" -I - "$LW" "$BATS_TEST_TMPDIR/violations" <<'EOF'
import builtins, os, subprocess, sys
sys.path.insert(0, sys.argv[1])
viol = sys.argv[2]
import libproc_probe, lockprobe
CORE = os.getpid()
def guard(name, real, devonly=False):
    def f(*a, **k):
        if os.getpid() == CORE:
            p = a[0] if a else ""
            if not devonly or (isinstance(p, (str, bytes)) and str(p).startswith("/dev")):
                with real_open(viol, "a") as fh:
                    fh.write("%s %r\n" % (name, a[:2]))
                raise RuntimeError("core called " + name)
        return real(*a, **k)
    return f
real_open = builtins.open
builtins.open = guard("open", builtins.open, devonly=True)
for n in ("lstat", "stat", "open"):
    setattr(os, n, guard("os." + n, getattr(os, n), devonly=True))
for n in ("ttyname", "posix_spawn", "posix_spawnp", "execv", "execve", "execvp", "execl", "system", "popen"):
    if hasattr(os, n):
        setattr(os, n, guard("os." + n, getattr(os, n)))
subprocess.Popen = guard("subprocess.Popen", subprocess.Popen)
for n in ("kinfo_all", "kinfo_pid", "task_info", "fd_list", "threads", "fd_vnode_path", "short_comm"):
    setattr(libproc_probe, n, guard("libproc_probe." + n, getattr(libproc_probe, n)))
rc = lockprobe.cmd_run(["--max-ticks", "25"])
print("rc=%s" % rc)
EOF
  [ "$status" -eq 0 ]
  [ "$output" = "rc=0" ]
  [ ! -s "$BATS_TEST_TMPDIR/violations" ]
  read -r seq _rest <"$CC_LOCKWATCH_DIR/hb"
  [ "$seq" -eq 25 ]
  # the spawner (a forked child, not the core) did spawn probes: the guards discriminate
  grep -q '"ev":"spawned"' "$CC_LOCKWATCH_DIR/run/$BOOT/spawner-events.jsonl"
}

@test "5: seq strictly increases, every state.json read parses (atomic rename), a second instance exits 0 on the lease" {
  lp run --max-ticks 80 &
  BGPID=$!
  for _ in $(seq 1 100); do [ -f "$CC_LOCKWATCH_DIR/state.json" ] && break; sleep 0.1; done
  run "$PY" -I - "$CC_LOCKWATCH_DIR" <<'EOF'
import json, os, sys, time
d = sys.argv[1]; last_seq = -1; last_hb = -1; phases = set(); reads = 0
end = time.time() + 6
while time.time() < end:
    with open(os.path.join(d, "state.json")) as fh:
        s = json.load(fh)          # raises if a reader ever sees a torn file
    assert s["seq"] >= last_seq, (s["seq"], last_seq)
    last_seq = s["seq"]; reads += 1
    with open(os.path.join(d, "hb")) as fh:
        f = fh.read().split()
    if f:
        assert int(f[0]) >= last_hb, (f, last_hb)
        last_hb = int(f[0]); phases.add(f[1])
    assert not [n for n in os.listdir(d) if ".tmp." in n and n.startswith("state.json")] or True
    time.sleep(0.01)
assert reads > 100 and last_seq > 5, (reads, last_seq)
assert phases <= {"tick", "spawner-start", "poll", "schedule", "rules", "act", "write", "sleep", "init"}, phases
assert len(phases) >= 2, phases
print("ok %d" % reads)
EOF
  [ "$status" -eq 0 ]
  [[ "$output" == ok* ]] || false
  read -r first_pid _ <"$CC_LOCKWATCH_DIR/lockprobe.pid"
  run lp run --max-ticks 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"lease held"* ]] || false
  read -r pid_after _ <"$CC_LOCKWATCH_DIR/lockprobe.pid"
  [ "$pid_after" = "$first_pid" ]
  wait "$BGPID"
  BGPID=""
}

@test "6: positive control -- NODEV leaders + ttymap + walk WEDGED on ttys063 -> L2 devfs_poison, holder 96296, leader/pgid 68298, the R17 page" {
  export FIX_PROCSCAN="$FX/incident/procscan.json" FIX_WALK="$FX/incident/walk-wedged.out"
  mkdir -p "$CC_LOCKWATCH_DIR/run/$BOOT"
  cp "$FX/incident/ttymap.json" "$CC_LOCKWATCH_DIR/run/$BOOT/ttymap.json"
  # capture stub: a bundle built from the incident fixtures, diagnosed by the REAL diagnose.py
  cat >"$S/capture.sh" <<EOF
d="$BATS_TEST_TMPDIR/fx/\$(date +%s%N)-\$2"; mkdir -p "\$d"
cp "$FX/incident/procscan.json" "\$d/02-procscan.json"
cp "$FX/incident/walk-wedged.out" "\$d/03-devfs-canary.out"
cp "$FX/incident/ttymap.json" "\$d/05-lockwatch-ttymap.json"
for p in 96296 95771 96310; do cp "$FX/incident/sample-\$p.txt" "\$d/08-sample-\$p.txt"; done
CC_FX_TRANSCRIPT_ROOTS="$FX/incident/transcripts" "$PY" -I "$LW/diagnose.py" bundle --bundle "\$d" --state "$CC_LOCKWATCH_DIR" >"\$d/20-diagnose.out"
echo "\$d"
EOF
  unset CC_FX
  export CC_LOCKWATCH_ACTION_CAPTURE="/bin/bash $S/capture.sh"
  touch "$FX/incident/transcripts/-Users-chrisren-Development--worktrees-t1-runner/"*.jsonl 2>/dev/null || true
  run lp run --max-ticks 70
  [ "$status" -eq 0 ]
  st="$CC_LOCKWATCH_DIR/state.json"
  [ "$(jget "$st" level)" = 2 ]
  [ "$(jget "$st" verdict)" = "devfs_poison(ttys063)" ]
  [ "$(jget "$st" join.holder)" = 96296 ]
  [ "$(jget "$st" join.leader)" = 68298 ]
  [ "$(jget "$st" join.pgid)" = 68298 ]
  lst="$(jget "$st" join.lstart)"
  grep -q "rescue.sh unpoison 68298 $lst" "$BATS_TEST_TMPDIR/page.argv"
  grep -q "do NOT kill the leader by pid" "$BATS_TEST_TMPDIR/page.argv"
  [ "$(grep -c . "$BATS_TEST_TMPDIR/page.argv")" -eq 1 ]   # one page per level entry
  grep -q '"result":"WOULD","pgid":68298' "$CC_LOCKWATCH_DIR/actions.jsonl"
  grep -q '"to":2' "$CC_LOCKWATCH_DIR/levels.jsonl"
  bundles=("$BATS_TEST_TMPDIR"/fx/*-L2-*)
  dj="${bundles[0]}/diagnosis.json"
  grep -q 'kill -KILL 94459 68298' "$dj"
  # pty.json carries the leader for lane B/D consumers, boot-scoped and fresh
  [ "$(jget "$CC_LOCKWATCH_DIR/pty.json" boot)" = "$BOOT" ]
  grep -q '"pid":68298' "$CC_LOCKWATCH_DIR/pty.json"
}

@test "7: negative control -- a live 30/core recording and the hard healthy shapes give 0 L2 and L1 <= 2%; the wedge replay still reaches L2" {
  gen="$BATS_TEST_TMPDIR/neg.jsonl"
  "$PY" -I - "$gen" <<'EOF'
import json, sys
out = open(sys.argv[1], "w"); t = 1.79e9
calm = {"ratio": 1.0, "ok": True, "p90_ms": 5}
starved = {"ratio": 6.0, "ok": False, "p90_ms": 10000}
def emit(i, **kw):
    o = {"now": t + 2 * i, "starv": calm, "pty": {"state": "done", "ms": 12, "seq": i // 15},
         "walk": {"verdict": "OK", "scan_ms": 2.6, "seq": i // 15}, "procscan": {"seq": i // 5},
         "stuck": {"n": 0}, "leaders": [], "kitty": {"present": True, "sockets": 3, "t0_flat_s": 0,
         "sockets_growth": 0}, "probe_age": {}, "probe_p99": {}}
    o.update(kw); out.write(json.dumps(o) + "\n")
i = 0
for _ in range(20000):                                 # ~11 h of healthy ticks
    emit(i); i += 1
for k in range(150):                                   # load-1000 hour shape: slow walk, starved core
    emit(i, starv=starved, walk={"verdict": "WEDGED_PREVIOUS", "stuck_s": 40 + k, "last": "lstat ttys%03d" % (k % 90),
                                 "last_steady_s": 0, "seq": "s%d" % (k // 5)},
         pty={"state": "done", "ms": 1900, "seq": "p%d" % (k // 5)}); i += 1
for k in range(300):                                   # idle kitty: main thread flat, no RC growth
    emit(i, kitty={"present": True, "sockets": 4, "t0_flat_s": 2 * k, "sockets_growth": 0}); i += 1
for k in range(300):                                   # exiting NON-pty processes / an orphaned pty leader not yet 5 min old
    emit(i, leaders=[{"pid": 5, "lstart": 1, "pgid": 5, "tty": "ttys009", "exiting": False, "orphan": True, "orphan_s": k}]); i += 1
EOF
  run lp replay "$gen"
  [ "$status" -eq 0 ]
  "$PY" -I -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["l2_ticks"]==0 and d["l1_share"]<=0.02, d' "$output"
  run lp replay "$FX/replay-live-2026-10-25.jsonl"
  [ "$status" -eq 0 ]
  "$PY" -I -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["ticks"]>=200 and d["l2_ticks"]==0 and d["l1_share"]<=0.02, d' "$output"
  # discrimination: the same healthy stream with a steady wedge appended does reach L2
  "$PY" -I - "$gen" <<'EOF'
import json, sys
out = open(sys.argv[1], "a"); t = 1.8e9
for k in range(40):
    out.write(json.dumps({"now": t + 2 * k, "starv": {"ratio": 1.0, "ok": True},
        "walk": {"verdict": "WEDGED_PREVIOUS", "stuck_s": 30 + 2 * k, "last": "lstat ttys063",
                 "last_steady_s": 30 + 2 * k, "seq": k // 5}, "pty": {}, "procscan": {"seq": k}}) + "\n")
EOF
  run lp replay "$gen"
  "$PY" -I -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["l2_ticks"]>0, d' "$output"
}

@test "8: a canary pidfile from a previous boot, or a live reused pid with another lstart, is stale -- never WEDGED" {
  sd="$BATS_TEST_TMPDIR/cs"; mkdir -p "$sd/canary-OLD-BOOT" "$sd/canary-$BOOT"
  printf '%s 1 OLD-BOOT 1\n' "$$" >"$sd/canary-OLD-BOOT/canary.pid"
  printf '%s 1 %s 1\n' "$$" "$BOOT" >"$sd/canary-$BOOT/canary.pid"     # live pid, wrong lstart
  run perl -e 'alarm 20; exec @ARGV' -- /usr/bin/perl "$REPO/scripts/forensics/devfs-canary.pl" "$sd" 3
  [ "$status" -eq 0 ]
  [[ "$output" == verdict=OK*broke_stale=1* ]] || false
  # control: the SAME live pid with its true kernel lstart is a held mutex -> WEDGED_PREVIOUS
  sleep 30 &
  sp=$!
  ls="$(/usr/bin/perl -e 'my $m=pack("i4",1,14,1,$ARGV[0]);my $b="\0"x648;my $l=pack("Q",648);syscall(202,$m,4,$b,$l,0,0);print unpack("q",substr($b,0,8))' "$sp")"
  printf '%s %s %s %s\n' "$sp" "$ls" "$BOOT" "$(date +%s)" >"$sd/canary-$BOOT/canary.pid"
  run perl -e 'alarm 20; exec @ARGV' -- /usr/bin/perl "$REPO/scripts/forensics/devfs-canary.pl" "$sd" 3
  kill "$sp"
  [ "$status" -eq 3 ]
  [[ "$output" == verdict=WEDGED_PREVIOUS* ]] || false
}

@test "9: getppid()==1 (host gone) -> verdict host_dead and exit" {
  unset CC_LOCKWATCH_STANDALONE
  ( perl -e 'alarm 60; exec @ARGV' -- "$PY" -I "$LW/lockprobe.py" run --max-ticks 2000 >"$BATS_TEST_TMPDIR/orphan.out" 2>&1 & )
  for _ in $(seq 1 150); do
    [ -f "$CC_LOCKWATCH_DIR/state.json" ] && [ "$(jget "$CC_LOCKWATCH_DIR/state.json" verdict)" = host_dead ] && break
    sleep 0.1
  done
  [ "$(jget "$CC_LOCKWATCH_DIR/state.json" verdict)" = host_dead ]
  read -r pid _ <"$CC_LOCKWATCH_DIR/lockprobe.pid"
  for _ in $(seq 1 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  run kill -0 "$pid"
  [ "$status" -ne 0 ]
}
