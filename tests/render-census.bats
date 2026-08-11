#!/usr/bin/env bats
# render-census.bats — row 13 M8 (MACHINE_CAPACITY_V2.md §11.3). The render-budget alarm.
#
# The properties that matter, in priority order:
#   1. A broken instrument reports NO-DATA, never a false OK — and specifically, top failing must
#      NOT be reported as the healthiest possible number (0.00 cores).
#   2. Every rung is reachable — proven by a positive control, not asserted.
#   3. It NEVER waits, sleeps, or polls (R1). It is an ALARM, not a gate.
#   4. The session census SEES BOTH pid families and dedupes to roots (the landed alarm read 13 of
#      31 real session trees by matching one family only).
#   5. A failed pane query reports null rather than a guess.
#
# The externals (top/ps/osascript) are stubbed on PATH so every rung is reachable without waiting
# for the box to actually be busy.
#
# `|| false` on every non-final [[ ]]/[ ] chain — errexit-exempt assertions are DEAD (memory
# bats-dead-assertions-errexit-exemptions).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  CENSUS="$REPO/scripts/render-census.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CC_RENDER_LOG="$BATS_TEST_TMPDIR/render.jsonl"
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages"
  export CC_RENDER_SAMPLE_S=1
  STUB="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB"
  # PIN THE TERMINAL. The pane count has had a kitty arm since 2026-07-31, and this suite stubs
  # `osascript` — i.e. it asserts the iTerm2 arm SPECIFICALLY. Run from inside kitty (now routine)
  # an inherited KITTY_WINDOW_ID would send the query to a kitty this suite does not stub, making
  # the verdict depend on the operator's own window. Kitty's arm: tests/kitty-recovery-launch.bats.
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
}

# Build a stub `top` whose SECOND sample carries the given iTerm2 / WindowServer / indexing CPU.
# The first sample deliberately carries different (lifetime-average-looking) numbers, so a script
# that read the wrong block would produce a visibly wrong answer instead of accidentally passing.
make_top() { # $1=iterm_cpu $2=ws_cpu $3=indexing_cpu
  cat > "$STUB/top" <<EOF
#!/bin/bash
cat <<'BLOCK'
Processes: 100 total, 2 running, 98 sleeping, 500 threads
PID    COMMAND          %CPU
999    iTerm2           1.0
371    WindowServer     1.0
555    mds_stores       1.0
BLOCK
cat <<'BLOCK'
Processes: 100 total, 2 running, 98 sleeping, 500 threads
PID    COMMAND          %CPU
999    iTerm2           $1
371    WindowServer     $2
555    mds_stores       $3
777    iTermServer-3.6. 4.0
BLOCK
EOF
  chmod +x "$STUB/top"
}

# Build a stub `top` whose SECOND sample ALSO carries a kitty row (and a decoy `kitten`, which the
# exact-match rule must never fold into kitty). Separate from make_top on purpose: the ten tests
# above pin the iTerm2-era arithmetic and must keep reading a kitty-free fleet.
make_top_kitty() { # $1=iterm_cpu $2=kitty_cpu $3=ws_cpu $4=indexing_cpu
  cat > "$STUB/top" <<EOF
#!/bin/bash
cat <<'BLOCK'
Processes: 100 total, 2 running, 98 sleeping, 500 threads
PID    COMMAND          %CPU
999    iTerm2           1.0
600    kitty            1.0
371    WindowServer     1.0
555    mds_stores       1.0
BLOCK
cat <<'BLOCK'
Processes: 100 total, 2 running, 98 sleeping, 500 threads
PID    COMMAND          %CPU
999    iTerm2           $1
600    kitty            $2
371    WindowServer     $3
555    mds_stores       $4
888    kitten           50.0
BLOCK
EOF
  chmod +x "$STUB/top"
}

make_osascript() { # $1=panes (or "fail")
  if [ "$1" = "fail" ]; then
    printf '#!/bin/bash\nexit 1\n' > "$STUB/osascript"
  else
    printf '#!/bin/bash\necho %s\n' "$1" > "$STUB/osascript"
  fi
  chmod +x "$STUB/osascript"
}

# `ps` is called three ways: `ps -M <pid>`, and `ps -eo pid,ppid,etime,args`. The stub answers both.
make_ps() { # $1=proc_table (multi-line "pid ppid etime args")
  cat > "$STUB/ps" <<EOF
#!/bin/bash
if [ "\$1" = "-M" ]; then
  echo "USER       PID   TT   %CPU STAT PRI     STIME     UTIME COMMAND"
  echo "chrisren \$2   ??   90.0 R    47T  49:00.88 618:12.97 /Applications/iTerm.app/Contents/MacOS/iTerm2"
  echo "\$2  45.0 S 37T 0:00.00 0:00.00"
  echo "\$2  5.0 S 37T 0:00.00 0:00.00"
  exit 0
fi
echo "  PID  PPID     ELAPSED ARGS"
cat <<'TABLE'
$1
TABLE
EOF
  chmod +x "$STUB/ps"
}

