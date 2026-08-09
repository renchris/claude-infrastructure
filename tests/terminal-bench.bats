#!/usr/bin/env bats
# terminal-bench — guards on the two instruments that will decide a terminal-emulator change
# (scripts/terminal-bench.sh, scripts/tui-load.sh, tools/terminal-bench/window-census.swift).
#
# WHY THESE SPECIFIC TESTS. Both instruments already produced a confidently wrong reading during
# development, and both failures were SILENT:
#   · tui-load.sh ran at 7,651 fps against a requested 10, because macOS bash 3.2 rejects a
#     fractional `read -t` and the error was swallowed by `2>/dev/null` — a busy loop wearing the
#     costume of a rate-limited one.
#   · terminal-bench.sh derived its repo root with `dirname "$0"/..`, which through the live
#     per-file-symlink layer resolves to ~/.claude — no tools/ there, so every window column would
#     have read NA while the script still exited 0.
# A measurement instrument that fails silently is worse than none, because its output gets quoted.
# So the tests below assert on the FAILURE paths, and each guard gets a control that can fail.

setup() {
  # Fixture $HOME. These tests launch scripts that read ${TMPDIR}/ and could write stats files; a
  # suite that runs against the live ~/ can perturb the operator's real state, and the hermeticity
  # lint (scripts/test-hermeticity-lint.sh) fails the build for exactly this.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  BENCH="$REPO/scripts/terminal-bench.sh"
  LOAD="$REPO/scripts/tui-load.sh"
  CENSUS_SRC="$REPO/tools/terminal-bench/window-census.swift"
  STATS="$BATS_TEST_TMPDIR/stats.tsv"
}

# ── terminal-bench: absence must be loud ──────────────────────────────────────────────────────────

@test "bench: a non-running app yields verdict=NO-DATA and exit 3, never a clean row" {
  # The whole point. If this returned 0 with zeroed columns, a candidate terminal that failed to
  # launch would be filed as "measured: costs nothing" — the vacuous pass this repo keeps re-learning.
  run bash "$BENCH" --app NoSuchTerminalApp7391 --interval 0
  [ "$status" -eq 3 ]
  [[ "$output" == *"verdict=NO-DATA"* ]]
}

@test "bench: resolves a process whose p_comm is a FULL PATH, which is how the incumbent hid" {
  # THE BUG THIS PINS. `pgrep -x iTerm2` matched nothing on 2026-07-31 while iTerm2 ran as pid 591:
  # macOS had stored its accounting name as the first 16 chars of the full path (`/Applications/iT`),
  # so an exact-name match could never hit it. pgrep listed 947 of 960 processes and dropped it.
  # The bake-off therefore filed its INCUMBENT as "not running" — a NO-DATA that reads like an
  # absent app rather than a blind instrument. Same class as memory claimed-outcome-vs-checked.
  #
  # We assert the resolver's fallback (ps comm BASENAME) on a process we control, so the test is
  # hermetic and needs no GUI app running.
  # Driven from a FIXTURE of real `ps -eo pid=,comm=` output rather than a live process: a copied
  # system binary is SIGKILLed by macOS code-signing the moment it execs (tried — the probe was dead
  # before ps could see it), and depending on a GUI app being up would make the test non-hermetic.
  # These two lines are verbatim what this box printed on 2026-07-31.
  local fixture="  591 /Applications/iTerm.app/Contents/MacOS/iTerm2
26094 /Applications/kitty.app/Contents/MacOS/kitty"

  local found
  found="$(printf '%s\n' "$fixture" | awk -v want="iTerm2" '{n=split($2,a,"/"); if (a[n]==want) {print $1; exit}}')"
  [ "$found" = "591" ]

  # and it must still discriminate — not just return the first row it sees
  found="$(printf '%s\n' "$fixture" | awk -v want="kitty" '{n=split($2,a,"/"); if (a[n]==want) {print $1; exit}}')"
  [ "$found" = "26094" ]
}

