#!/usr/bin/env bats
# renderer-film — guards on the filming instruments (assets/demo/renderer-film.sh,
# tools/terminal-bench/window-rect.swift, tools/terminal-bench/window-film.swift).
#
# WHY THESE SPECIFIC TESTS. Every one of them pins a failure that actually happened while building
# these files, and all but one were SILENT:
#   · The screen-lock probe was written as `ioreg | grep -q`, which under this script's `pipefail`
#     returns the SIGPIPEd producer's 141 — so it read "unlocked" exactly when the screen WAS
#     locked, and three takes ran against a machine that draws nothing.
#   · A capture returned 3 frames over 21 s and passed every check that existed: the file was
#     genuinely 1920x1080, genuinely 60/1, and 0.12 seconds long.
#   · window-film crashed in `markAsFinished` when no frames were written, instead of reporting it.
#   · window-rect matched "the first window of that app" would have filmed a LIVE agent session —
#     this box had three windows titled "Claude Code" open at the time.
# The instrument's whole value is that its output gets believed, so absence and failure must be
# loud, and each guard below has a control that can fail.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FILM="$REPO/assets/demo/renderer-film.sh"
  RECT="$REPO/tools/terminal-bench/window-rect.swift"
  FILM_SWIFT="$REPO/tools/terminal-bench/window-film.swift"

  # Own TMPDIR: renderer-film.sh caches its compiled binary under $TMPDIR, and the stub below is how
  # these tests stay fast (a real swiftc run costs seconds) and hermetic.
  export TMPDIR="$BATS_TEST_TMPDIR/tmp/"; mkdir -p "$TMPDIR"

  BIN="$TMPDIR/window-film-$(date -u +%Y%m%d)"
  printf '#!/bin/sh\necho "verdict=ERROR reason=stub"\n' > "$BIN"
  chmod +x "$BIN"
  # Must be NEWER than the source or the script rebuilds it and the stub is bypassed.
  touch "$BIN"

  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"

  # 🚨 EVERY invocation below passes --out into this directory, and that is not tidiness. The
  # harness defaults --out to the REPO's assets/demo, so while RED-proving the lock guard — with the
  # guard deliberately broken — a test spawned a real 2-pane kitty window and wrote a measurement
  # row into the working tree. A suite must stay hermetic against the code under test being WRONG,
  # which is the only state it is ever run in on purpose.
  mkdir -p "$BATS_TEST_TMPDIR/out"
}

# Stub ioreg so the lock state is a test INPUT rather than whatever the machine happens to be doing.
# Everything else must still resolve normally, so the stub falls through to the real ioreg for any
# other query.
#
# 🚨 THE FILLER IS LOAD-BEARING, NOT PADDING. The first version of this stub echoed ONE line and
# exited — and the locked-screen test then passed against the KNOWN-BROKEN `ioreg | grep -q` probe,
# because a producer that has already finished writing never receives SIGPIPE. The defect being
# pinned only exists when the producer is still writing after grep -q exits, which is what the real
# ioreg (tens of KB) does and a one-line stub does not. So the stub emits the key line FIRST and
# then keeps writing: grep -q matches immediately, the rest of the write hits a closed pipe, the
# stub dies of SIGPIPE, and `pipefail` promotes its 141 — reproducing the inversion exactly.
# A fixture that cannot fail the way production fails is not a control.
stub_ioreg() {
  cat > "$STUBS/ioreg" <<EOF
#!/bin/sh
echo '"IOConsoleUsers" = ({"kCGSSessionOnConsoleKey"=Yes,"CGSSessionScreenIsLocked"=$1})'
i=0
while [ \$i -lt 20000 ]; do
  echo '  "IOSomeOtherKey" = {"padding"="the real ioreg emits tens of KB after this key"}'
  i=\$(( i + 1 ))
done
EOF
  chmod +x "$STUBS/ioreg"
  export PATH="$STUBS:$PATH"
}

# ── the screen lock: a refusal, not a retry ───────────────────────────────────────────────────────

@test "film: a locked screen is REFUSED before anything is spawned" {
  # THE BUG THIS PINS, and it is not the obvious one. The check itself was always correct; the
  # PLUMBING inverted it. `ioreg -n Root -d1 | grep -q 'CGSSessionScreenIsLocked"=Yes'` under
  # `set -o pipefail` reports 141 — grep -q exits on the first match, ioreg dies of SIGPIPE, and
  # pipefail promotes the producer's status — so the probe read FALSE on a MATCH. Verified by hand
  # in a shell WITHOUT pipefail, where it read true, which is what made it look correct.
  stub_ioreg Yes
  run "$FILM" --app kitty --panes 2 --seconds 2 --out "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 9 ]
  [[ "$output" == *"verdict=LOCKED"* ]]
  # It must refuse BEFORE creating panes: 18 repainting panes on a machine that cannot draw them is
  # pure load on a shared box, and the refusal would arrive 60 s later wearing a renderer's face.
  [[ "$output" != *"spawned"* ]]
}

