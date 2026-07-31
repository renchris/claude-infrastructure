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

@test "bench: --app is mandatory (exit 2), so a typo cannot silently measure nothing" {
  run bash "$BENCH" --interval 0
  [ "$status" -eq 2 ]
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

# ── tui-load: the rate it claims must be the rate it achieved ─────────────────────────────────────

@test "load: writes a 9-field stats row including strategy and flag" {
  run bash "$LOAD" --fps 10 --duration 1 --label unit --stats "$STATS"
  [ "$status" -eq 0 ]
  [ -s "$STATS" ]
  local fields; fields="$(awk -F'\t' '{print NF; exit}' "$STATS")"
  [ "$fields" -eq 9 ]
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
  [[ "$output" == *"verdict=OK"* ]]
}