@test "(i) selftest GREEN — all four rungs + NO-DATA are reachable (positive control, R6)" {
  run /bin/bash "$CENSUS" --selftest
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ "selftest GREEN" ]] || false
  [[ "$output" =~ "→ OK" ]] || false
  [[ "$output" =~ "→ WARN" ]] || false
  [[ "$output" =~ "→ ALARM" ]] || false
  [[ "$output" =~ "→ NO-DATA" ]] || false
}

@test "(ii) OK rung — 1.76 cores (today's measured floor) stays OK, and reads the SECOND sample" {
  make_top 117.6 58.7 1.0; make_osascript 56; make_ps "  1 0 10:00 /sbin/launchd"
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --json --no-append
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ \"verdict\":\"OK\" ]] || false
  # 117.6+58.7 = 176.3 ⇒ 1.76 cores. The first sample would have given 0.02 — proof of block choice.
  [[ "$output" =~ \"render_cores\":1.76 ]] || false
}

@test "(iii) WARN rung — at the budget, rc 1" {
  make_top 200.0 60.0 1.0; make_osascript 56; make_ps "  1 0 10:00 /sbin/launchd"
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --json --no-append
  [ "$status" -eq 1 ] || false
  [[ "$output" =~ \"verdict\":\"WARN\" ]] || false
}

@test "(iv) ALARM rung — above the alarm floor, rc 2, and ALARM outranks WARN" {
  make_top 300.0 80.0 1.0; make_osascript 56; make_ps "  1 0 10:00 /sbin/launchd"
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --json --no-append
  [ "$status" -eq 2 ] || false
  [[ "$output" =~ \"verdict\":\"ALARM\" ]] || false
}

@test "(v) THE LOAD-BEARING ONE — a dead top reports NO-DATA (rc 3), never 0.00 cores as OK" {
  # This is the specific trap this instrument invites: summing two CPU numbers that were never read
  # yields 0.00, which is the BEST possible render reading. A silent failure would therefore look
  # like the healthiest box we have ever measured.
  printf '#!/bin/bash\nexit 1\n' > "$STUB/top"; chmod +x "$STUB/top"
  make_osascript 56; make_ps "  1 0 10:00 /sbin/launchd"
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --json --no-append
  [ "$status" -eq 3 ] || false
  [[ "$output" =~ \"verdict\":\"NO-DATA\" ]] || false
  [[ "$output" =~ \"render_cores\":null ]] || false
  ! [[ "$output" =~ \"verdict\":\"OK\" ]] || false
}

@test "(vi) POSITIVE CONTROL for (v): the SAME code path yields OK with a working top" {
  # Without this, (v) could pass because the script always says NO-DATA.
  make_top 100.0 50.0 1.0; make_osascript 56; make_ps "  1 0 10:00 /sbin/launchd"
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --json --no-append
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ \"verdict\":\"OK\" ]] || false
  ! [[ "$output" =~ \"verdict\":\"NO-DATA\" ]] || false
}

@test "(vii) an idle iTerm2 is 0.00 cores and still OK — absence of load is NOT absence of data" {
  # The counterpart to (v): top RAN and simply found no iTerm2 row. That is a real measurement of a
  # real zero, and must not be laundered into NO-DATA either.
  cat > "$STUB/top" <<'EOF'
#!/bin/bash
echo "Processes: 100 total"
echo "PID    COMMAND          %CPU"
echo "1      launchd          0.0"
echo "Processes: 100 total"
echo "PID    COMMAND          %CPU"
echo "1      launchd          0.0"
EOF
  chmod +x "$STUB/top"
  make_osascript 0; make_ps "  1 0 10:00 /sbin/launchd"
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --json --no-append
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ \"verdict\":\"OK\" ]] || false
  [[ "$output" =~ \"render_cores\":0.00 ]] || false
}

@test "(viii) osascript timeout/failure → panes null, and a verdict is STILL produced" {
  make_top 117.6 58.7 1.0; make_osascript fail; make_ps "  1 0 10:00 /sbin/launchd"
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --json --no-append
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ \"panes\":null ]] || false
  # the render verdict does not depend on the pane query — a blind pane count must not blind the alarm
  [[ "$output" =~ \"verdict\":\"OK\" ]] || false
}

@test "(ix) session census counts BOTH pid families and dedupes to ROOTS" {
  # The landed capacity alarm matched `claude-code/bin/claude.exe` only and reported 13 of 31 real
  # session trees. Population here: 2 roots in family A, 1 root in family B, plus 2 children whose
  # parents are in-family (must NOT be counted) and 1 unrelated proc.
  make_top 117.6 58.7 1.0; make_osascript 56
  make_ps "  100 1 10:00 /Users/x/.claude/claude-code/bin/claude.exe --agent-id a
  101 1 10:00 /Users/x/.claude/claude-code/bin/claude.exe --agent-id b
  200 1 10:00 /Users/x/node_modules/.bin/claude
  300 100 09:00 /Users/x/.claude/claude-code/bin/claude.exe --child-of-100
  301 200 09:00 /Users/x/node_modules/.bin/claude --child-of-200
  400 1 10:00 /usr/bin/unrelated"
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --json --no-append
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ \"sessions\":3 ]] || false
}

@test "(x) POSITIVE CONTROL for (ix): a single-family-only population is NOT read as 3" {
  # Guards the guard: if the regex silently matched everything, (ix) would pass for the wrong reason.
  make_top 117.6 58.7 1.0; make_osascript 56
  make_ps "  100 1 10:00 /Users/x/.claude/claude-code/bin/claude.exe --agent-id a
  400 1 10:00 /usr/bin/unrelated
  401 1 10:00 /usr/bin/also-not-claude"
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --json --no-append
  [[ "$output" =~ \"sessions\":1 ]] || false
}

@test "(xi) mdworker spawn count is bounded by the sample window (etime parsing, all 3 shapes)" {
  # macOS ps has no `etimes` keyword, so etime is parsed from MM:SS / HH:MM:SS / DD-HH:MM:SS.
  # Only the two young mdworkers are inside a 1-second window.
  make_top 117.6 58.7 1.0; make_osascript 56
  make_ps "  10 1 00:00 /System/.../Support/mdworker_shared
  11 1 00:01 /System/.../Support/mdworker
  12 1 05:00 /System/.../Support/mdworker_shared
  13 1 02:05:18:11 /System/.../Support/mdworker
  14 1 01:00:00 /System/.../Support/mdworker"
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --json --no-append
  [[ "$output" =~ \"mdworker_spawns_in_window\":2 ]] || false
}

@test "(xii) page is written on ALARM and names the shed platter" {
  make_top 300.0 80.0 1.0; make_osascript 56; make_ps "  1 0 10:00 /sbin/launchd"
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --quiet
  [ "$status" -eq 2 ] || false
  [ -f "$CC_PAGES_DIR/render-census.page" ] || false
  run cat "$CC_PAGES_DIR/render-census.page"
  [[ "$output" =~ "cc-reaper --watchdog-census" ]] || false
  [[ "$output" =~ "/handoff" ]] || false
  [[ "$output" =~ "iTerm2" ]] || false
  # it must say what it is, so nobody mistakes it for a gate
  [[ "$output" =~ "ALARM, not a gate" ]] || false
}

@test "(xiii) page SELF-CLEARS on OK — a passed condition is misinformation, not history" {
  mkdir -p "$CC_PAGES_DIR"
  printf 'stale\n' > "$CC_PAGES_DIR/render-census.page"
  printf 'stale\n' > "$CC_PAGES_DIR/render-census.page.notified"
  make_top 100.0 50.0 1.0; make_osascript 56; make_ps "  1 0 10:00 /sbin/launchd"
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --quiet
  [ "$status" -eq 0 ] || false
  [ ! -f "$CC_PAGES_DIR/render-census.page" ] || false
  [ ! -f "$CC_PAGES_DIR/render-census.page.notified" ] || false
}

@test "(xiv) NO-DATA clears the page too — a stale ALARM while blind asserts what we cannot see" {
  mkdir -p "$CC_PAGES_DIR"
  printf 'stale\n' > "$CC_PAGES_DIR/render-census.page"
  printf '#!/bin/bash\nexit 1\n' > "$STUB/top"; chmod +x "$STUB/top"
  make_osascript 56; make_ps "  1 0 10:00 /sbin/launchd"
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --quiet
  [ "$status" -eq 3 ] || false
  [ ! -f "$CC_PAGES_DIR/render-census.page" ] || false
}

@test "(xv) jsonl row is appended and carries the honest hot-thread provenance" {
  make_top 117.6 58.7 1.0; make_osascript 56; make_ps "  1 0 10:00 /sbin/launchd"
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --quiet
  [ -f "$CC_RENDER_LOG" ] || false
  run cat "$CC_RENDER_LOG"
  [[ "$output" =~ \"render_cores\":1.76 ]] || false
  # ps -M is a LIFETIME AVERAGE, not the `sample`-based instantaneous share §11.9 reported. The row
  # must say which instrument produced it so a future reader cannot conflate the two.
  [[ "$output" =~ \"hot_thread_src\":\"ps-M-lifetime-avg\" ]] || false
  [[ "$output" =~ \"hot_thread_pct\":45.0 ]] || false
}

@test "(xvi) kill switch CC_RENDER_CENSUS=off → rc 0 and NO log write" {
  run env CC_RENDER_CENSUS=off CC_RENDER_LOG="$BATS_TEST_TMPDIR/ks.jsonl" /bin/bash "$CENSUS" --quiet
  [ "$status" -eq 0 ] || false
  [ ! -f "$BATS_TEST_TMPDIR/ks.jsonl" ] || false
}

@test "(xvii) R1 — never sleeps, polls, or waits on load (EXECUTABLE lines only)" {
  # Comments are stripped first: the header PROSE says it never sleeps or polls, and a bare grep
  # would convict the very documentation of the property it checks (memory
  # detector-matching-its-own-skill-description). The existence guard stops the test passing
  # vacuously against a tree with no render-census.sh at all.
  [ -f "$CENSUS" ] || false
  run bash -c "sed 's/#.*//' '$CENSUS' | grep -nE '\\bsleep\\b|while.*load|until.*load|loadavg'"
  [ "$status" -ne 0 ] || false
}

@test "(xviii) POSITIVE CONTROL for (xvii): the comment-stripped grep still catches a real sleep" {
  printf '# we never sleep here\nsleep 5\n' > "$BATS_TEST_TMPDIR/bait.sh"
  run bash -c "sed 's/#.*//' '$BATS_TEST_TMPDIR/bait.sh' | grep -nE '\\bsleep\\b'"
  [ "$status" -eq 0 ] || false
  printf '# we never sleep here\n:\n' > "$BATS_TEST_TMPDIR/clean.sh"
  run bash -c "sed 's/#.*//' '$BATS_TEST_TMPDIR/clean.sh' | grep -nE '\\bsleep\\b'"
  [ "$status" -ne 0 ] || false
}

# NOTE: no backticks in a @test NAME — bash evaluates them as command substitution while bats
# GATHERS the tests, which fails the whole file at parse time with `not ok 1 bats-gather-tests`
# before a single test runs (cost an hour here; the suite looked hung rather than broken).
@test "(xix) the -n 0 flag is never passed to top — it suppresses every process row" {
  # Verified on this box: `top -l 2 -n 0` prints only the header block, so the census would read an
  # empty fleet forever while looking perfectly healthy. Regression guard for a documented trap.
  [ -f "$CENSUS" ] || false
  run bash -c "sed 's/#.*//' '$CENSUS' | grep -nE 'top .*-n 0|top .*-n0'"
  [ "$status" -ne 0 ] || false
}

# ── THE TERMINAL THE FLEET ACTUALLY RENDERS IN (2026-08-11) ───────────────────────────────────────
# 09-adv-constants.md §2 / 02-render.md §6 D1: the render SUM matched iTerm2 + WindowServer only,
# while every pane on the box is drawn by kitty — so the instrument was blind to exactly the
# per-pane term its 3.5-core alarm exists to catch, and under-read by 23-26% live.

@test "(xx) kitty CPU is IN the render sum — the fleet's real terminal is counted" {
  # iTerm2 0.0 (it is gone), kitty 90.0, WindowServer 60.0 ⇒ 150.0% ⇒ 1.50 cores.
  # Kitty-blind, the same fleet reads 0.60 — the live 2026-08-09 shape exactly.
  make_top_kitty 0.0 90.0 60.0 1.0; make_osascript 56; make_ps "  1 0 10:00 /sbin/launchd"
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --json --no-append
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ \"render_cores\":1.50 ]] || false
  [[ "$output" =~ \"kitty_cpu_pct\":90.0 ]] || false
  # the decoy: top's COMMAND column also carries `kitten` at 50.0%. EXACT match, never substring —
  # folding the short-lived helpers into kitty would inflate the sum to 2.00.
  ! [[ "$output" =~ \"render_cores\":2.00 ]] || false
}

@test "(xxi) MUTATION CONTROL for (xx): deleting the kitty arm makes the sum under-read again" {
  # Guards the guard. Without this, (xx) could pass on a script that hard-codes 1.50 or that counts
  # kitty into a field nothing sums. The mutant is syntax-checked first: a malformed mutant reds
  # everything, which reads as maximal coverage while proving nothing.
  MUT="$BATS_TEST_TMPDIR/mut-kitty-blind.sh"
  sed '/if (cmd == "kitty")/d' "$CENSUS" > "$MUT"
  bash -n "$MUT" || { echo "mutant is malformed — it would red everything and prove nothing"; return 1; }
  ! grep -q 'if (cmd == "kitty")' "$MUT" || skip "sed anchor missed; nothing mutated"
  make_top_kitty 0.0 90.0 60.0 1.0; make_osascript 56; make_ps "  1 0 10:00 /sbin/launchd"
  # CONTROL FIRST — the real script must read 1.50 here, or a difference proves nothing.
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --json --no-append
  [[ "$output" =~ \"render_cores\":1.50 ]] || { echo "control failed: unmutated census does not read 1.50"; return 1; }
  run env PATH="$STUB:$PATH" /bin/bash "$MUT" --json --no-append
  [[ "$output" =~ \"render_cores\":0.60 ]] || { echo "mutation changed nothing — (xx) is not pinning the kitty arm"; return 1; }
  ! [[ "$output" =~ \"render_cores\":1.50 ]] || false
}

@test "(xxii) WindowServer is split out as a SHARED compositor term, not billed to the terminal" {
  # 02-render.md §6 D2: WindowServer is the whole-desktop compositor (4 displays ≈ 52 Mpx, browser
  # at 73% CPU concurrently). Only 0.002-0.009 cores/pane of it is the terminal's. render_cores
  # still sums both — the alarm floors were calibrated against that total — but the row must say
  # which half is which, so nobody sheds panes at a browser.
  make_top_kitty 0.0 90.0 60.0 1.0; make_osascript 56; make_ps "  1 0 10:00 /sbin/launchd"
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --json --no-append
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ \"terminal_cores\":0.90 ]] || false
  [[ "$output" =~ \"compositor_cores\":0.60 ]] || false
  [[ "$output" =~ \"compositor_attrib\":\"shared-desktop-not-terminal-only\" ]] || false
  # and the two halves must reconstruct the published total — an annotation that does not add up is
  # a second wrong number, not a fix
  [[ "$output" =~ \"render_cores\":1.50 ]] || false
}

@test "(xxiii) the human readout names the compositor share as SHARED" {
  # The jsonl is for machines; the operator reads the block. An honest field with a lying line above
  # it is still a lying instrument.
  make_top_kitty 0.0 90.0 60.0 1.0; make_osascript 56; make_ps "  1 0 10:00 /sbin/launchd"
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --no-append
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ "terminal cores" ]] || false
  [[ "$output" =~ "compositor cores" ]] || false
  [[ "$output" =~ "SHARED" ]] || false
  [[ "$output" =~ "iTerm2 / kitty / WS" ]] || false
}

@test "(xxiv) top consumer can be kitty — the platter never points at an app that is not running" {
  # Pre-fix, iTerm2 was the only terminal in the comparison, so on a kitty fleet the shed platter
  # said "top consumer is iTerm2" at 0.0% while kitty drew everything.
  make_top_kitty 0.0 90.0 60.0 1.0; make_osascript 56; make_ps "  1 0 10:00 /sbin/launchd"
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --json --no-append
  [[ "$output" =~ \"top_consumer\":\"kitty\" ]] || false
  [[ "$output" =~ \"top_consumer_pct\":90.0 ]] || false
}

@test "(xxv) when WindowServer wins it is named SHARED on the page, with panes named as NOT the lever" {
  # 340% WS against 20% kitty ⇒ 3.60 cores ⇒ ALARM (floor 3.5), with the compositor on top. The page
  # must not send the operator to close panes at a browser and four 5K displays.
  make_top_kitty 0.0 20.0 340.0 1.0; make_osascript 56; make_ps "  1 0 10:00 /sbin/launchd"
  run env PATH="$STUB:$PATH" /bin/bash "$CENSUS" --quiet
  [ "$status" -eq 2 ] || false
  [ -f "$CC_PAGES_DIR/render-census.page" ] || false
  run cat "$CC_PAGES_DIR/render-census.page"
  [[ "$output" == *"WindowServer(shared)"* ]] || false
  [[ "$output" =~ "panes are NOT the lever" ]] || false
  [[ "$output" == *"compositor (WindowServer, SHARED)"* ]] || false
}
