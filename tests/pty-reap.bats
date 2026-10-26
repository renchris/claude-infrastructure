#!/usr/bin/env bats
# tests/helpers/pty-reap.bash: no program a test spawned on a pty outlives the test (incident
# 2026-10-25, ~/incident-2026-10-25/RCA.md §1; lane-F hitlist, the lr-fire-resume expect row).
#
# The stub every arm spawns through expect is the hazard's shape: it ignores HUP, TERM and INT, so
# the hangup a closing master sends cannot end it, and it records its pid and its group. It opens no
# tty by path and nobody here does, so even a stub left on a dead pty has no opener to deadlock with.
# RED on 1bceb92c0 (no helper; the 8 files still run `timeout N expect` with no teardown); TAPs in the
# commit body. Arm 1c is the control: the shape the 8 files had leaves the stub alive.

load helpers/cc-stub
load helpers/pty-reap

FILES="lr-fire-resume-close-attrib lr-fire-resume-inject-atomic lr-fire-resume-no-token
  lr-fire-resume-noprompt lr-fire-resume-pane-ui lr-fire-resume-reply-drain lr-fire-resume-submit
  reso-resume-one"

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"; mkdir -p "$HOME"
  export T CC_ADMIT_GATE=off
  command -v expect >/dev/null || skip "expect(1) not installed"
  cc_stub "$T/stub" deaf '#!/bin/bash
trap "" HUP TERM INT
echo "$$" > "$T/deaf.pid"
( trap "" HUP TERM INT; while :; do /bin/sleep 1; done ) &
echo "$!" > "$T/deaf-member.pid"
while :; do /bin/sleep 1; done'
  # shellcheck disable=SC2016  # the Tcl program reads $env(...) itself
  EXPECT_PROG='set timeout -1; spawn -noecho $env(T)/stub/deaf; expect eof'
}

teardown() { pty_reap; }

alive() { kill -0 "$1" 2>/dev/null; }
gone() { ! kill -0 "$1" 2>/dev/null; }
wait_until() { local n=$(( $1 * 10 )); shift; until "$@"; do n=$((n - 1)); [ "$n" -gt 0 ] || return 1; /bin/sleep 0.1; done; }
pid_of() { cat "$T/$1.pid" 2>/dev/null; }

@test "1a: pty_timeout kills the spawn's group while expect holds the master, then returns 124" {
  run pty_timeout 3 expect -c "$EXPECT_PROG"
  [ "$status" -eq 124 ] || { echo "status $status: $output"; false; }
  l="$(pid_of deaf)"; m="$(pid_of deaf-member)"
  [ -n "$l" ] && [ -n "$m" ] || { echo "the stub never started"; false; }
  wait_until 5 gone "$l" || { echo "the spawned leader $l outlived pty_timeout"; false; }
  wait_until 5 gone "$m" || { echo "member $m of the spawn's group outlived pty_timeout"; false; }
}

@test "1b: pty_timeout passes a finished command's status and stdin through" {
  run pty_timeout 30 /bin/bash -c 'read -r x; echo "got $x"; exit 3' <<<"hello"
  [ "$status" -eq 3 ] || { echo "status $status: $output"; false; }
  [ "$output" = "got hello" ]
}

@test "1e: the command pty_timeout runs inherits no ignored INT or QUIT (an async command's default)" {
  run pty_timeout 120 /usr/bin/python3 -I -c '
import signal as s
print(" ".join("%s=%s" % (n, "IGN" if s.getsignal(getattr(s, "SIG" + n)) == s.SIG_IGN else "ok") for n in ("INT", "QUIT")))'
  [ "$status" -eq 0 ] || { echo "status $status: $output"; false; }
  [ "$output" = "INT=ok QUIT=ok" ] || { echo "$output"; false; }
}

@test "1c: CONTROL: timeout(1) around expect leaves the HUP-deaf spawn alive; pty_reap ends it, leader last" {
  command -v timeout >/dev/null || skip "no timeout(1) on PATH"
  # Not `run`: the surviving stub inherits expect's stdout, so a captured run never sees EOF and
  # hangs the suite (measured on the first draft of this arm: that hang IS the hazard). A file
  # instead, and bats' fd 3 closed, so the stub holds nothing bats waits on.
  rc=0; timeout 3 expect -c "$EXPECT_PROG" </dev/null >"$T/ctl.out" 2>&1 3>&- || rc=$?
  [ "$rc" -eq 124 ] || { echo "status $rc: $(cat "$T/ctl.out")"; false; }
  l="$(pid_of deaf)"; m="$(pid_of deaf-member)"
  [ -n "$l" ] && [ -n "$m" ] || { echo "the stub never started"; false; }
  /bin/sleep 1
  alive "$l" || { echo "the control did not reproduce: the stub died with expect"; false; }
  pty_reap
  wait_until 5 gone "$m" || { echo "member $m survived pty_reap"; false; }
  wait_until 5 gone "$l" || { echo "leader $l survived pty_reap"; false; }
}

@test "1d: pty_reap with an empty or relative BATS_TEST_TMPDIR selects nothing" {
  "$T/stub/deaf" </dev/null >/dev/null 2>&1 &
  wait_until 10 test -s "$T/deaf.pid" || { echo "the stub never started"; false; }
  l="$(pid_of deaf)"
  BATS_TEST_TMPDIR="" pty_reap
  BATS_TEST_TMPDIR="relative/dir" pty_reap
  alive "$l" || { echo "an empty selector killed $l"; false; }
  pty_reap
  wait_until 5 gone "$l" || { echo "pty_reap missed $l, in the test's own group"; false; }
}

@test "2: STRUCTURAL: each of the 8 expect files loads pty-reap, reaps in teardown, and runs no bare timeout(1) around expect" {
  local f bad=""
  for f in $FILES; do
    f="$REPO/tests/$f.bats"
    grep -q '^load helpers/pty-reap$' "$f" || bad="$bad\n$f: does not load helpers/pty-reap"
    awk '/^teardown\(\) *\{/{t=1} t&&/pty_reap/{found=1} t&&/^\}/{t=0} END{exit !found}' "$f" \
      || grep -qE '^teardown\(\) *\{.*pty_reap.*\}' "$f" || bad="$bad\n$f: teardown does not call pty_reap"
    # a literal bound or a variable one (lr_expect_run's "$bound" was the site a digits-only pattern missed)
    if grep -nE '(^|[^_[:alnum:]])timeout +("?\$\{?[A-Za-z_]+\}?"?|[0-9]+) +expect( |$)' "$f" | grep -vE '^[0-9]+:[[:space:]]*#'; then
      bad="$bad\n$f: timeout(1) around expect"
    fi
  done
  [ -z "$bad" ] || { printf '%b\n' "$bad"; false; }
}
