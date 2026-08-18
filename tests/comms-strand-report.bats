#!/usr/bin/env bats
# comms-strand-report.bats — the report is the CITATION for CROSS_SESSION_COMMS_V2.md §2, so its
# refusal path is the load-bearing behaviour under test, not its arithmetic.
#
# WHY: every box whose pane is absent from the live list counts as stranded, so a silently-broken
# liveness detector makes EVERY box read as dead and the script fabricates a catastrophe. That
# happened for real while measuring §2 (`it2 --list --json` — a verb that does not exist — returned
# empty with rc 0 and produced "0 live panes"). A non-verdict must never be reported as a zero.
#
# HERMETIC: $HOME fixtured. BATS ERREXIT: `|| false` on every non-final [[ ]]/(( ))/!/A&&B.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_MAILBOX_DIR="$HOME/.claude/mailbox"
  mkdir -p "$CC_MAILBOX_DIR" "$HOME/bin"
  RPT="$REPO/scripts/comms-strand-report.sh"
  # a dead-pane box holding one never-surfaced line
  printf '2026-07-29T10:00:00-0700 [peer] stranded\n' > "$CC_MAILBOX_DIR/DEAD1111-1111-2222-3333-444444444444.md"
  # neutralise the real oracle so each test installs its own stub
  export PATH="$HOME/bin:$PATH"
}

# Install a fake it2 whose `session list --json` prints $1 verbatim.
_stub_it2() {
  mkdir -p "$HOME/.claude/bin"
  { echo '#!/bin/bash'; printf 'cat <<"J"\n%s\nJ\n' "$1"; } > "$HOME/.claude/bin/it2"
  chmod +x "$HOME/.claude/bin/it2"
}

# Install a fake cc-sessions whose `--json` prints $1 verbatim (the second identity oracle).
_stub_sessions() {
  mkdir -p "$HOME/.claude/bin"
  { echo '#!/bin/bash'; printf 'cat <<"J"\n%s\nJ\n' "$1"; } > "$HOME/.claude/bin/cc-sessions"
  chmod +x "$HOME/.claude/bin/cc-sessions"
}

@test "REFUSES with verdict=unknown when the oracle emits nothing (the fabricated-zero bug)" {
  _stub_it2 ''
  run /bin/bash "$RPT" --json
  [ "$status" -eq 3 ]
  printf '%s' "$output" | grep -q '"verdict":"unknown"' || false
  # and it must NOT have claimed any strand number. `grep -c … || true` keeps this a LIVE final
  # `[ ]` comparison — a bare `grep -qv` here would exit 0 on any non-matching line and assert nothing.
  [ "$(printf '%s' "$output" | grep -c 'dead_never_surfaced' || true)" = "0" ]
}

@test "REFUSES when the oracle emits non-array garbage" {
  _stub_it2 'not json at all'
  run /bin/bash "$RPT" --json
  [ "$status" -eq 3 ]
  printf '%s' "$output" | grep -q '"verdict":"unknown"' || false
}

@test "REFUSES when the positive control FAILS — list readable but our own pane is absent" {
  # a readable, valid, non-empty list that simply does not describe this machine
  _stub_it2 '[{"id":"99999999-9999-9999-9999-999999999999"}]'
  export ITERM_SESSION_ID="w0t0p0:1234ABCD-1111-2222-3333-444444444444"
  run /bin/bash "$RPT" --json
  [ "$status" -eq 3 ]
  printf '%s' "$output" | grep -q 'control-failed' || false
}

# POSITIVE CONTROL for all three refusals above (memory absence-alarm-needs-evidence): the same
# fixtures with a list that DOES contain our pane must produce a real verdict. Without this, a script
# that refused unconditionally would pass every test above while being useless.
@test "positive control: our pane present in the list → verdict=ok and real numbers" {
  export ITERM_SESSION_ID="w0t0p0:1234ABCD-1111-2222-3333-444444444444"
  _stub_it2 '[{"id":"1234ABCD-1111-2222-3333-444444444444"}]'
  # The report now requires BOTH identity oracles (backlog 8370af320af5: pane ids alone counted every
  # session-uuid-keyed box dead, eight of them belonging to live sessions). This control's claim is
  # unchanged — ok, with real numbers — so it has to supply the second one. Stubbing it also keeps the
  # test hermetic: with only $HOME fixtured, resolution would otherwise fall through PATH to the
  # operator's real cc-sessions, which does not know this fixture's pane.
  _stub_sessions '[{"paneUUID":"1234ABCD-1111-2222-3333-444444444444","name":"fixture","session_id":"55556666-7777-8888-9999-aaaabbbbcccc"}]'
  run /bin/bash "$RPT" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"verdict":"ok"' || false
  printf '%s' "$output" | grep -q '"oracle":"controlled"' || false
}

@test "an EMPTY but valid array is a readable oracle, not an unknown one (when not in a pane)" {
  unset ITERM_SESSION_ID
  _stub_it2 '[]'
  _stub_sessions '[]'   # second identity oracle: readable, describes no session (8370af320af5)
  run /bin/bash "$RPT" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"oracle":"readable"' || false
}

@test "counts a dead-pane box's never-surfaced line, and keeps the three counts distinct" {
  unset ITERM_SESSION_ID
  _stub_it2 '[]'
  _stub_sessions '[]'   # second identity oracle: readable, describes no session (8370af320af5)
  run /bin/bash "$RPT" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"dead_boxes":1' || false
  printf '%s' "$output" | grep -q '"dead_total_lines":1' || false
  printf '%s' "$output" | grep -q '"dead_never_surfaced":1' || false
}

@test "a line already SURFACED is not counted as never-surfaced (the handed-down count's error)" {
  unset ITERM_SESSION_ID
  _stub_it2 '[]'
  _stub_sessions '[]'   # second identity oracle: readable, describes no session (8370af320af5)
  printf '1\n' > "$CC_MAILBOX_DIR/DEAD1111-1111-2222-3333-444444444444.seen"
  run /bin/bash "$RPT" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"dead_total_lines":1' || false      # total still 1
  printf '%s' "$output" | grep -q '"dead_never_surfaced":0' || false   # but loss is 0
}

@test "fixture-keyed boxes are excluded from the denominator" {
  unset ITERM_SESSION_ID
  _stub_it2 '[]'
  _stub_sessions '[]'   # second identity oracle: readable, describes no session (8370af320af5)
  printf 'x\n' > "$CC_MAILBOX_DIR/AAAAAAAA-1111-2222-3333-444444444444.md"
  run /bin/bash "$RPT" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"fixture_excluded":1' || false
  printf '%s' "$output" | grep -q '"boxes":1' || false
}

@test "forward coverage is reported in permille so 3.3% is not rounded to 3%" {
  unset ITERM_SESSION_ID
  _stub_it2 '[]'
  _stub_sessions '[]'   # second identity oracle: readable, describes no session (8370af320af5)
  printf 'BBBB1111-1111-2222-3333-444444444444\n' > "$CC_MAILBOX_DIR/DEAD1111-1111-2222-3333-444444444444.forward"
  run /bin/bash "$RPT" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"forward_coverage_permille":1000' || false
}
