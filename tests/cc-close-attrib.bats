#!/usr/bin/env bats
# cc-close-attrib — the session close-attribution exec-wrapper + its join in the crash
# watchdog. The wrapper runs the real binary unchanged, tees stderr to a per-run capture,
# and writes ~/.claude/logs/close-records/<pid>-<epoch>.json carrying the REAL exit_code/
# signal; the watchdog then turns that record into an attributed cause (clean-exit vs
# killed-oom-or-force vs binary-crash vs error-exit) instead of "abrupt-unknown".
#
# Coverage: (i) exit-code + argv passthrough · (ii) exit_code/signal record fields (0, 1, the
# 139 crash code, and a real signal death) · (iii) stderr reaches the caller's fd2 AND the tail
# is captured · (iv) secret-bearing lines stripped from the tail · (v) unwritable records dir
# fails open (session runs, exit code preserved, no crash) · (vi) watchdog joins a fixture
# close-record → enrichment fields + clean-exit/binary-crash classification, outranks jetsam,
# no-record falls through to existing behavior · (vii) the DURABLE per-pid stderr log (eval-track
# crash forensics): full untruncated text, watchdog-joinable name, survives a hard kill that
# writes no close-record at all, no litter on a clean exit, honours the kill switch, bounded ·
# (ix) the suite-wide lock that keeps (ii)'s fixtures out of the operator's crash-report store.
#
# (vii) exists because the eval track (claude-next/-2/-3/-4, claude-fable*, claude-desk*, all
# handoff-fire spawns) execs the 2.1.219 binary through THIS wrapper and never through
# bin/claude-latest — so before the durable log, lead-crash-watchdog.sh:821's join
# (`ls $HOME/.claude/logs/stderr/*-<pid>.log`) matched nothing for any eval-track pid:
# 0 of 52 rows in the live claude-crashes.jsonl ever carried a stderr_log, and the three
# 2026-07-29 eval-track deaths landed as cause="abrupt-unknown" with no close-record either
# (the wrapper died with its child, so write_record never ran).

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. handoff-fire.sh's
  # capacity_gate reads the box's live loadavg AND (M10) its memory headroom, exiting 9 when either is
  # past its bar, so an unpinned suite goes RED purely because the box is busy — the corpus deciding a
  # verdict on machine state instead of on the tree. Both terms are pinned off here (they are the two
  # TERMS of one exit 9, handoff-fire.sh:4487); tests/handoff-fire-capacity-gate.bats is the ONE place
  # the gate runs ON, against synthetic inputs.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WRAP="$REPO/bin/cc-close-attrib"
  HOOK="$REPO/hooks/lead-crash-watchdog.sh"
  export CC_CLOSE_RECORDS_DIR="$BATS_TEST_TMPDIR/close-records"
  # sandbox the watchdog's account roots so --classify never touches live transcripts
  export CC_ACCOUNT_BASES="$BATS_TEST_TMPDIR/acct"
  mkdir -p "$CC_ACCOUNT_BASES/projects/proj"
  # (vii) uses the DEFAULT stderr-log path so the test exercises the same $HOME-derived
  # directory lead-crash-watchdog.sh:821 globs — hence a sandboxed HOME, never the live one.
  export HOME="$BATS_TEST_TMPDIR/home"
  SD="$HOME/.claude/logs/stderr"
  mkdir -p "$HOME"
}