@test "POSITIVE CONTROL: the basename resolver reports nothing for an absent name" {
  # Without this, the test above would also pass for a resolver that returns any pid unconditionally.
  local fixture="  591 /Applications/iTerm.app/Contents/MacOS/iTerm2"
  local found
  found="$(printf '%s\n' "$fixture" | awk -v want="Ghostty" '{n=split($2,a,"/"); if (a[n]==want) {print $1; exit}}')"
  [ -z "$found" ]
}

@test "RED CONTROL: a bare exact-name match CANNOT find the incumbent — this is the bug" {
  # The guard is only meaningful if the OLD behaviour demonstrably fails on the same input. An
  # exact match against the whole comm string is what `pgrep -x iTerm2` effectively did, and it
  # returns nothing for a comm that is a full path. If this ever starts passing, the fallback above
  # has stopped being necessary and should be re-justified rather than kept out of habit.
  local fixture="  591 /Applications/iTerm.app/Contents/MacOS/iTerm2"
  local found
  found="$(printf '%s\n' "$fixture" | awk -v want="iTerm2" '{if ($2==want) {print $1; exit}}')"
  [ -z "$found" ]
}

@test "bench: --app is mandatory (exit 2), so a typo cannot silently measure nothing" {
  run bash "$BENCH" --interval 0
  [ "$status" -eq 2 ]
}

