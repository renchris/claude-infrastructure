#!/usr/bin/env bats
# stub-stdin-drain — a test STUB must never read the runner's INHERITED stdin.
#
# WHY THIS EXISTS (2026-08-05). tests/handoff-fire-kitty.bats stubbed osascript with an
# unconditional `cat >/dev/null`. The intent was legitimate — osascript accepts a script ON STDIN
# (`osascript - "$1" <<'AS'`, handoff-fire.sh:708/785/4639) and a stub that does not consume it hands
# the caller a SIGPIPE. But the stub also answers the OTHER shape, `osascript -e '…'`
# (handoff-fire.sh:4189/4701/4708), where the script is in argv and the real binary never reads stdin
# at all. There the stub's `cat` reads whatever stdin the SUITE RUNNER was launched with — and waits
# for an EOF that never comes.
#
# THE POLARITY IS WHY IT SURVIVED, and it is the whole reason this file is behavioral and not a
# comment. A developer running the suite by hand gets a stdin that EOFs, so it is GREEN BY HAND. An
# automated runner — launchd, the nightly, any background harness — gets a pipe nobody closes, and
# the suite hangs FOREVER. A hung gate is indistinguishable from a slow one, so nothing alarms: the
# defect was found as two orphaned bats-exec-test processes at 11:46 and 37:07 elapsed, both wedged
# in .../test/129/bin/osascript, after a landing gate had failed to return a verdict for hours.
# Measured two-sided on the unfixed file: stdin=/dev/null → 34/34 green in <1s; stdin=an open pipe
# with a live writer → rc 124, stalled at suite-local test 22 (the first `-e` caller).
#
# WHAT IS PINNED, and why each half is load-bearing:
#   A. THE FIX — on an argv-script invocation the stub must return PROMPTLY even when stdin is an
#      open pipe nobody will ever close.
#   B. THE PROPERTY THE FIX MUST NOT BREAK — on a stdin-script invocation the stub must STILL drain,
#      or the caller takes SIGPIPE. A "fix" that just deletes the drain passes A and breaks B, so
#      testing A alone would license exactly the wrong remedy.
#   C. ANTI-VACUITY — a MUTANT of each real stub, rebuilt back to the historical unconditional drain,
#      must make probe A TIME OUT. Without C, a probe that silently stopped exercising the stub (a
#      broken extraction, a bound that no longer bounds) would report green forever. The mutation is
#      anchored and the anchor is asserted to match EXACTLY ONCE, so a stub that drifts out from
#      under this file fails here rather than quietly becoming untested.
#
# NOTHING HERE RUNS BATS. The stub bodies are EXTRACTED from the real suite files — the established
# pattern in this repo (tests/handoff-fire-it2-bound.bats:26 extracts functions from handoff-fire.sh
# the same way) — and executed directly. Extraction is GUARDED: an empty body is a vacuous pass,
# which is the failure mode this file exists to prevent.
#
# Every assertion is `[ ]`, `run`+status, or `… || false`. `[[ ]]` and `(( ))` are errexit-EXEMPT in
# bats and are silently DEAD anywhere but a body's last line — that has burned this repo twice.

setup() {
  # Rule 2 of test-hermeticity-lint: this file names handoff-fire suites, so it must pin the fire
  # capacity gate off even though it never fires anything — the lint keys on the reference, and an
  # un-pinned suite that ever DID reach a fire would read ambient machine load instead of its subject.
  export CC_FIRE_CAPACITY_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermeticity ratchet: never live ~/
  # The extracted stubs append their invocation log to $OLOG / $PLOG. Export both for EVERY row: an
  # unset one makes the stub's first line a redirect to "", which is a different failure than the one
  # under test and would muddy every verdict below.
  OLOG="$BATS_TEST_TMPDIR/o.log"; : > "$OLOG"; export OLOG
  PLOG="$BATS_TEST_TMPDIR/p.log"; : > "$PLOG"; export PLOG
}

# ── the table of real stubs under test ───────────────────────────────────────────────────────────
# Each row is "<suite file>|<the heredoc's redirect target, verbatim>|<the flag that means
# script-on-stdin>". Adding a stub is one row. Every row is exercised by A, B and C below.
stub_rows() {
  cat <<'ROWS'
tests/handoff-fire-kitty.bats|"$STUB/osascript"|-
tests/handoff-fire-kitty.bats|"$PYTHON_BIN"|-
tests/handoff-selfclose-terminal-pin-order.bats|"$STUB/osascript"|-
ROWS
}