@test "film: an UNlocked screen is not refused — the control that can fail" {
  # Without this, a screen_locked() that returned true unconditionally would pass the test above and
  # nothing would ever film again. The unknown app makes it exit early with a different code.
  stub_ioreg No
  run "$FILM" --app NoSuchTerminal9731 --panes 2 --seconds 2 --out "$BATS_TEST_TMPDIR/out"
  [[ "$output" != *"verdict=LOCKED"* ]]
  [ "$status" -eq 2 ]
}

# ── the load circuit breaker ──────────────────────────────────────────────────────────────────────

@test "film: refuses to add 18 repainting panes to an already-loaded box" {
  stub_ioreg No
  FILM_MAXLOAD=0 run "$FILM" --app kitty --panes 18 --seconds 2 --out "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 4 ]
  [[ "$output" == *"verdict=REFUSED"* ]]
  [[ "$output" != *"spawned"* ]]
}

# ── window-rect: absence is loud, and a miss NEVER falls back ─────────────────────────────────────

@test "rect: an app with no windows is NO-MATCH and exit 4, never a silent pick" {
  run swift "$RECT" --owner NoSuchApplication4471
  [ "$status" -eq 4 ]
  [[ "$output" == *"verdict=NO-MATCH"* ]]
}

@test "rect: a title that matches nothing REFUSES rather than returning some other window" {
  # 🚨 THE SAFETY PROPERTY. This box runs the operator's live Claude Code fleet in the very apps
  # under test — a census during development found THREE live kitty windows titled "Claude Code".
  # A "no title match, so use the first window of that app" fallback would point the camera at a
  # live agent session. The refusal is what makes that impossible.
  #
  # Asserted against a REAL owner that is running (this suite runs from a terminal), so the miss is
  # attributable to the title and not to the app being absent.
  run swift "$RECT" --owner kitty --title ZZ_NO_SUCH_TITLE_4471_ZZ
  [ "$status" -eq 4 ]
  [[ "$output" == *"verdict=NO-MATCH"* ]]
  # The diagnostic must distinguish "app not running" from "title matched nothing" — they need
  # opposite fixes, and a bare NO-MATCH sends the reader to the wrong one.
  [[ "$output" == *"owner_windows="* ]]
}

@test "rect: --owner is required and a bad flag is rejected, not ignored" {
  run swift "$RECT" --title CCFILM60
  [ "$status" -eq 2 ]
  run swift "$RECT" --owner kitty --nonsense-flag
  [ "$status" -eq 2 ]
}

# ── window-film: a missing window is reported, not crashed on ─────────────────────────────────────

@test "film-swift: a window id that does not exist reports NO-WINDOW instead of aborting" {
  # THE BUG THIS PINS. With no frames written, AVAssetWriterInput.markAsFinished() throws an ObjC
  # exception ("Cannot call method when status is 0") that Swift cannot catch, so the process died
  # with a stack trace and no verdict line — the worst possible failure for output that is parsed.
  # Compiling here is deliberate: `swift window-film.swift` ABORTS inside swift-frontend
  # (SLSGetActiveDisplayList), so the interpreted path could never have caught this.
  command -v swiftc >/dev/null || skip "swiftc unavailable"
  local bin="$BATS_TEST_TMPDIR/window-film"
  swiftc -O "$FILM_SWIFT" -o "$bin" 2>/dev/null || skip "swiftc failed in this environment"
  run "$bin" --window-id 999999999 --seconds 1 --out "$BATS_TEST_TMPDIR/never.mov"
  [ "$status" -eq 4 ]
  [[ "$output" == *"verdict=NO-WINDOW"* ]]
  [ ! -f "$BATS_TEST_TMPDIR/never.mov" ]
}

@test "film-swift: required args are enforced" {
  command -v swiftc >/dev/null || skip "swiftc unavailable"
  local bin="$BATS_TEST_TMPDIR/window-film2"
  swiftc -O "$FILM_SWIFT" -o "$bin" 2>/dev/null || skip "swiftc failed in this environment"
  run "$bin" --seconds 1
  [ "$status" -eq 2 ]
}

# ── argument handling ─────────────────────────────────────────────────────────────────────────────

@test "film: an unknown app is rejected rather than filmed as something else" {
  stub_ioreg No
  run "$FILM" --app definitely-not-a-terminal --out "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 2 ]
}

@test "film: --app is required" {
  run "$FILM"
  [ "$status" -eq 2 ]
}