# ── the emitter pad: every column must stay in its own column ──────────────────────────────────────
#
# WHY THIS LIVES HERE AND NOT ONLY IN tests/tsv-field-collapse.bats. `reading()` emits a 7-cell TSV
# row that `show()` reads with `IFS=$'\t' read`. Tab is an IFS-*whitespace* character, so that read
# COLLAPSES a run of delimiters: one empty cell does not yield an empty variable, it shifts every
# later column one position LEFT, silently, at exit status 0 — ports takes windows' value and the
# last column comes back empty. Splitting on tab explicitly does not prevent it; only a non-empty
# cell does, which is why `reading()` pads each cell to "-".
#
# That pad landed at 68e17e2a and was reverted three hours later by 68694672 — a whole-function
# rewrite from a stale base whose subject was about pgrep and which said nothing about padding. It
# went unnoticed for a week because the ONLY thing pinning it was the whole-tree guard in
# tests/tsv-field-collapse.bats §3, which no author's land is required to run against their own
# diff. A cross-cutting guard cannot defend a single file's behaviour; this file's own gate can.
#
# `top` is shadowed rather than mocked at a seam because there is no seam: reading() calls it by
# bare name. A short `top` line is not hypothetical — it is one of the two live sources of an empty
# cell named in reading()'s own comment (the other being `cut -f3/-f5/-f7` on a short census row).
stub_top_short() {
  # `top -stats pid,command,cpu,mem,th,ports` normally prints six fields. This one prints FIVE, so
  # reading()'s `awk '{print $6}'` for ports yields the empty string — the defect's real input.
  STUBDIR="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUBDIR"
  cat > "$STUBDIR/top" <<'STUB'
#!/bin/bash
p=""; while [ $# -gt 0 ]; do [ "$1" = "-pid" ] && p="$2"; shift; done
printf '%s stubbed 1.2 100M 13\n' "$p"
STUB
  chmod +x "$STUBDIR/top"
  PATH="$STUBDIR:$PATH"
}

@test "emitter pad: an empty ports cell does not slide windows into the ports column" {
  # Drives the REAL script end to end. Census cells are 21/20/1.00 (windows/offscreen/onscreenMpx),
  # so the shift is unambiguous: unpadded renders ports=21 win=20 off=1.00 mpx=<empty> — every
  # column past the hole wearing its neighbour's number, and the row still exits 0.
  start_subject
  stub_census 1 20
  stub_top_short
  run bash "$BENCH" --app "$SUBJ_NAME" --interval 0 --sample-secs 1
  [[ "$output" == *"cpu=1.2 mem=100MB th=13 ports=- win=21 off=20 mpx=1.00"* ]] || false

  # …and the collapse signature specifically: the last column emptied by a hole further left.
  [[ "$output" != *"mpx="$'\n'* ]] || false
  [[ "$output" != *"ports=21"* ]]
}

@test "RED CONTROL: un-padding the SHIPPING emitter makes the row slide again" {
  # A guard whose failure mode is unreachable proves nothing, and a hand-written approximation of
  # the emitter would pass vacuously no matter what the real one does (memory
  # control-must-replay-the-real-artifact). So the mutant is the REAL file with exactly one edit:
  # the pad stripped back to the post-revert shape 68694672 left behind.
  start_subject
  stub_census 1 20
  stub_top_short

  local mutant="$BATS_TEST_TMPDIR/unpadded.sh"
  sed 's/"${cpu:--}" "${mem:--}" "${th:--}" "${ports:--}" "${win:--}" "${off:--}" "${mpx:--}"/"$cpu" "$mem" "$th" "$ports" "$win" "$off" "$mpx"/' \
    "$BENCH" > "$mutant"
  # The mutation must have LANDED. A sed whose anchor silently missed produces a byte-identical copy
  # that then "fails to slide" and reads as the guard working. Anchored on the PADDED form, which
  # occurs exactly once — counting the un-padded form instead reads 2, because `show()`'s own printf
  # carries a byte-identical argument list one line further down. Measured, not assumed.
  run grep -c 'cpu:--' "$BENCH"
  [ "$output" = "1" ]
  run grep -c 'cpu:--' "$mutant"
  [ "$output" = "0" ]
  run bash -n "$mutant"
  [ "$status" -eq 0 ]

  run bash "$mutant" --app "$SUBJ_NAME" --interval 0 --sample-secs 1
  # windows' 21 in the ports column, offscreen's 20 in windows', and the last column emptied —
  # every one of them at exit status 0, which is what made this survive a week undetected.
  [[ "$output" == *"th=13 ports=21 win=20 off=1.00 mpx="* ]] || false
  [[ "$output" != *"ports=-"* ]]
}

@test "bench: resolves its repo root THROUGH a symlink, not to the symlink's parent" {
  # RED-PROOF of the self-path fix. Invoked via a symlink in a directory with no tools/ sibling,
  # the pre-fix code resolved REPO to that directory and warned/degraded. The fix walks the link
  # chain, so the census source must still be found.
  ln -s "$BENCH" "$BATS_TEST_TMPDIR/linked-bench.sh"
  run bash "$BATS_TEST_TMPDIR/linked-bench.sh" --app NoSuchTerminalApp7391 --interval 0
  # It still exits NO-DATA (no such app) — but it must NOT have complained about a missing census.
  [[ "$output" != *"census source not found"* ]]
}

@test "POSITIVE CONTROL: with every cell populated, padded and unpadded agree" {
  # The pad must be inert on the common path — a fix that changed the reading of a COMPLETE row
  # would silently invalidate every measurement already filed against this instrument.
  run bash -c '
    cpu=12.3 mem=783 th=44 ports=95 win=21 off=20 mpx=1.00
    bare="$(printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$cpu" "$mem" "$th" "$ports" "$win" "$off" "$mpx")"
    pad="$(printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "${cpu:--}" "${mem:--}" "${th:--}" "${ports:--}" "${win:--}" "${off:--}" "${mpx:--}")"
    if [ "$bare" = "$pad" ]; then printf identical; fi'
  [ "$output" = "identical" ]
}

# ── tui-load: the rate it claims must be the rate it achieved ─────────────────────────────────────

