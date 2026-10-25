#!/usr/bin/env bats
# scripts/forensics/capture.sh + devfs-canary.pl + scripts/lockwatch/diagnose.py (DESIGN C3 tests
# a-f). Every tool capture.sh calls goes through a CC_FX_STUB_DIR recorder; `sample` is faked;
# logs, sudo and the transcript scan are kept off the live machine. Runs under /bin/bash (3.2),
# the interpreter the sentinel and lockprobe use.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  CAP="$REPO/scripts/forensics/capture.sh"
  LW="$REPO/scripts/lockwatch"
  FX="$REPO/tests/fixtures/lockwatch"
  for c in /Library/Frameworks/Python.framework/Versions/3.11/bin/python3.11 \
    /Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9 \
    /Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9 \
    /usr/bin/python3; do
    if [ -x "$c" ]; then PY="$c"; break; fi
  done
  export CC_FX_ROOT="$BATS_TEST_TMPDIR/fx" CC_FX_ACTIVE="$BATS_TEST_TMPDIR/active.pids"
  export CC_LOCKWATCH_DIR="$BATS_TEST_TMPDIR/lw" CC_FX_SKIP_LOG=1 CC_FX_NOSUDO=1
  export CC_FX_TRANSCRIPT_ROOTS="$BATS_TEST_TMPDIR/no-transcripts"
  mkdir -p "$CC_LOCKWATCH_DIR" "$CC_FX_TRANSCRIPT_ROOTS"
  BOOT="$(/usr/sbin/sysctl -n kern.bootsessionuuid)"
  STUB="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB"
  export CALLS="$BATS_TEST_TMPDIR/calls.log"
  # recorders: log argv, then run the real tool (sample is faked: it would take seconds per pid)
  for t in ps:/bin/ps sysctl:/usr/sbin/sysctl vm_stat:/usr/bin/vm_stat find:/usr/bin/find \
    memory_pressure:/usr/bin/memory_pressure cp:/bin/cp log:/usr/bin/log sudo:/usr/bin/sudo; do
    printf '#!/bin/bash\nprintf "%%s\\t%%s\\n" "%s" "$*" >>"$CALLS"\nexec %s "$@"\n' "${t%%:*}" "${t#*:}" >"$STUB/${t%%:*}"
  done
  printf '#!/bin/bash\nprintf "sample\\t%%s\\n" "$*" >>"$CALLS"\nf=""; while [ $# -gt 0 ]; do [ "$1" = -file ] && f="$2"; shift; done\nprintf "Sort by top of stack, same collapsed (when >= 5):\\n        __semwait_signal  (in libsystem_kernel.dylib)  5\\n" >"$f"\n' >"$STUB/sample"
  for t in lsof pgrep zsh login ls tty; do
    printf '#!/bin/bash\nprintf "%s\\t%%s\\n" "$*" >>"$CALLS"\n' "$t" >"$STUB/$t"
  done
  chmod +x "$STUB"/*
  export CC_FX_STUB_DIR="$STUB"
}

teardown() {
  [ -n "${HOLDER:-}" ] && kill "$HOLDER" 2>/dev/null || true
  local f p
  for f in "$CC_FX_ROOT"/.canary/canary-*/canary.pid; do
    [ -f "$f" ] || continue
    read -r p _ <"$f"
    # the stalled canary child (seam): a setsid'd probe child with no ctty, I9 exception
    [ -n "$p" ] && kill -TERM "$p" 2>/dev/null || true
  done
}

cap() { perl -e 'alarm 150; exec @ARGV' -- /bin/bash "$CAP" "$@"; }
lstart_of() { /usr/bin/perl -e 'my $m=pack("i4",1,14,1,$ARGV[0]);my $b="\0"x648;my $l=pack("Q",648);syscall(202,$m,4,$b,$l,0,0);print unpack("q",substr($b,0,8))' "$1"; }
bundle() { printf '%s\n' "$output" | tail -1; }

@test "a: a step past its deadline is ABANDONed and returns within deadline + 1 s; progress ends in EXIT" {
  CC_FX_EXTRA_STEP='99-slow|1|/bin/sleep 30' run cap snapshot slowstep
  [ "$status" -eq 0 ]
  d="$(bundle)"
  row="$(grep '^99-slow' "$d/steps.tsv")"
  [ "$(printf '%s' "$row" | cut -f2)" = 124 ]
  [ "$(printf '%s' "$row" | cut -f5)" = ABANDON ]
  [ "$(printf '%s' "$row" | cut -f3)" -le 2000 ]
  [ "$(tail -1 "$d/progress")" = "EXIT 0" ]
  grep -q '"abandoned": \[' "$d/manifest.json"
  grep -q '99-slow' "$d/manifest.json"
}