# Pull one stub's heredoc BODY out of a suite file. Matched with awk's plain `index()`, never a
# regex, so the `$` and `"` in a redirect target need no escaping and cannot silently mis-anchor.
extract_stub() {   # $1=abs suite file  $2=redirect target verbatim
  awk -v anchor="$2" '
    !inb && index($0, anchor) && index($0, "<<\047FAKE\047") { inb = 1; next }
    inb && $0 == "FAKE" { exit }
    inb { print }
  ' "$1"
}

# Rebuild a stub body back to the PRE-FIX unconditional drain. Anchored on the conditional block this
# fix introduced; the caller asserts the anchor matched exactly once, so a drifted stub fails loudly
# instead of yielding a mutant identical to the original (which would make probe C vacuous).
mutate_to_historical() {   # stdin: fixed body → stdout: historical body
  awk '
    $0 == "for a in \"$@\"; do" { print "cat >/dev/null 2>&1 || true"; skip = 1; next }
    skip && $0 == "done"        { skip = 0; next }
    skip                        { next }
    { print }
  '
}

# Run a stub with an stdin that is OPEN and will never EOF — a FIFO held by a live writer that writes
# nothing. This is the automated-runner condition, reproduced exactly. Prints the exit code; 124 is
# timeout(1)'s "still running when the bound expired", i.e. the hang.
#
# THE BOUND IS AN ARGUMENT, AND THE TWO CALLERS PASS OPPOSITE VALUES ON PURPOSE. A's bound is only
# ever WAITED OUT on failure, so it is generous — a tight bound there would convict a merely-slow box
# (this corpus runs under a QoS utility clamp, on a machine that is often saturated) and produce a
# flaky RED. C's bound is PAID IN FULL on every green run, because a hanging mutant never returns, so
# it is short. Same probe, and the asymmetry is the whole reason it is cheap AND non-flaky.
rc_with_never_eof_stdin() {   # $1=bound seconds  $2=stub path; $3.. = argv
  local bound="$1" stub="$2"; shift 2
  local fifo w rc
  fifo="$(mktemp -u "$BATS_TEST_TMPDIR/fifo.XXXXXX")"   # trailing Xs only — BSD mktemp ignores others
  mkfifo "$fifo"
  # THE WRITER MUST HOLD THE FIFO AND NOTHING ELSE. Two properties, both learned the hard way here:
  #   · Its stdio is redirected away from the test's. bats reads a test's output pipe to EOF, so a
  #     background child that inherits it keeps the TEST alive for the child's whole lifetime — this
  #     file took 3m01s of pure wall-clock wait before the redirect, on ~1s of actual work. That is
  #     the same shape as the bug under test: a reader blocked on a pipe nobody closed.
  #   · The second `exec` REPLACES the subshell with sleep, so $! is the process that actually holds
  #     fd 9 and `kill` reaches it. Without it the sleep is a grandchild that survives the kill and
  #     goes on holding whatever it inherited.
  # The sleep is bounded just past the probe's own bound: long enough that stdin never EOFs while the
  # probe is running (an early EOF would let a BROKEN stub exit and read as a pass), short enough to
  # self-reap if this function is killed before its cleanup runs.
  ( exec 9>"$fifo"; exec sleep "$((bound + 3))" ) >/dev/null 2>&1 </dev/null &
  w=$!
  timeout "$bound" "$stub" "$@" <"$fifo" >/dev/null 2>&1
  rc=$?
  kill "$w" 2>/dev/null || true
  wait "$w" 2>/dev/null || true
  rm -f "$fifo"
  printf '%s' "$rc"
}

# Materialise one row's stub body at $BATS_TEST_TMPDIR/stub and echo nothing. Guards the extraction.
install_stub() {   # $1=suite file (repo-relative)  $2=redirect target  $3=variant(fixed|historical)
  local body
  body="$(extract_stub "$REPO/$1" "$2")"
  [ -n "$body" ]                                  # an empty extraction is a vacuous pass
  # …and a NON-empty extraction can still be the wrong block. A stub body always opens with a
  # shebang, so this is what separates "found the stub" from "found some other FAKE heredoc".
  printf '%s\n' "$body" | head -1 | grep -q '^#!' || false
  if [ "$3" = historical ]; then
    # The anchor must match EXACTLY ONCE. Zero matches ⇒ the stub drifted and the mutant would equal
    # the original (probe C passes for the wrong reason); more than one ⇒ the mutation is ambiguous.
    [ "$(printf '%s\n' "$body" | grep -cF 'for a in "$@"; do')" = "1" ]
    body="$(printf '%s\n' "$body" | mutate_to_historical)"
    printf '%s\n' "$body" | grep -qF 'cat >/dev/null 2>&1 || true' || false
    # Negative assertion as an `if`, never `… && false`: on the PASSING path (grep finds nothing) a
    # `&&` chain yields grep's non-zero status and errexit would fail the test for succeeding.
    if printf '%s\n' "$body" | grep -qF 'for a in "$@"; do'; then return 1; fi
  fi
  printf '%s\n' "$body" > "$BATS_TEST_TMPDIR/stub"
  chmod +x "$BATS_TEST_TMPDIR/stub"
}