@test "load: writes a 10-field stats row including strategy, flag and the measured geometry" {
  run bash "$LOAD" --fps 10 --duration 1 --label unit --stats "$STATS"
  [ "$status" -eq 0 ]
  [ -s "$STATS" ]
  local fields; fields="$(awk -F'\t' '{print NF; exit}' "$STATS")"
  [ "$fields" -eq 10 ]
  # Field 10 is <cols>x<rows>/<source>, and the SOURCE is the load-bearing half. `tput cols` inside
  # a command substitution reports the terminfo default 80x24 rather than the pane — measured in one
  # WezTerm pane, same instant: tput 80x24 vs stty 44 95 — so every pane in that terminal painted a
  # fixed small frame while kitty painted full-size ones, and the "identical load in every
  # candidate" premise silently did not hold. Recording which probe answered is what lets a later
  # reader tell a comparable run from a non-comparable one.
  local geom; geom="$(awk -F'\t' '{print $10; exit}' "$STATS")"
  [[ "$geom" =~ ^[0-9]+x[0-9]+/(stty|tput|default)$ ]] || false
  # The nap strategy is RECORDED, never inferred: a reader must be able to tell a forkless run from
  # a `sleep`-per-frame run, because only the latter's absolute CPU carries a producer tax.
  local strategy; strategy="$(awk -F'\t' '{print $8; exit}' "$STATS")"
  [[ "$strategy" == "perl" || "$strategy" == "sleep" ]]
}

@test "load: a run that achieves its requested rate is flagged OK" {
  run bash "$LOAD" --fps 5 --duration 2 --label ok --stats "$STATS"
  local flag; flag="$(awk -F'\t' '{print $9; exit}' "$STATS")"
  [ "$flag" = "OK" ]
}

@test "POSITIVE CONTROL: a consumer that cannot keep up makes the row self-condemn as SUSPECT" {
  # This control is what makes the OK above mean anything: without it, a flag hardcoded to "OK"
  # would pass every other test in this file.
  #
  # IT WENT STALE TWICE BEFORE REACHING THIS FORM, and that history is the reason for the design.
  # v1 asked for 5,000 fps — unreachable while every frame cost a `sleep` fork. Moving to the
  # deadline-corrected perl emitter made 5,000 fps easy, so the control started passing and silently
  # stopped guarding. v2 raised the bar to 1,000,000 fps; the emitter MET IT (999,999 achieved, ~2
  # GB/s into /dev/null), so that died too. Any threshold calibrated against the implementation dies
  # the moment the implementation improves (memory work-item-remedy-can-become-forbidden).
  #
  # v3 abandons rate thresholds entirely and drives the MECHANISM the flag exists to detect: a
  # consumer too slow to accept the load. The reader sleeps before draining, so the 64 KB pipe fills,
  # the emitter blocks in write(), and delivery collapses far below the request. A faster emitter
  # only blocks SOONER — the control strengthens as the code improves instead of decaying. This is
  # also the real-world condition being guarded: a terminal that cannot keep up with 30 panes.
  local err="$BATS_TEST_TMPDIR/err"
  bash -c "bash '$LOAD' --fps 200 --duration 2 --label blocked --stats '$STATS' 2>'$err' | ( sleep 4; cat >/dev/null )"
  local flag; flag="$(awk -F'\t' '{print $9; exit}' "$STATS")"
  [ "$flag" = "SUSPECT" ]
  grep -q SUSPECT "$err"
}

@test "load: restores the terminal on exit (no alternate screen left armed)" {
  # A generator killed mid-run must still emit the leave-alt-screen sequence, or every subsequent
  # measurement in that pane is taken against a corrupted terminal state.
  run bash -c "bash '$LOAD' --fps 10 --duration 1 --label restore --stats '$STATS' | tail -c 24 | cat -v"
  [[ "$output" == *"[?1049l"* ]]
}

# ── window census: an empty answer is NO-DATA, not zero ───────────────────────────────────────────