@test "b: the PATH-stub recorder sees no banned I4 form (tt/tty/-t/-M/-T, ps without -x/-A, multi-pid -p, lsof, ls /dev, pgrep, zsh, login)" {
  run cap full banned
  [ "$status" -eq 0 ]
  [ -s "$CALLS" ]
  grep -q '^ps' "$CALLS"                      # the recorder discriminates: ps WAS called
  run "$PY" -I - "$CALLS" <<'EOF'
import re, sys
bad = []
for line in open(sys.argv[1]):
    tool, _, args = line.rstrip("\n").partition("\t")
    a = args.split()
    if tool in ("lsof", "pgrep", "zsh", "login", "tty"):
        bad.append(line)
    if tool == "ls" and any(x.startswith("/dev") for x in a):
        bad.append(line)
    if tool == "ps":
        flags = [x for x in a if x.startswith("-")]
        if not any("x" in f or "A" in f for f in flags if not f.startswith("-o")):
            bad.append(line)
        if any(f in ("-t", "-T", "-M") or re.match(r"-[a-zA-Z]*[tTM]$", f) for f in flags):
            bad.append(line)
        cols = ",".join(a[i + 1] for i, x in enumerate(a) if x == "-o" and i + 1 < len(a))
        if re.search(r"(^|,)(tt|tty)=?(,|$)", cols):
            bad.append(line)
        if any(x == "-p" and i + 1 < len(a) and "," in a[i + 1] for i, x in enumerate(a)):
            bad.append(line)
print("".join(bad) or "clean")
EOF
  [ "$output" = clean ]
  # and nothing bypasses the recorder by absolute path
  run grep -n -E '^[^#]*(/usr/sbin/lsof|/usr/bin/pgrep|/bin/zsh|/usr/bin/login|/bin/ls /dev)' "$CAP"
  [ "$status" -eq 1 ]
}

@test "c: a lock from a previous boot, or a live reused pid with another lstart, is broken; a true holder is busy (75)" {
  L="$CC_FX_ROOT/.locks/$BOOT/capture-snapshot.lock"
  mkdir -p "$L"
  printf '%s 1 OLD-BOOT\n' "$$" >"$L/owner"
  run cap snapshot oldboot
  [ "$status" -eq 0 ]
  [[ "$output" == *"broke stale snapshot lock"* ]] || false
  mkdir -p "$L"
  printf '%s 1 %s\n' "$$" "$BOOT" >"$L/owner"          # live pid, wrong lstart = reused
  CC_FX_FORCE=1 run cap snapshot reused
  [ "$status" -eq 0 ]
  [[ "$output" == *"broke stale snapshot lock"* ]] || false
  sleep 60 &
  HOLDER=$!
  mkdir -p "$L"
  printf '%s %s %s\n' "$HOLDER" "$(lstart_of "$HOLDER")" "$BOOT" >"$L/owner"
  CC_FX_FORCE=1 run cap snapshot held
  [ "$status" -eq 75 ]
  [[ "$output" == *busy* ]] || false
}

@test "d: an L1 snapshot holding its lock does not block the L2 full capture, which yields a full bundle" {
  run cap snapshot first
  [ "$status" -eq 0 ]
  sleep 60 &
  HOLDER=$!
  L="$CC_FX_ROOT/.locks/$BOOT/capture-snapshot.lock"
  mkdir -p "$L"
  printf '%s %s %s\n' "$HOLDER" "$(lstart_of "$HOLDER")" "$BOOT" >"$L/owner"
  run cap snapshot again                               # rate-limited / busy
  [ "$status" -eq 75 ]
  CC_FX_FORCE=1 CC_FX_EXTRA_STEP="98-active|5|/bin/cat $CC_FX_ACTIVE" run cap full L2-test
  [ "$status" -eq 0 ]
  d="$(bundle)"
  [ -f "$d/diagnosis.json" ]
  [ -f "$d/DIAGNOSIS.md" ]
  [ -f "$d/steps.tsv" ]
  grep -q '"tier": "full"' "$d/manifest.json"
  grep -q '"full_ok": true' "$d/manifest.json"
  grep -q '"H2"' "$d/manifest.json"                    # no root wrapper here: recorded, not faked
  # every step child registers `pid lstart boot` BEFORE it execs (the compressor actuator's
  # never-list): the cat step reads its own line back
  run grep -E "^[0-9]+ [1-9][0-9]+ $BOOT\$" "$d/98-active.out"
  [ "$status" -eq 0 ]
}