# poll (bounded — never hangs a suite) until $1 matches a non-empty file; echo it or nothing
await_log() { # $1=glob-dir
  local i=0 f=""
  while [ "$i" -lt 100 ]; do
    # shellcheck disable=SC2012  # our own fixed pattern in a sandboxed dir
    f=$(ls -1 "$1"/*.log 2>/dev/null | head -1 || true)
    [ -n "$f" ] && [ -s "$f" ] && { printf '%s' "$f"; return 0; }
    sleep 0.1; i=$((i + 1))
  done
  return 1
}

# executable stub that early-exits on `--version` (so the wrapper's cached version probe
# never triggers the stub's real body), then runs the given body lines.
mk_stub() { # $1=path  $2...=body lines
  local p="$1"; shift
  { printf '#!/bin/bash\n[[ "$1" == "--version" ]] && { echo "stub 9.9.9"; exit 0; }\n'
    printf '%s\n' "$@"
  } > "$p"
  chmod +x "$p"
}

# newest close-record in the sandbox
rec() { ls -1t "$CC_CLOSE_RECORDS_DIR"/*.json 2>/dev/null | head -1; }

# ── (i) passthrough ───────────────────────────────────────────────────────────────────────
@test "wrapper passes the exit code and argv through to the stub" {
  local stub="$BATS_TEST_TMPDIR/stub"
  mk_stub "$stub" 'printf "%s\n" "$@" > "'"$BATS_TEST_TMPDIR"'/seen"' 'exit 33'
  run bash "$WRAP" "$stub" alpha beta
  [ "$status" -eq 33 ]                                  # exit code preserved
  grep -qx alpha "$BATS_TEST_TMPDIR/seen"              # stub actually received the args
  grep -qx beta  "$BATS_TEST_TMPDIR/seen"
  grep -q ',"alpha","beta"\]' "$(rec)"                 # argv[first 3] recorded
}

# ── (ii) exit_code / signal record fields ───────────────────────────────────────────────────
# The 139 case is a plain `exit 139`, NOT the `kill -SEGV $$` it used to be. write_record derives
# the entire signal field arithmetically — `rsig=$(( rcode - 128 ))`, bin/cc-close-attrib:118 —
# from the status `wait` hands back, and bash returns 139 identically for a SEGV death and for
# `exit 139`, so the record under assertion is byte-identical either way. What the real signal
# added was a real macOS crash report: /bin/bash dying on SIGSEGV makes ReportCrash write an .ips
# into ~/Library/Logs/DiagnosticReports on EVERY run (measured 2026-08-09: one run of this file =
# exactly +1, 31→32), and com.claude.postland-verify runs this suite on every land. So the fixture
# was a daily litter generator inside the one directory the fleet's crash forensics reads, and it
# had already corrupted a census: docs/research/panic-compressor-2026-08-05.md §8 found 35 of 104
# .ips were this single line's output — "it litters real crash reports daily and polluted this
# census". An instrument must not write into the evidence store another instrument reads.
#
# The real-signal path is NOT surrendered in the trade — the sT case below dies of a genuine
# SIGTERM, so `wait` must still yield a true 128+n rather than an exit status that merely looks
# like one. macOS only crash-reports the EXC_CRASH signals; measured on 15.6.1, SEGV(11) and
# QUIT(3) each write an .ips while TERM(15) writes none over 3 runs, so SIGTERM buys that
# coverage at zero cost to the operator's crash store. (ix) locks the choice suite-wide.
@test "record carries exit_code/signal for clean, error, crash-code, and signal-killed exits" {
  local s0="$BATS_TEST_TMPDIR/s0" s1="$BATS_TEST_TMPDIR/s1" s9="$BATS_TEST_TMPDIR/s9"
  local sT="$BATS_TEST_TMPDIR/sT"
  mk_stub "$s0" 'exit 0'
  mk_stub "$s1" 'exit 1'
  mk_stub "$s9" 'exit 139'
  mk_stub "$sT" 'kill -TERM $$'

  run bash "$WRAP" "$s0"
  [ "$status" -eq 0 ]
  grep -q '"exit_code":0,' "$(rec)"
  grep -q '"signal":"",'   "$(rec)"

  run bash "$WRAP" "$s1"
  [ "$status" -eq 1 ]
  grep -q '"exit_code":1,' "$(rec)"

  run bash "$WRAP" "$s9"
  [ "$status" -eq 139 ]
  grep -q '"exit_code":139,' "$(rec)"
  grep -q '"signal":"11",'   "$(rec)"                  # 139 = 128 + SIGSEGV(11) — binary-crash

  # a REAL signal death, so 128+n is derived from an actual kill and not from an exit status
  run bash "$WRAP" "$sT"
  [ "$status" -eq 143 ]
  grep -q '"exit_code":143,' "$(rec)"
  grep -q '"signal":"15",'   "$(rec)"                  # 143 = 128 + SIGTERM(15)
}

# ── (ii-b) WHICH PROCESS THE SIGNAL WAS AIMED AT ────────────────────────────────────────────
# The two arms below are the whole point of sig_reached_wrapper: BOTH die 143 / signal "15", so
# every field that existed before this test agrees across them byte-for-byte, and only the new
# one separates a kill aimed at the claude CHILD from one that reached the WRAPPER. The second
# arm is the positive control, chosen to answer differently from the first — a pair whose cells
# agreed would be measuring the harness rather than the field.
#
# This is the distinction docs/research/sigterm-forensics-2026-08-25.md had to reconstruct by
# hand from the ABSENCE of co-victims (§ line 84) and which its § line 71 calls the fact that
# "redirects the entire search". It is NOT si_pid: that doc's top recommendation asks for si_pid
# in _forward(), which bash cannot reach at all — see the long note at bin/cc-close-attrib's
# _forward() block for why, and for why the only implementable form of that request would have
# been blind to the very kill it was written for.
@test "record separates a signal aimed at the child from one that reached the wrapper" {
  local sChild="$BATS_TEST_TMPDIR/sChild" sWrap="$BATS_TEST_TMPDIR/sWrap"
  # child-alone TERM — the wrapper's trap never runs.
  mk_stub "$sChild" 'kill -TERM $$'
  # a TERM that reaches the WRAPPER, which forwards it, so the child still dies of TERM. The
  # sleep is what makes the forward FALSIFIABLE: without a forward this stub exits 0, not 143.
  mk_stub "$sWrap" 'kill -TERM $PPID' 'sleep 5' 'exit 0'

  run bash "$WRAP" "$sChild"
  [ "$status" -eq 143 ]
  grep -q '"exit_code":143,'          "$(rec)"
  grep -q '"signal":"15",'            "$(rec)"
  grep -q '"sig_reached_wrapper":""'  "$(rec)"        # aimed at the child alone

  run bash "$WRAP" "$sWrap"
  [ "$status" -eq 143 ]                               # ...so the forward genuinely happened
  grep -q '"exit_code":143,'              "$(rec)"    # every pre-existing field AGREES with arm 1
  grep -q '"signal":"15",'                "$(rec)"
  grep -q '"sig_reached_wrapper":"TERM"'  "$(rec)"    # ...and only the new field discriminates
  true
}

@test "a REAL record carrying the new field stays valid JSON and shadows nothing" {
  # Deliberately NOT a hand-written fixture. A fixture would assert a property of a string this
  # test itself wrote, so no mutation of the WRITER could ever red it — it would be green by
  # construction. This drives the real wrapper and reads its real record, so the printf that
  # builds the JSON is the subject.
  local stub="$BATS_TEST_TMPDIR/sJson"
  mk_stub "$stub" 'echo "boom" >&2' 'kill -TERM $PPID' 'sleep 5' 'exit 0'
  run bash "$WRAP" "$stub"
  [ "$status" -eq 143 ]
  local r; r="$(rec)"
  [ -n "$r" ]

  # (a) VALIDITY. The record is built by printf, never jq (bin/cc-close-attrib's "NO HARD
  # DEPENDENCIES" rule), so a malformed separator in that format string is the standing hazard
  # of editing it — and it would not show up in any single-field grep.
  run python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$r"
  [ "$status" -eq 0 ]

  # (b) NO SHADOW. close_record_field greps an UNANCHORED "<key>": and takes head -1, so this is
  # the assertion that the field NAME was chosen safely — not merely that the writer emits it.
  local pid; pid="$(basename "$r" | cut -d- -f1)"
  run bash "$HOOK" --close-fields "$pid"
  [ "$(printf '%s' "$output" | cut -f1)" = "143" ]   # exit_code, not shadowed
  [ "$(printf '%s' "$output" | cut -f2)" = "15" ]    # signal reads 15, NOT "TERM"
  true
}

# ── (iii) stderr passthrough AND capture ────────────────────────────────────────────────────
@test "stderr still reaches the caller's fd2 while the tail is captured" {
  local stub="$BATS_TEST_TMPDIR/stub"
  mk_stub "$stub" 'echo "to-stdout"' 'echo "to-stderr-line" >&2' 'exit 0'
  bash "$WRAP" "$stub" >"$BATS_TEST_TMPDIR/o" 2>"$BATS_TEST_TMPDIR/e"
  grep -qx "to-stdout"      "$BATS_TEST_TMPDIR/o"      # stdout untouched
  grep -qx "to-stderr-line" "$BATS_TEST_TMPDIR/e"      # stderr reached the caller (fd2)
  grep -q  "to-stderr-line" "$(rec)"                    # AND landed in the record tail
}

# ── (iv) secret stripping ───────────────────────────────────────────────────────────────────
@test "secret-bearing stderr lines are stripped from the record tail" {
  local stub="$BATS_TEST_TMPDIR/stub"
  mk_stub "$stub" \
    'echo "normal diagnostic line" >&2' \
    'echo "authorization: Bearer abc123" >&2' \
    'echo "api_key=SUPERSECRET" >&2' \
    'echo "x-auth-token: zzz" >&2' \
    'echo "another normal line" >&2' \
    'exit 0'
  bash "$WRAP" "$stub" >/dev/null 2>/dev/null
  local r; r="$(rec)"
  grep -q "normal diagnostic line" "$r"
  grep -q "another normal line"    "$r"
  ! grep -qi "bearer"        "$r" || false
  ! grep -qi "SUPERSECRET"   "$r" || false
  ! grep -qi "authorization" "$r" || false
  ! grep -qi "token"         "$r"
}

# ── (v) fail-open on an unwritable records dir ──────────────────────────────────────────────
@test "unwritable records dir fails open: session runs, exit code preserved, no crash" {
  local ro="$BATS_TEST_TMPDIR/ro"; mkdir -p "$ro"; chmod 000 "$ro"
  export CC_CLOSE_RECORDS_DIR="$ro/nope/records"
  local stub="$BATS_TEST_TMPDIR/stub"
  mk_stub "$stub" 'echo "ran anyway"' 'exit 5'
  run bash "$WRAP" "$stub"
  chmod 755 "$ro"                                       # restore so bats teardown can clean up
  [ "$status" -eq 5 ]                                   # exit code still preserved
  printf '%s' "$output" | grep -q "ran anyway"          # session still ran
}

# ── (vi) watchdog close-record join ─────────────────────────────────────────────────────────
@test "watchdog joins a fixture close-record → clean-exit / binary-crash classification" {
  mkdir -p "$CC_CLOSE_RECORDS_DIR"
  printf '{"pid":8001,"exit_code":0,"signal":"","stderr_tail":"bye","version":"2.1.9"}\n'   > "$CC_CLOSE_RECORDS_DIR/8001-100.json"
  printf '{"pid":8002,"exit_code":139,"signal":"11","stderr_tail":"x","version":"2.1.9"}\n' > "$CC_CLOSE_RECORDS_DIR/8002-100.json"

  run bash "$HOOK" --classify sess 8001
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | cut -f1)" = "RECYCLE" ]
  [ "$(printf '%s' "$output" | cut -f2)" = "clean-exit" ]

  run bash "$HOOK" --classify sess 8002
  [ "$(printf '%s' "$output" | cut -f1)" = "CRASH" ]
  [ "$(printf '%s' "$output" | cut -f2)" = "binary-crash" ]
}

@test "watchdog --close-fields exposes exit_code/signal/path/version for the crash row" {
  mkdir -p "$CC_CLOSE_RECORDS_DIR"
  printf '{"pid":8003,"exit_code":137,"signal":"9","stderr_tail":"oom","version":"2.1.42"}\n' > "$CC_CLOSE_RECORDS_DIR/8003-100.json"
  run bash "$HOOK" --close-fields 8003
  [ "$(printf '%s' "$output" | cut -f1)" = "137" ]
  [ "$(printf '%s' "$output" | cut -f2)" = "9" ]
  printf '%s' "$output" | grep -q "8003-100.json"       # stderr_tail_path
  [ "$(printf '%s' "$output" | cut -f4)" = "2.1.42" ]
}

@test "close-record OUTRANKS the jetsam heuristic (per-pid ground truth wins)" {
  mkdir -p "$CC_CLOSE_RECORDS_DIR"
  export CC_JETSAM_DIRS="$BATS_TEST_TMPDIR/jetsam"; mkdir -p "$CC_JETSAM_DIRS"
  : > "$CC_JETSAM_DIRS/JetsamEvent-2099-01-01-000000.ips"   # a fresh jetsam event...
  printf '{"pid":8010,"exit_code":0,"signal":"","stderr_tail":"clean","version":"1.0.0"}\n' > "$CC_CLOSE_RECORDS_DIR/8010-1.json"
  run bash "$HOOK" --classify sess 8010                      # ...but this pid exited clean
  [ "$(printf '%s' "$output" | cut -f2)" = "clean-exit" ]
}

@test "no close-record for the pid ⇒ existing behavior (no forced override)" {
  run bash "$HOOK" --classify sess 9999
  [ "$(printf '%s' "$output" | cut -f1)" = "CRASH" ]
  [ "$(printf '%s' "$output" | cut -f2)" = "no-transcript" ]
}

# ── (vii) the durable per-pid stderr log ────────────────────────────────────────────────────
@test "durable stderr log is named <ts>-<pid>.log and joins on the watchdog's own glob" {
  local stub="$BATS_TEST_TMPDIR/stub"
  mk_stub "$stub" 'echo "DIAG-LINE" >&2' 'exit 0'
  run bash "$WRAP" "$stub"
  [ "$status" -eq 0 ]

  # the pid the record was keyed on IS the pid in the log's name — that identity is what
  # makes the log joinable, so assert it rather than just "some log exists".
  local pid; pid=$(sed -nE 's/.*"pid":([0-9]+).*/\1/p' "$(rec)")
  [ -n "$pid" ]
  # REPLAY of lead-crash-watchdog.sh:821, verbatim — same expression, same $HOME-derived dir.
  # shellcheck disable=SC2012  # deliberate: this IS the consumer's expression
  local sterr; sterr=$(ls -1t "$HOME/.claude/logs/stderr/"*"-${pid}.log" 2>/dev/null | head -1 || true)
  [ -n "$sterr" ]
  grep -q "DIAG-LINE" "$sterr"
  # 0600 (mktemp inode) — the durable log is UNFILTERED stderr, unlike the record's tail
  [ "$(stat -f '%Lp' "$sterr")" = "600" ]
}

@test "durable log keeps the FULL stderr where the record tail is truncated to 40 lines" {
  local stub="$BATS_TEST_TMPDIR/stub"
  mk_stub "$stub" 'for i in $(seq 1 60); do echo "OOMLINE-$i" >&2; done' 'exit 1'
  run bash "$WRAP" "$stub"
  [ "$status" -eq 1 ]
  local r; r="$(rec)"
  grep -q "OOMLINE-60" "$r"                       # tail-40 keeps the newest
  ! grep -q "OOMLINE-1\\\\n" "$r" || false        # ...but not the oldest (line 1 fell off)

  local sterr; sterr=$(await_log "$SD")
  [ "$(grep -c '^OOMLINE-' "$sterr")" -eq 60 ]    # the durable log kept every line
  grep -qx "OOMLINE-1" "$sterr"
}

@test "durable log survives a hard kill in which NO close-record is written" {
  # THE load-bearing case: a group SIGKILL (OOM killer / force-quit) takes the wrapper with
  # its child, so write_record never runs — this was the 2026-07-29 abrupt-unknown signature.
  local stub="$BATS_TEST_TMPDIR/stub"
  mk_stub "$stub" 'echo "FATAL-HEAP-OOM-EVIDENCE" >&2' 'sleep 5'
  bash "$WRAP" "$stub" >/dev/null 2>/dev/null &
  local wpid=$!

  local sterr; sterr=$(await_log "$SD")
  [ -n "$sterr" ]
  kill -9 "$wpid" 2>/dev/null || true             # wrapper FIRST — it must not get to record
  pkill -9 -P "$wpid" 2>/dev/null || true         # then its child + tee (precise: -P, not -f)
  wait "$wpid" 2>/dev/null || true

  grep -q "FATAL-HEAP-OOM-EVIDENCE" "$sterr"      # the evidence outlived the whole group
  # shellcheck disable=SC2012
  [ -z "$(ls -1 "$CC_CLOSE_RECORDS_DIR"/*.json 2>/dev/null || true)" ]   # and there IS no record
}

@test "a clean run that wrote no stderr leaves no log behind" {
  local stub="$BATS_TEST_TMPDIR/stub"
  mk_stub "$stub" 'echo "quiet"' 'exit 0'
  run bash "$WRAP" "$stub"
  [ "$status" -eq 0 ]
  # shellcheck disable=SC2012
  [ -z "$(ls -1 "$SD"/*.log 2>/dev/null || true)" ]
  # and no capture temp leaked into the records dir either
  # shellcheck disable=SC2012
  [ -z "$(ls -1 "$CC_CLOSE_RECORDS_DIR"/.stderr.* 2>/dev/null || true)" ]
}

@test "kill switch: CC_CLOSE_ATTRIB_DISABLED=1 writes no durable log" {
  local stub="$BATS_TEST_TMPDIR/stub"
  mk_stub "$stub" 'echo "SHOULD-NOT-CAPTURE" >&2' 'exit 0'
  export CC_CLOSE_ATTRIB_DISABLED=1
  run bash "$WRAP" "$stub"
  [ "$status" -eq 0 ]
  [ ! -d "$SD" ] || [ -z "$(ls -1 "$SD"/*.log 2>/dev/null || true)" ]
}

@test "durable logs are bounded — the newest 200 survive, older ones are rotated out" {
  mkdir -p "$SD"
  # 205 pre-existing non-empty logs, oldest first by mtime
  local i
  for i in $(seq 1 205); do
    printf 'old\n' > "$SD/20200101T0000$(printf '%02d' "$((i % 60))")-90$i.log"
    touch -t "2020010100$(printf '%02d' "$((i % 60))")" "$SD/20200101T0000$(printf '%02d' "$((i % 60))")-90$i.log"
  done
  local stub="$BATS_TEST_TMPDIR/stub"
  mk_stub "$stub" 'echo "new-diag" >&2' 'exit 0'
  run bash "$WRAP" "$stub"
  [ "$status" -eq 0 ]
  # shellcheck disable=SC2012
  [ "$(ls -1 "$SD"/*.log 2>/dev/null | wc -l | tr -d ' ')" -le 200 ]
  # the run's OWN log is one of the survivors (it is the newest)
  grep -rqs "new-diag" "$SD"
}

# ── (viii) the exit code survives a child REAPED before the wrapper reaches its wait ─────────
# The wrapper's whole contract is the exit code, and it used to test `kill -0 "$child"` as the
# GUARD of its wait loop. A reaped pid is gone from the process table, so that read is FALSE for
# a child that already exited: the body never ran, `code` kept its initial 0, and a session that
# died fast was recorded exit 0 / clean-exit. It presented as a minority-of-runs flake in THIS
# file (5 rows in postland's flakes.jsonl; a 2-of-3 retry ladder eventually called it a
# reproducible trunk RED, whose bisect then convicted an unrelated commit and fired an
# auto-revert at it — backlog d86f584455a7).
@test "exit code survives a child reaped before the wrapper reaches its wait" {
  local stub="$BATS_TEST_TMPDIR/stub" shim="$BATS_TEST_TMPDIR/shim"
  mk_stub "$stub" 'exit 1'
  # Widen the race to certainty. `ln` (the durable-log hard link) is the wrapper's last step
  # between forking the child and waiting on it, so delaying it guarantees the child is dead AND
  # reaped by the time the wait is reached — the exact state in which `kill -0` reads FALSE.
  # Without this the defect is a minority-of-runs race and a single-run assertion passes
  # vacuously most of the time (measured pre-fix: 8/60 bare, 5/5 with the delay).
  mkdir -p "$shim"
  { printf '#!/bin/bash\n'
    printf 'touch %s\n' "$BATS_TEST_TMPDIR/ln-fired"
    printf 'sleep 0.4\n'
    printf 'exec /bin/ln "$@"\n'
  } > "$shim/ln"
  chmod +x "$shim/ln"
  export PATH="$shim:$PATH"

  run bash "$WRAP" "$stub"
  # THE CONTROL MUST BE ABLE TO FAIL. If the wrapper ever stops calling `ln` on this path the
  # delay never fires, the race closes, and the assertion below would pass for a reason that has
  # nothing to do with the bug — so prove the injection actually happened before trusting it.
  [ -f "$BATS_TEST_TMPDIR/ln-fired" ]
  [ "$status" -eq 1 ]
  grep -q '"exit_code":1,' "$(rec)"          # ...and the record carries the TRUE code, not 0
}

# ── (x) fd 9 COULD NOT BE OPENED ⇒ the session still runs, with its TRUE exit code ───────────
# THE FLAKE THIS PINS. `exec 9> "$TEE_FIFO"` is a BLOCKING open(2), and bash's SIGCHLD handler is
# not SA_RESTART: any background child dying while the wrapper sits in that open aborts the
# redirection with EINTR, and bash does not retry it. The wrapper has two such children by
# construction — the disowned `--version` probe and the tee itself — so the window is real, not
# theoretical. Measured on this box (QoS-starved via `taskpolicy -c background` + 4 CPU hogs,
# tight loop): 3 of ~100 runs printed
#     cc-close-attrib: line 205: …/.stderr.XXXXXX.fifo.XXXXXX: Interrupted system call
#     cc-close-attrib: line 213: 9: Bad file descriptor
# and exited 1. Off-box it is the whole of backlog 6a7eb069e703: 3 of 12 hermetic CI runs, always
# case (i), always line 79 — because with fd 9 absent `2>&9` kills the child's subshell before it
# can exec anything, so $status is 1, `seen` is never written and no record carries the argv.
#
# WHY THIS IS THE MECHANISM AND NOT THE TIMING. EINTR is only one way for that open to fail, and a
# test that raced it would be as flaky as the bug. What actually broke the wrapper is the SECOND
# half: an fd-9 open failure was FATAL rather than degrading, in a file whose stated hard rule is
# that "the worst case is a plain exec with no record". So the control injects a DETERMINISTIC
# open failure of the same class (a `mkfifo` shim that makes a DIRECTORY, so the open fails EISDIR
# with fd 9 unopened) and asserts the contract that must hold for every member of the class: the
# real binary still runs, and its exit code still reaches the caller. Capture may be lost; the
# session may not. Pre-fix rc measured on this box: 1, with no `seen` file, on 5/5 runs.
@test "(x) a FIFO whose fd-9 open fails still runs the session and preserves its exit code" {
  local stub="$BATS_TEST_TMPDIR/stub" shim="$BATS_TEST_TMPDIR/shim"
  mk_stub "$stub" 'printf "%s\n" "$@" > "'"$BATS_TEST_TMPDIR"'/seen"' 'exit 33'
  mkdir -p "$shim"
  # Reports success, so the wrapper takes the capture branch, but leaves a target that cannot be
  # opened for writing. `-m 600` is swallowed: only the final argument is the path the wrapper uses.
  { printf '#!/bin/bash\n'
    printf 'touch %s\n' "$BATS_TEST_TMPDIR/mkfifo-fired"
    printf 'for a; do :; done\n'
    printf 'mkdir -p "$a"\n'
  } > "$shim/mkfifo"
  chmod +x "$shim/mkfifo"
  export PATH="$shim:$PATH"

  run bash "$WRAP" "$stub" alpha beta
  # THE CONTROL MUST BE ABLE TO FAIL: if the wrapper ever stops calling mkfifo on this path the
  # injection never happens and the assertions below would pass for an unrelated reason.
  [ -f "$BATS_TEST_TMPDIR/mkfifo-fired" ]
  [ "$status" -eq 33 ]                                  # the session ran and its code survived
  grep -qx alpha "$BATS_TEST_TMPDIR/seen"               # ...and the binary was actually EXECUTED
  grep -q '"exit_code":33,' "$(rec)"                    # ...and the record carries the true code
}

# ── (viii) the fd2-holder leak (2026-08-07 load-781 incident). The >(tee) procsub's stdin is the
# session's fd2, and every process the session ever backgrounded inherits that fd — so a binary
# that dies leaving even ONE orphan keeps tee EOF-less, and bash waits for the procsub at exit:
# the wrapper lingered beside its dead session (measured: 43 of 59 wrappers, S+ up to 10h, each
# pinning a tee and its pipeline's zombies). The fix reaps the wrapper's OWN tee after the record
# is written. This test IS the incident in miniature: the stub leaves a 25s orphan holding fd2;
# pre-fix the wrapper exits only when that orphan dies (~25s), post-fix promptly.

@test "(viii) an orphan holding the session's fd2 cannot pin the wrapper past its record" {
  # >/dev/null is load-bearing: the orphan must hold ONLY fd2 (the procsub pipe). Left on fd1 it
  # would hold the wrapper's REAL stdout — the bats capture pipe — and this test would measure
  # the orphan's lifetime on either side of the fix, discriminating nothing.
  mk_stub "$BATS_TEST_TMPDIR/bin-claude" \
    '( sleep 25 >/dev/null & )' \
    'exit 7'
  t0=$(date +%s)
  run bash "$WRAP" "$BATS_TEST_TMPDIR/bin-claude"
  t1=$(date +%s)
  [ "$status" -eq 7 ]                        # the child's code survives the reap path
  [ $((t1 - t0)) -lt 15 ]                    # pre-fix this is ~25s (the orphan's lifetime)
  grep -q '"exit_code":7,' "$(rec)"          # and the record was written BEFORE the tee reap
}

# ── (ix) the lock on (ii)'s trade — suite-wide, because the defect's home is "any .bats". macOS
# writes a real .ips into the operator's ~/Library/Logs/DiagnosticReports for the EXC_CRASH
# signals (measured on 15.6.1: SEGV and QUIT each do; TERM, INT and KILL do not), and
# com.claude.postland-verify runs this corpus on every land — so ONE fixture that self-kills with
# a crash-reporting signal is a daily-litter generator inside the directory crash triage reads.
# Reintroduction is silent by construction: the fixture goes green and the whole cost lands in a
# DIFFERENT tool's evidence, which is why it took a panic census to notice the first one at all.
# Nothing else in the suite fires one today (verified across all 374 .bats files), so this scan
# is a lock, not a migration. It stays scoped to tests/ deliberately: production code sending a
# crash signal to a hung process is a legitimate way to MAKE a report, and only a fixture
# manufactures crash evidence as a side effect of proving something unrelated.
@test "(ix) no test fixture kills itself with a crash-reporting signal" {
  local re='kill[[:space:]]+((-s[[:space:]]+)?-?(QUIT|ILL|TRAP|ABRT|EMT|FPE|BUS|SEGV|SYS)|-(3|4|5|6|7|8|10|11|12))'
  # Full-line comments are documentation, not fixtures — (ii)'s note names the retired
  # `kill -SEGV $$` verbatim, and the file that retired it must not be convicted by its own
  # explanation. The path:lineno: anchor keeps the filter from eating a real match that merely
  # carries a trailing comment.
  run bash -c "grep -rnE '$re' '$REPO/tests' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'"
  # 1 = the inner grep selected nothing, which is the only passing state. 0 = a live fixture; 2 =
  # grep could not read the tree, and a scan that did not RUN must never read as a clean scan.
  [ "$status" -eq 1 ] || { echo "crash-reporting-signal fixture(s): ${output:-<grep error $status>}"; false; }
}