@test "census: an owner with no windows reports NO-DATA, not a clean zero" {
  command -v swiftc >/dev/null || skip "swiftc unavailable — control cannot run, so it must not pass"
  local bin="$BATS_TEST_TMPDIR/wc"
  swiftc -O "$CENSUS_SRC" -o "$bin" 2>/dev/null || skip "swiftc could not build the census"
  run "$bin" --owner NoSuchOwner7391
  [ "$status" -eq 3 ]
  [[ "$output" == *"verdict=NO-DATA"* ]]
}

@test "census: a real desktop reports verdict=OK with a nonzero window total" {
  command -v swiftc >/dev/null || skip "swiftc unavailable"
  local bin="$BATS_TEST_TMPDIR/wc"
  swiftc -O "$CENSUS_SRC" -o "$bin" 2>/dev/null || skip "swiftc could not build the census"
  run "$bin" --tsv
  # A logged-in Mac always has windows; an empty list means the CALL failed, which is why the tool
  # reports NO-DATA rather than "0 windows" in that case.
  if [ "$status" -eq 3 ]; then skip "no window server in this context (headless runner)"; fi
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=OK"* ]] || false
}

# ── the constant-layout PRECONDITION (added 2026-07-31) ───────────────────────────────────────────
# THE BUG THESE PIN. The 2026-07-31 22:17Z 30-minute kitty run returned `verdict=OK` and its
# +10 ports/hr is unusable: the window census fell 36 → 19 while the interval held. `verdict=OK`
# certified that two readings and a GPU profile were obtained and NOTHING about layout stability,
# so the confounded row was indistinguishable from the clean bound §6.1 is still waiting for.
#
# These drive the REAL script end-to-end rather than re-implementing its comparison, because the
# defect is in control flow (what the script DOES with a broken precondition), which no extracted
# expression can pin. The census is stubbed through the script's own documented derivation —
# CENSUS_BIN is "${TMPDIR}/window-census.$(id -u)" and is rebuilt only when the .swift source is
# NEWER — so a fresh executable at that path inside a fixture TMPDIR is used as-is, untouched.

# The stub answers from a single mutable file, and the layout is moved by a BACKGROUND writer at a
# wall-clock offset. An earlier version encoded the whole timeline as "value at t+N" measured from
# test setup and THREE of these tests passed or failed for the wrong reason: the script's baseline
# probe does not happen at t+0, it happens after two `top -l 2` samples and the GPU sample — about
# five seconds in — by which point a "change at t+2" had already been folded into the baseline, so
# there was nothing left to detect. Hence two rules that every test below obeys:
#   · the flip is scheduled well clear of that start-up cost, and
#   · every test ASSERTS THE PRINTED BASELINE, so a run whose timing slipped fails loudly instead of
#     certifying a layout that never moved. A control that cannot fail is not a control.
stub_census() {   # initial "<onscreen>" "<offscreen>"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  printf '%s %s\n' "$1" "$2" > "$TMPDIR/current"
  cat > "$TMPDIR/window-census.$(id -u)" <<'STUB'
#!/bin/bash
d="$(dirname "$0")"
read -r on off < "$d/current"
[ -n "${on:-}" ] || exit 3
printf 'owner\tpid\twindows\tonscreen\toffscreen\tzeroArea\tonscreenMpx\tlayers\n'
printf 'stub\t1\t%s\t%s\t%s\t0\t1.00\t1\n' "$((on+off))" "$on" "$off"
STUB
  chmod +x "$TMPDIR/window-census.$(id -u)"
}

# Moves the layout mid-run. Written via an atomic rename so a poll can never read a half-written
# file and mistake it for a census failure. Its three standard fds are detached: an abort test ends
# while a later flip is still sleeping, and a background child that still holds bats' TAP descriptor
# keeps the run open after the test has finished (memory fixture-lifetime-is-an-orphan-leak-bound,
# where exactly this wedged a suite for five minutes). teardown kills them regardless.
flip_layout_after() {  # seconds onscreen offscreen
  ( sleep "$1"; printf '%s %s\n' "$2" "$3" > "$TMPDIR/.next"; mv "$TMPDIR/.next" "$TMPDIR/current" ) \
    >/dev/null 2>&1 </dev/null &
  FLIP_PIDS="${FLIP_PIDS:-} $!"
}