@test "e: the stall seam -> WEDGED, then WEDGED_PREVIOUS last=\"lstat <name>\" from the SAME child; no second child" {
  dev="$BATS_TEST_TMPDIR/fakedev"; mkdir -p "$dev"; touch "$dev/a" "$dev/ttys063" "$dev/z"
  export CC_FX_DEV_DIR="$dev" CC_FX_CANARY_STALL_AT=ttys063 CC_FX_CANARY_STALL_S=300
  run cap snapshot stall1
  [ "$status" -eq 0 ]
  c1="$(cat "$(bundle)/03-devfs-canary.out")"
  [[ "$c1" == 'verdict=WEDGED pid='*'last="lstat ttys063"' ]] || false
  p1="$(printf '%s' "$c1" | sed -E 's/.* pid=([0-9]+) .*/\1/')"
  CC_FX_FORCE=1 run cap snapshot stall2
  [ "$status" -eq 0 ]
  d2="$(bundle)"
  c2="$(cat "$d2/03-devfs-canary.out")"
  [[ "$c2" == 'verdict=WEDGED_PREVIOUS pid='"$p1"' '*'last="lstat ttys063"' ]] || false
  kill -0 "$p1"
  # the bundle's own diagnosis reads the wedged walk (no leader join in a live table)
  grep -q '"verdict": "devfs_lookup_stall"' "$d2/diagnosis.json"
}

@test "f: diagnose names ttys063 / holder 96296 / leader 68298 over the NODEV fixture, adds the cause from a transcript, and reads none when healthy" {
  b="$BATS_TEST_TMPDIR/b1"; mkdir -p "$b"
  cp "$FX/incident/procscan.json" "$b/02-procscan.json"
  cp "$FX/incident/walk-wedged.out" "$b/03-devfs-canary.out"
  cp "$FX/incident/ttymap.json" "$b/05-lockwatch-ttymap.json"
  for p in 96296 95771 96310; do cp "$FX/incident/sample-$p.txt" "$b/08-sample-$p.txt"; done
  run "$PY" -I "$LW/diagnose.py" bundle --bundle "$b" --no-cause
  [ "$status" -eq 0 ]
  dj="$b/diagnosis.json"
  run "$PY" -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["verdict"], d["tty"], d["holder"], d["leader"], d["pgid"], d["confidence"], " ".join(map(str, d["targets"])))' "$dj"
  [ "$output" = "devfs_poison ttys063 96296 68298 68298 high 96296 95771 96310" ]
  run grep -q '"cause"' "$dj"
  [ "$status" -eq 1 ]
  # with the transcript fixture the cause is attributed
  tr="$BATS_TEST_TMPDIR/tr"; cp -R "$FX/incident/transcripts" "$tr"; touch "$tr"/*/*.jsonl
  CC_FX_TRANSCRIPT_ROOTS="$tr" run "$PY" -I "$LW/diagnose.py" bundle --bundle "$b"
  [ "$status" -eq 0 ]
  grep -q 'kill -KILL 94459 68298' "$dj"
  grep -q 'cc5a6d48-0000-4000-8000-fixture00001' "$dj"
  run grep -q 'kill -0 12345' "$dj"                    # a kill naming another pid is not a cause
  [ "$status" -eq 1 ]
  grep -q 'rescue.sh unpoison 68298' "$b/DIAGNOSIS.md"
  # control: no __open sample -> the same join at medium confidence, holder unknown
  rm "$b/08-sample-96296.txt"
  run "$PY" -I "$LW/diagnose.py" bundle --bundle "$b" --no-cause
  grep -q '"confidence": "medium"' "$dj"
  # healthy fixture -> none
  h="$BATS_TEST_TMPDIR/b2"; mkdir -p "$h"
  cp "$FX/incident/healthy-procscan.json" "$h/02-procscan.json"
  cp "$FX/incident/walk-ok.out" "$h/03-devfs-canary.out"
  run "$PY" -I "$LW/diagnose.py" bundle --bundle "$h" --no-cause
  [ "$status" -eq 0 ]
  grep -q '"verdict": "none"' "$h/diagnosis.json"
}
