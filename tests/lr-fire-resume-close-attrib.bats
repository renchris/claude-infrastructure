#!/usr/bin/env bats
# lr-fire-resume.sh — a RESUMED session must be launched through bin/cc-close-attrib, so that when
# it dies the crash watchdog has a close-record to read.
#
# THE DEFECT. Every other launch path on this box interposes the wrapper (~/.zshrc's claude-next*
# launchers do it explicitly); this script's `spawn` did not, so a session recovered by limit-
# recovery could produce no close-record however it died. The watchdog's entire attribution ladder
# is built on that record: measured 2026-09-08, 151 of September's 151 `abrupt-unknown` crashes
# carry none, while every crash that carries one is attributed
# (docs/research/death-attribution-coverage-2026-09-08.md). Live census the same day: 20 running
# leads, 15 wrapped, 5 not — and all five unwrapped ones were spawns from this line.
#
# WHY THESE ARMS EXECUTE THE REAL EXPECT PROGRAM RATHER THAN GREPPING FOR THE WRAPPER'S NAME. A
# `grep cc-close-attrib` over the file would pass on a spawn that names the wrapper and never reaches
# it, and would say nothing about the thing actually in doubt — whether a bash wrapper that
# background-execs its child and juggles fds survives being the process expect(1) spawns on a pty.
# So the expect body is extracted verbatim from the subject and RUN, against a stub binary, with the
# real wrapper. The verdict is the close-record the wrapper writes: a file that exists only if the
# wrapper was interposed AND ran to completion under the pty.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIRE="$REPO/scripts/limit-recover/lr-fire-resume.sh"
  WRAP="$REPO/bin/cc-close-attrib"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_CLOSE_RECORDS_DIR="$BATS_TEST_TMPDIR/close-records"
  # The subject reaches scripts/lib/capacity-admit.sh, whose gate reads live load, memory headroom
  # and a `ps` session census — so an unpinned suite goes red because the BOX is busy, not because
  # its subject is wrong. Pinned off here; the gate is not this suite's subject.
  export CC_ADMIT_GATE=off

  command -v expect >/dev/null || skip "expect(1) not installed"

  # The expect program, verbatim between `expect -c '` and its closing quote.
  EXP="$BATS_TEST_TMPDIR/resume.exp"
  # The end anchor is `^' ||`, not a bare `^'`: the subject no longer EXECs expect (it captures the
  # rc and falls through to a login shell so the pane outlives the session), so its closing quote
  # line is now `' || lr_rc=$?`. A range whose START never matches emits NOTHING, so a stale anchor
  # here fails LOUD on the `-s` check below rather than silently extracting the wrong span.
  sed -n "/^expect -c '\$/,/^' ||/p" "$FIRE" | sed '1d;$d' > "$EXP"
  [ -s "$EXP" ] || { echo "extraction of the expect body from $FIRE failed" >&2; return 1; }
  grep -q 'spawn -noecho env' "$EXP"      # extraction sanity only — the arms below do the work

  # The stub stands in for the claude binary: it early-exits on the wrapper's cached --version probe,
  # writes one marker to each stream, and exits 7 so the status has to travel the whole chain.
  STUB="$BATS_TEST_TMPDIR/stub"
  cat > "$STUB" <<'SH'
#!/bin/bash
[[ "$1" == "--version" ]] && { echo "stub 9.9.9"; exit 0; }
printf '%s\n' "$@" > "$LR_TEST_ARGV"
echo "STUB-STDOUT-MARKER"
echo "STUB-STDERR-MARKER" >&2
exit 7
SH
  chmod +x "$STUB"
  export LR_TEST_ARGV="$BATS_TEST_TMPDIR/argv"

  # Everything the program reads. The menu patterns are pinned to a string the stub never prints, so
  # no arm fires and the run ends on the program's own `eof { exit }` — `interact` is never reached.
  export LR_CFG="$BATS_TEST_TMPDIR/cfg" LR_BIN="$STUB" LR_MODEL="m" LR_EFFORT="high" \
         LR_SID="00000000-0000-0000-0000-000000000000" LR_PROMPT="" LR_ASIS=1
  local never='ZZZ-NEVER-MATCHES-ZZZ'
  export LR_RE_MENU="$never" LR_RE_ASIS_STRONG="$never" LR_RE_ASIS="$never" \
         LR_RE_TRUST="$never" LR_RE_TRUST_RB="$never" LR_RE_FS="$never" LR_RE_FS_RB="$never" \
         LR_RE_OVERAGE="$never" LR_RE_READY="$never"
}

# shellcheck disable=SC2012  # our own fixed pattern in a sandboxed dir (as cc-close-attrib.bats)
rec() { ls -1t "$CC_CLOSE_RECORDS_DIR"/*.json 2>/dev/null | head -1; }

@test "a resumed session is spawned THROUGH cc-close-attrib and leaves a close-record" {
  export LR_WRAP="$WRAP"
  run expect -f "$EXP"
  [ "$status" -eq 0 ]                                  # the program exits on eof, not on the stub's rc
  # the stub really ran, and received the resume argv the subject builds
  grep -qx -- "--resume" "$LR_TEST_ARGV"
  grep -qx -- "00000000-0000-0000-0000-000000000000" "$LR_TEST_ARGV"
  # THE VERDICT: a close-record exists, closed, carrying the stub's real exit status. Only an
  # interposed wrapper that survived the pty spawn and reached its exit path can produce this.
  local r; r="$(rec)"
  [ -n "$r" ]
  grep -q '"exit_code":7' "$r"
  grep -q '"record_state":"closed"' "$r"
}

@test "an unresolvable wrapper costs the RECORD, never the RECOVERY" {
  # The fail-open half, and the control for the arm above: with LR_WRAP empty the else-branch spawns
  # the binary directly — the session still comes back, and no record is written. This is the
  # pre-fix behaviour, pinned deliberately: on the limit-recovery path a session that does not
  # return is strictly worse than one that returns unattributed.
  export LR_WRAP=""
  run expect -f "$EXP"
  [ "$status" -eq 0 ]
  grep -qx -- "--resume" "$LR_TEST_ARGV"               # the recovery still happened
  # shellcheck disable=SC2012
  [ -z "$(ls -1 "$CC_CLOSE_RECORDS_DIR"/*.json 2>/dev/null || true)" ]
}

@test "the wrapper does not swallow the child's stderr on the pty" {
  # The wrapper routes fd2 through a FIFO and a tee. Under a pty that is the same descriptor as
  # stdout, so a mistake here would either lose the stream or deadlock the spawn — and every menu
  # pattern in this program is matched against what reaches the pty.
  export LR_WRAP="$WRAP"
  run expect -f "$EXP"
  [ "$status" -eq 0 ]
  [[ "$output" == *STUB-STDOUT-MARKER* ]] || false
  [[ "$output" == *STUB-STDERR-MARKER* ]]
}