# A census that runs but answers nothing — the "I could not look" state, which must never be
# spelled the same way as "I looked and it was fine".
stub_census_silent() {
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  printf '#!/bin/bash\nexit 3\n' > "$TMPDIR/window-census.$(id -u)"
  chmod +x "$TMPDIR/window-census.$(id -u)"
}

# A uniquely-named subject we control, so the run cannot be hijacked by a stray system process and
# cannot die underneath the test. A SYMLINK to /bin/sleep, never a copy: macOS code-signing SIGKILLs
# a copied system binary at exec (the note on the resolver test above), while the symlink execs the
# signed original and still takes the link's basename as its p_comm.
start_subject() {
  SUBJ_NAME="tbsubject$$"
  ln -sf /bin/sleep "$BATS_TEST_TMPDIR/$SUBJ_NAME"
  "$BATS_TEST_TMPDIR/$SUBJ_NAME" 240 &
  SUBJ_PID=$!
  sleep 0.3
}
teardown() {
  [ -n "${SUBJ_PID:-}" ] && kill "$SUBJ_PID" 2>/dev/null || true
  for p in ${FLIP_PIDS:-}; do kill "$p" 2>/dev/null || true; done
  return 0
}

# Seconds to wait before moving the layout. Must clear the script's pre-hold cost — T0 app reading,
# T0 WindowServer reading (a `top -l 2` each) and the GPU sample — measured at ~5 s on this box.
FLIP_AT=12

@test "precondition: a RISING offscreen count is the SIGNAL, and must NOT abort the measurement" {
  # THE CONTROL THAT KILLS THE OBVIOUS IMPLEMENTATION. The tempting gate is the `windows` column
  # the script already reads — but that is the ON- AND OFF-SCREEN TOTAL, and a growing offscreen
  # population is precisely the window leak this instrument exists to convict. A gate keyed on it
  # makes a leaking terminal abort its own measurement and become structurally unable to report the
  # leak. So: offscreen 20 → 25 at constant onscreen must still produce a drift row.
  start_subject
  stub_census 1 20
  flip_layout_after "$FLIP_AT" 1 25
  run bash "$BENCH" --app "$SUBJ_NAME" --interval 20 --watch 1 --sample-secs 1
  [[ "$output" == *"baseline: onscreen=1 offscreen=20"* ]] || false
  [[ "$output" != *"PRECONDITION BROKE"* ]] || false
  [[ "$output" == *"CERTIFIED-constant layout"* ]] || false
  [[ "$output" == *"offscreen win  +5"* ]] || false
  [[ "$output" != *"verdict=LAYOUT-DRIFT"* ]] || false
  [ "$status" -eq 0 ]
}

@test "precondition: onscreen CHANGING aborts with verdict=LAYOUT-DRIFT and exit 4, no drift row" {
  # The 22:17Z failure, reproduced: panes opened or closed underneath the interval. Ports move WITH
  # windows, so the delta cannot be split into leaked-versus-released — the row must not be printed
  # at all, because a caveat does not travel with a number once it is quoted.
  #
  # This also pins LAYOUT-DRIFT as STICKY for free: the subject is a `sleep`, whose sample matches
  # no GPU or CPU discriminator, so the GPU axis is NO-DATA. If the final downgrade were allowed to
  # rewrite this verdict the way it rewrites OK, this would read PARTIAL.
  start_subject
  stub_census 1 20
  flip_layout_after "$FLIP_AT" 4 20
  run bash "$BENCH" --app "$SUBJ_NAME" --interval 45 --watch 1 --sample-secs 1
  [[ "$output" == *"baseline: onscreen=1 offscreen=20"* ]] || false
  [ "$status" -eq 4 ]
  [[ "$output" == *"verdict=LAYOUT-DRIFT"* ]] || false
  [[ "$output" == *"PRECONDITION BROKE"* ]] || false
  [[ "$output" == *"onscreen 1→4"* ]] || false
  [[ "$output" != *"DRIFT (app"* ]]
}

