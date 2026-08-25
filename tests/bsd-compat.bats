#!/usr/bin/env bats
# bsd-compat — the BSD date(1)/stat(1) shims a dispatched Linux session uses to run this repo's
# macOS-authored corpus at all. See scripts/bsd-compat.sh for why the tool exists.
#
# WHAT THIS SUITE IS FOR, stated so it is not mistaken for redundancy with `--selftest`. The
# selftest proves the TRANSLATIONS against unshimmed answers and lives with the tool, so it runs
# anywhere including a container with no bats. This suite proves the two properties that are
# ABOUT THE TOOL rather than about date(1): that the guards refuse instead of approximating, and
# that the SHIMMED banner is unconditional. Those are the properties that decide whether a green
# run under the shim can be misread as a native macOS verdict — which is the failure this whole
# artifact was built to prevent, and the one a translation test cannot see.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SH="$REPO/scripts/bsd-compat.sh"
  SHIM="$REPO/scripts/lib/bsd-compat"
  # HERMETICITY (the repo's test-hermeticity ratchet): fixture $HOME before anything runs, so no
  # case can read or write the operator's live ~/. Nothing here consults $HOME, and that is
  # precisely why it must be pinned — a future edit that starts to would otherwise do it silently.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

# ── the tool's own controls, run as one case: a failure names the exact translation ───────────────

@test "--selftest passes: every translation matches an UNSHIMMED answer, every guard refuses" {
  run bash "$SH" --selftest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -qE 'selftest: [0-9]+/[0-9]+ OK' || false
  # A selftest that ran zero checks would print "0/0 OK" and pass. Assert it has real breadth.
  [ "$(echo "$output" | grep -c '^  ok ')" -ge 15 ]
}

# ── refusal, not approximation: each of these silently mistranslated is a fixture aged to `now` ──

@test "date REFUSES an unsigned adjustment — BSD SETS the field, it does not add" {
  # tests/cc-blockers.bats:1319 records this trap in its own words. A shim that read `-v 12H` as
  # "+12 hours" would age every fixture written that way in the wrong direction and stay silent.
  run "$SHIM/date" -v 12H +%H
  [ "$status" -eq 64 ]
  echo "$output" | grep -q 'SETS the field' || false
}

@test "date REFUSES an unknown unit rather than falling through to a plain date" {
  # The fall-through is the dangerous branch: a dropped adjustment returns `now`, so a fixture
  # aged -30H lands fresh and a staleness alarm reads GREEN for the reason it should read red.
  run "$SHIM/date" -v-3Q +%H
  [ "$status" -eq 64 ]
  echo "$output" | grep -q "unsupported unit" || false
}

@test "date REFUSES a non-numeric magnitude" {
  run "$SHIM/date" -v-xH +%H
  [ "$status" -eq 64 ]
  echo "$output" | grep -q 'non-numeric magnitude' || false
}

@test "stat REFUSES the formats with no exact GNU counterpart (%Sm, %Lp), never approximating" {
  # bin/cc-blockers:300 is `stat -f %m … || true` — an unreadable mtime is a DELIBERATE fail-open.
  # So a shim answering an unknown format with garbage drives every consumer down its abstain
  # branch and produces a board that is silent for a reason unrelated to the machine.
  local probe="$BATS_TEST_TMPDIR/probe"; printf 'x' > "$probe"
  run "$SHIM/stat" -f %Sm "$probe"
  [ "$status" -eq 64 ]
  run "$SHIM/stat" -f %Lp "$probe"
  [ "$status" -eq 64 ]
  echo "$output" | grep -q 'refusing rather than answering wrongly' || false
}

# ── the property that keeps a shimmed green from being read as a native one ───────────────────────

@test "the SHIMMED banner is UNCONDITIONAL and goes to stderr, not stdout" {
  # On stderr so it cannot corrupt a TAP stream or a parsed stdout, and unconditional because the
  # one moment it would be suppressed is the one where someone is scripting the tool and will
  # paste its output as evidence.
  local out err
  out="$BATS_TEST_TMPDIR/o"; err="$BATS_TEST_TMPDIR/e"
  bash "$SH" true > "$out" 2> "$err"
  grep -q 'SHIMMED over GNU userland' "$err" || false
  grep -q 'NOT a macOS run' "$err" || false
  [ ! -s "$out" ]
}

@test "the runner puts the shims FIRST on PATH and hands the command its own exit status" {
  run bash "$SH" bash -c 'command -v date'
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'lib/bsd-compat/date' || false

  run bash "$SH" bash -c 'exit 3'
  [ "$status" -eq 3 ]
}

@test "a command run through the runner actually gets BSD date -v (the end-to-end property)" {
  # The point of the whole tool: a macOS-authored line that dies on Linux must succeed under it.
  run bash -c 'date -v-30H +%Y >/dev/null 2>&1'
  [ "$status" -ne 0 ]                                   # RED CONTROL: bare Linux cannot do this
  run bash "$SH" bash -c 'date -v-30H +%Y'
  [ "$status" -eq 0 ]
}

@test "--print-path emits the shim dir and takes no banner (it is meant to be captured)" {
  local out; out="$(bash "$SH" --print-path 2>/dev/null)"
  [ -d "$out" ]
  [ -x "$out/date" ]
  [ -x "$out/stat" ]
}

@test "no argument is a USAGE error (64), never a silent success" {
  run bash "$SH"
  [ "$status" -eq 64 ]
}