# ── A. THE FIX ───────────────────────────────────────────────────────────────────────────────────

@test "A: every stub returns PROMPTLY on an argv-script call, with stdin an open pipe that never EOFs" {
  # The regression proper. Pre-fix every row here returned 124.
  while IFS='|' read -r file target _flag; do
    [ -n "$file" ] || continue
    install_stub "$file" "$target" fixed
    # `-e <script>` is the argv shape. Also passes a second arg, because a stub that only checked
    # "$1" would pass this while still hanging on `osascript -l JavaScript -e …`.
    [ "$(rc_with_never_eof_stdin 20 "$BATS_TEST_TMPDIR/stub" -e 'return "x"' extra)" = "0" ]
  done < <(stub_rows)
}

@test "A2: an argv-script call still LOGS and still ANSWERS — the stub was not merely silenced" {
  # A alone would pass if the fix had turned the stub into a no-op. Assert the stub's two real jobs
  # survive: it records the invocation its suite asserts on, and it prints its fixture answer.
  install_stub tests/handoff-fire-kitty.bats '"$STUB/osascript"' fixed
  export KFAKE_OSA_OUT="ABC-DEF"
  run "$BATS_TEST_TMPDIR/stub" -e 'tell application "x"'
  [ "$status" = "0" ]
  [ "$output" = "ABC-DEF" ]
  grep -qF 'osascript -e tell application "x"' "$OLOG" || false
}

# ── B. THE PROPERTY THE FIX MUST NOT BREAK ───────────────────────────────────────────────────────

@test "B: every stub STILL drains a script-on-stdin call — deleting the drain is not the fix" {
  # 256 KiB, comfortably past the 64 KiB pipe buffer, so the producer cannot complete unless the stub
  # actually reads. A stub that skipped the drain exits with the data unread, the producer's next
  # write hits a closed reader, and PIPESTATUS[0] comes back 141 (SIGPIPE) instead of 0.
  local big="$BATS_TEST_TMPDIR/big"
  dd if=/dev/zero bs=1024 count=256 2>/dev/null | tr '\0' 'x' > "$big"
  [ -s "$big" ]
  while IFS='|' read -r file target flag; do
    [ -n "$file" ] || continue
    install_stub "$file" "$target" fixed
    run bash -c "cat '$big' | timeout 5 '$BATS_TEST_TMPDIR/stub' '$flag' someid >/dev/null 2>&1; printf '%s' \"\${PIPESTATUS[0]}\""
    [ "$status" = "0" ]
    [ "$output" = "0" ]
  done < <(stub_rows)
}

# ── C. ANTI-VACUITY ──────────────────────────────────────────────────────────────────────────────

@test "C: the HISTORICAL unconditional drain still HANGS probe A — the probe is not blind" {
  # The positive control. If this test ever goes green-by-passing (rc 0 instead of 124), probe A has
  # stopped being able to detect the defect and every green above is worthless.
  while IFS='|' read -r file target _flag; do
    [ -n "$file" ] || continue
    install_stub "$file" "$target" historical
    [ "$(rc_with_never_eof_stdin 3 "$BATS_TEST_TMPDIR/stub" -e 'return "x"' extra)" = "124" ]
  done < <(stub_rows)
}

@test "C2: the mutant is a REAL mutant — it differs from the shipped stub on every row" {
  # Guards the anchor itself. If a stub is reworded so `mutate_to_historical` no longer bites, the
  # mutant would equal the original, C would pass for the wrong reason, and A would be unguarded.
  while IFS='|' read -r file target _flag; do
    [ -n "$file" ] || continue
    install_stub "$file" "$target" fixed
    cp "$BATS_TEST_TMPDIR/stub" "$BATS_TEST_TMPDIR/fixed"
    install_stub "$file" "$target" historical
    run diff -q "$BATS_TEST_TMPDIR/fixed" "$BATS_TEST_TMPDIR/stub"
    [ "$status" != "0" ]
  done < <(stub_rows)
}

# ── the table itself ─────────────────────────────────────────────────────────────────────────────

@test "the stub table is non-empty and every row names a file that exists" {
  # A silently-emptied table would make A, B and C all pass by iterating zero times.
  local n=0
  while IFS='|' read -r file target _flag; do
    [ -n "$file" ] || continue
    [ -f "$REPO/$file" ]
    [ -n "$(extract_stub "$REPO/$file" "$target")" ]
    n=$((n + 1))
  done < <(stub_rows)
  [ "$n" = "3" ]
}