@test "precondition: a poll catches a window that opens and closes INSIDE the interval" {
  # Why polling exists at all rather than just comparing the two endpoints. Here onscreen goes
  # 1 → 3 → 1, so both endpoints agree and an endpoint-only gate would certify the window as
  # constant — while the ports had already been allocated and freed underneath it.
  # The abort must therefore be attributed to a POLL (t+Ns), not to the endpoint check.
  start_subject
  stub_census 1 20
  flip_layout_after "$FLIP_AT" 3 20
  flip_layout_after "$((FLIP_AT + 8))" 1 20
  run bash "$BENCH" --app "$SUBJ_NAME" --interval 45 --watch 1 --sample-secs 1
  [[ "$output" == *"baseline: onscreen=1 offscreen=20"* ]] || false
  [ "$status" -eq 4 ]
  [[ "$output" == *"onscreen 1→3"* ]] || false
  [[ "$output" == *"PRECONDITION BROKE — t+"* ]] || false
  [[ "$output" != *"PRECONDITION BROKE — endpoint"* ]]
}

@test "precondition: a FALLING offscreen count aborts — released windows move ports too" {
  # The other half of the asymmetry. Offscreen rising is the signal; offscreen falling is a release
  # event that churns the population, and the 22:17Z run's −18 offscreen is exactly what made its
  # +5 ports uninterpretable.
  start_subject
  stub_census 1 20
  flip_layout_after "$FLIP_AT" 1 12
  run bash "$BENCH" --app "$SUBJ_NAME" --interval 45 --watch 1 --sample-secs 1
  [[ "$output" == *"baseline: onscreen=1 offscreen=20"* ]] || false
  [ "$status" -eq 4 ]
  [[ "$output" == *"offscreen 20→12"* ]]
}

@test "precondition: a census that cannot answer yields PARTIAL — never OK" {
  # The header has promised since the file was written that a missing window census yields PARTIAL.
  # Until 2026-07-31 the code set VERDICT=OK unconditionally once two readings existed, so a run
  # with no census at all — the case where layout stability is pure assumption — was filed as a
  # full comparable row. "I could not look" must not be spelled like "I looked and it was fine".
  start_subject
  stub_census_silent
  run bash "$BENCH" --app "$SUBJ_NAME" --interval 4 --watch 1 --sample-secs 1
  [[ "$output" == *"verdict=PARTIAL"* ]] || false
  [[ "$output" == *"layout UNCERTIFIED"* ]] || false
  [[ "$output" != *"verdict=OK"* ]]
}

@test "the JSONL row carries the SAME verdict as stdout" {
  # The machine-readable sink used to be appended BEFORE the final downgrade, so a run whose stdout
  # read PARTIAL could leave "OK" in the file a consumer parses — the overclaim landing on the
  # surface that gets quoted rather than the one a human reads.
  start_subject
  stub_census 1 20
  flip_layout_after "$FLIP_AT" 9 20
  local out="$BATS_TEST_TMPDIR/rows.jsonl"
  run bash "$BENCH" --app "$SUBJ_NAME" --interval 45 --watch 1 --sample-secs 1 --out "$out"
  [[ "$output" == *"baseline: onscreen=1 offscreen=20"* ]] || false
  local stdout_verdict; stdout_verdict="$(printf '%s\n' "$output" | sed -n 's/^verdict=//p' | tail -1)"
  local json_verdict;   json_verdict="$(sed -n 's/.*"verdict":"\([^"]*\)".*/\1/p' "$out" | tail -1)"
  [ "$stdout_verdict" = "LAYOUT-DRIFT" ]
  [ "$json_verdict" = "$stdout_verdict" ]
  grep -q '"layout":"broken"' "$out"
}
