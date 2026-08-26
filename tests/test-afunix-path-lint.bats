#!/usr/bin/env bats
# test-afunix-path-lint — the RATCHET that stops a fixture binding an AF_UNIX socket by ABSOLUTE path.
#
# The failure it exists for (2026-08-08 07:44 → 2026-08-09 22:39): tests/boot-resume-launch.bats
# bound "$BATS_TEST_TMPDIR/sock/kitty-42". Darwin caps sun_path at 104 bytes against the string
# handed to bind(2), and inside postland-verify that prefix is launchd's 49-byte /var/folders/… plus
# postland-run.XXXXXX plus the test's own (long) NAME — so bind raised "AF_UNIX path too long". The
# suite was in 17 of 17 postland reds, no GREEN stamp existed for 40h, deploy-live refused every
# sweep, and nothing that landed on trunk reached the live ~/.claude layer.
#
# WHAT MAKES THIS CLASS SPECIAL IS THE POLARITY, and it is why a grep-lint is the right instrument:
# the suite is green in every hand-check, and green under the re-run command postland ITSELF prints
# (a short /tmp/pv-repro). The operator's own repro exonerates the file. Nobody was going to find
# this by re-running it.
#
# Three properties are proved here: the 104-byte cap and the prescribed fix are REAL (an end-to-end
# bind, not a grep — that control cannot decay as the lint's implementation changes); the lint
# DISCRIMINATES on both real shapes and on the half-fix; and it is GREEN on the tree as it stands —
# a lint that ships standing-red is rot, and the nightly runs every scripts/*lint*.sh.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/test-afunix-path-lint.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"    # dogfood: this suite obeys the sibling rule
  # …and the other half of that rule: scripts/test-hermeticity-lint.sh requires any suite reaching
  # the fire path to pin this, so its fires cannot read live machine load. Caught by that ratchet on
  # first run here — which is the sibling lints working exactly as this one is meant to.
  export CC_FIRE_CAPACITY_GATE=off
  FIX="$BATS_TEST_TMPDIR/fix"; mkdir -p "$FIX"
  # THE VIOLATING SHAPE IS ASSEMBLED, NEVER WRITTEN AS A LITERAL — the same discipline
  # tests/test-walltime-lint.bats applies to its future dates, and for the same reason: a literal
  # here would make this very suite violate its own rule, and the only ways out are a self-exemption
  # in the ratchet (which is how a ratchet rots into an exemption list) or a lint that cannot see its
  # own corpus. Verified both directions — inline the literal and the whole-tree scan goes red.
  # (memory: guard-refusal-fires-on-its-own-harness — scope to the dangerous EFFECT, not the file.)
  BND='.bind'
  ABS_ONELINE="mksock() { python3 -c \"import socket,sys; socket.socket(socket.AF_UNIX)${BND}(sys.argv[1])\" \"\$1\"; }"
  SAFE_ONELINE='mksock() { /usr/bin/python3 -c "import os,socket,sys; d,b=os.path.split(os.path.abspath(sys.argv[1])); os.chdir(d); socket.socket(socket.AF_UNIX).bind(b)" "$1"; }'
}

mk() {  # $1=dir  $2=file body (verbatim)
  mkdir -p "$FIX/$1"
  printf '#!/usr/bin/env bats\n%s\n@test "x" { true; }\n' "$2" > "$FIX/$1/zz-fixture.bats"
}

# ── THE INVARIANT ITSELF, measured — not the lint's opinion of it ─────────────────────────────────
# Everything else in this file greps text. This one proves the PHYSICS the lint encodes: at a path
# over the cap the absolute bind raises and the prescribed fix does not. If Darwin ever changed the
# cap, or the "fix" stopped working, this test would say so and every grep assertion below would
# keep passing — which is exactly why it is here (memory: control-calibrated-to-implementation-decays;
# keyed on the MECHANISM, so a longer path only makes it stronger).
@test "PHYSICS: over 104 bytes the absolute bind RAISES and chdir+basename SUCCEEDS" {
  local pad d
  pad="$(printf 'p%.0s' $(seq 1 60))"                  # push the dir comfortably past the cap
  d="$BATS_TEST_TMPDIR/$pad/$pad/sock"; mkdir -p "$d"
  [ "${#d}" -gt 104 ] || { echo "fixture path is only ${#d} bytes — below the cap, the control is vacuous"; false; }

  # the pre-fix shape MUST fail, and fail for the documented reason
  run /usr/bin/python3 -c "import socket,sys; socket.socket(socket.AF_UNIX)${BND}(sys.argv[1])" "$d/kitty-42"
  [ "$status" -ne 0 ] || { echo "an absolute bind at ${#d} bytes SUCCEEDED — the cap is not what this lint claims"; false; }
  echo "$output" | grep -q 'too long' || false

  # the prescribed fix MUST succeed, and land the socket at that same absolute path
  run /usr/bin/python3 -c "import os,socket,sys; d,b=os.path.split(os.path.abspath(sys.argv[1])); os.chdir(d); socket.socket(socket.AF_UNIX)${BND}(b)" "$d/kitty-42"
  [ "$status" -eq 0 ] || false
  [ -S "$d/kitty-42" ] || false
}

@test "the real tree is CLEAN — the embedded ratchet matches HEAD, nightly stays green" {
  run bash "$LINT"
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q 'test-afunix-path-lint: clean' || false
}

@test "--selftest is GREEN and every discriminating case is exercised" {
  run bash "$LINT" --selftest
  [ "$status" -eq 0 ] || false
}

# The regression that motivated the lint, reproduced with the shape that was ACTUALLY on trunk.
@test "RED: the one-liner shape that reddened trunk for 40h" {
  mk abs "$ABS_ONELINE"
  CC_AFUNIX_ALLOWLIST="" run bash "$LINT" "$FIX/abs"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'ABS-BIND' || false
}

# The second real shape: AF_UNIX and the bind are on DIFFERENT lines (tests/cc-kitty-socket.bats).
# A single-line rule would have missed it, and missing it is how the class survived a fix.
@test "RED: the heredoc shape, where AF_UNIX sits on an earlier line" {
  mk het "mksock() {
  python3 - \"\$1\" <<PYEOF
import socket, sys
s = socket.socket(socket.AF_UNIX)
s${BND}(sys.argv[1])
PYEOF
}"
  CC_AFUNIX_ALLOWLIST="" run bash "$LINT" "$FIX/het"
  [ "$status" -eq 1 ] || false
}

# Half the fix is not the fix: chdir does nothing if the argument handed to bind is still absolute.
@test "RED: chdir present but the bind argument is STILL absolute" {
  mk half "mksock() { python3 -c \"import os,socket,sys; os.chdir(os.path.dirname(sys.argv[1])); socket.socket(socket.AF_UNIX)${BND}(sys.argv[1])\" \"\$1\"; }"
  CC_AFUNIX_ALLOWLIST="" run bash "$LINT" "$FIX/half"
  [ "$status" -eq 1 ] || false
}

@test "GREEN: chdir + basename is the prescribed fix and passes" {
  mk ok "$SAFE_ONELINE"
  CC_AFUNIX_ALLOWLIST="" run bash "$LINT" "$FIX/ok"
  [ "$status" -eq 0 ] || false
}

# AF_INET has no path and therefore no cap. tests/cc-authbrowser.bats binds ("127.0.0.1", port) and
# must stay legal — a lint that flagged it would be refactoring working code for no safety gain.
@test "GREEN: an AF_INET bind is out of scope by construction" {
  mk inet 'mkport() { python3 -c "import socket,sys; s=socket.socket(); s.bind((\"127.0.0.1\", int(sys.argv[1])))" "$1"; }'
  CC_AFUNIX_ALLOWLIST="" run bash "$LINT" "$FIX/inet"
  [ "$status" -eq 0 ] || false
}

# Four files in this repo now EXPLAIN this defect at length. Flagging prose would train people to
# ignore the lint — and would red the very comments that document the fix.
@test "GREEN: the defect described in PROSE is not a fixture" {
  mkdir -p "$FIX/prose"
  # The fixture must carry the REAL token, or this case passes vacuously — it would be asserting
  # that a comment containing something-other-than-the-defect is clean, which nothing doubted.
  printf '#!/usr/bin/env bats\n# AF_UNIX %s( an absolute path ) is the 104-byte defect — see e1d43f93da19\nsetup() { true; }\n@test "x" { true; }\n' "$BND" > "$FIX/prose/zz-fixture.bats"
  grep -qF "AF_UNIX ${BND}(" "$FIX/prose/zz-fixture.bats" || { echo "the prose fixture lost the real token — this case would pass vacuously"; false; }
  CC_AFUNIX_ALLOWLIST="" run bash "$LINT" "$FIX/prose"
  [ "$status" -eq 0 ] || false
}

@test "the window is load-bearing: narrow it and the multi-line shape goes invisible" {
  mk het "mksock() {
  python3 - \"\$1\" <<PYEOF
import socket, sys
s = socket.socket(socket.AF_UNIX)
s${BND}(sys.argv[1])
PYEOF
}"
  CC_AFUNIX_ALLOWLIST="" CC_AFUNIX_WINDOW=1 run bash "$LINT" "$FIX/het"
  [ "$status" -eq 0 ] || false
}

@test "the ratchet only shrinks: a fixed-but-still-grandfathered suite is RED" {
  mk ok "$SAFE_ONELINE"
  CC_AFUNIX_ALLOWLIST="zz-fixture.bats" run bash "$LINT" "$FIX/ok"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'RATCHET' || false
}

# Own-scope, built in from day one so this lint never becomes a fleet-wide hard stop (a lander
# refused over a suite it never touched). Same three states as its two siblings.
@test "own-scope: a violation OUTSIDE the lander's diff is advisory; INSIDE it blocks" {
  mk abs "$ABS_ONELINE"
  CC_AFUNIX_ALLOWLIST="" CC_AFUNIX_OWN="tests/other.bats" run bash "$LINT" "$FIX/abs"
  [ "$status" -eq 0 ] || false
  CC_AFUNIX_ALLOWLIST="" CC_AFUNIX_OWN="tests/zz-fixture.bats" run bash "$LINT" "$FIX/abs"
  [ "$status" -eq 1 ] || false
}

@test "own-scope: set-but-EMPTY (a docs-only land) passes; UNSET stays strict" {
  mk abs "$ABS_ONELINE"
  CC_AFUNIX_ALLOWLIST="" CC_AFUNIX_OWN="" run bash "$LINT" "$FIX/abs"
  [ "$status" -eq 0 ] || false
  CC_AFUNIX_ALLOWLIST="" run env -u CC_AFUNIX_OWN bash "$LINT" "$FIX/abs"
  [ "$status" -eq 1 ] || false
}

@test "LOUD: an unusable scan dir exits 2, never a silent green" {
  run bash "$LINT" "$FIX/nope"
  [ "$status" -eq 2 ] || false
}

@test "ship-land runs it, own-scoped, with a kill switch" {
  # Anchored on the own_run ROUTING, not on the assignment spelling — see the note in
  # tests/test-hermeticity-lint.bats. `CC_AFUNIX_OWN=` was true until the P2 own-scope work made
  # own_run() the single reader of the kill switch and the variable name an ARGUMENT.
  grep -q 'own_run AFUNIX CC_AFUNIX_OWN' "$REPO/scripts/ship-land.sh" || false
  grep -q 'SHIP_LAND_AFUNIX_OWN_SCOPE' "$REPO/scripts/ship-land.sh" || false
  grep -q 'test-afunix-path-lint.sh' "$REPO/scripts/ship-land.sh" || false
}

# postland-verify is the ONLY place this class is observable, so a lint absent from its prelints
# would leave the 40h red able to recur exactly where it already happened.
@test "postland-verify runs it as a prelint" {
  grep -q 'test-afunix-path-lint.sh' "$REPO/scripts/postland-verify.sh" || false
}

@test "the nightly picks it up automatically (name matches *lint*.sh AND supports --selftest)" {
  case "$(basename "$LINT")" in *lint*.sh) ;; *) false ;; esac
  grep -q -- '--selftest' "$LINT" || false
}

# The four files the class actually lived in. Named, so a future refactor that reintroduces the bug
# in any of them fails HERE with the history attached, not just in the anonymous whole-tree scan.
#
# THE LOOP VARIABLE HAS TO REACH THE SUBJECT, and until 2026-08-26 it did not. This arm used to run
# `bash "$LINT" "$REPO/tests"` — the SAME whole-tree scan — once per iteration, with $f appearing
# only in an existence check and in the failure message. Three things followed, and the third is the
# one that costs a future reader an afternoon:
#   · it had ZERO attribution power. Measured by planting the violating shape in the FOURTH named
#     site: the lint itself printed "handoff-fire-kitty-daemon.bats", and this arm discarded that and
#     reported "whole-tree scan is red while checking boot-resume-launch" — the FIRST site, which was
#     clean. A red always names site one, whichever site caused it.
#   · it was a byte-for-byte repeat of "the real tree is CLEAN" above, four times over. Its
#     CC_AFUNIX_ALLOWLIST="" looks like a stricter setting but EMBEDDED_ALLOWLIST is already the
#     empty string, so it selected exactly the same scan.
#   · and a title naming a number is a completeness claim that nothing checked (memory:
#     assertion-span-must-equal-its-subject; per-site-mutation-attributes-coverage — a green sweep
#     over one whole-tree scan credits no site at all).
# Scanning each site ALONE fixes all three at once: lint_dir takes a directory and enumerates
# "$dir"/*.bats, so a one-file directory is the smallest scope it can be asked about, the verdict is
# then genuinely per-site, and the message can only name the file that was scanned.
@test "each of the four known sites is clean, scanned IN ISOLATION so a red names the site" {
  local f d
  for f in boot-resume-launch cc-kitty-socket kitty-socket-address handoff-fire-kitty-daemon; do
    [ -f "$REPO/tests/$f.bats" ] || { echo "missing suite: $f.bats" >&2; return 1; }
    d="$BATS_TEST_TMPDIR/site-$f"
    mkdir -p "$d"
    cp "$REPO/tests/$f.bats" "$d/$f.bats"
    CC_AFUNIX_ALLOWLIST="" run bash "$LINT" "$d"
    [ "$status" -eq 0 ] || { echo "$f.bats binds an AF_UNIX socket by absolute path — the lint said: $output" >&2; return 1; }
  done
}

@test "INSTRUMENT CONTROL: an isolated per-site scan can go RED, and it names THAT site" {
  # Without this, the arm above passes just as happily against a lint_dir that had stopped reading
  # its input — an isolated directory is exactly the fixture a broken extractor would find empty
  # (memory: probe-that-acts-on-absence-must-confirm-presence). Both halves are here, over the SAME
  # copied file, so the red is attributable to the plant and to nothing else.
  local d="$BATS_TEST_TMPDIR/ctl-red" e="$BATS_TEST_TMPDIR/ctl-green" n=0
  mkdir -p "$d" "$e"
  cp "$REPO/tests/handoff-fire-kitty-daemon.bats" "$d/handoff-fire-kitty-daemon.bats"
  cp "$REPO/tests/handoff-fire-kitty-daemon.bats" "$e/handoff-fire-kitty-daemon.bats"
  # assembled, never a literal — a literal here would make this suite violate its own rule
  printf '%s\n' "$ABS_ONELINE" >> "$d/handoff-fire-kitty-daemon.bats"

  CC_AFUNIX_ALLOWLIST="" run bash "$LINT" "$d"
  [ "$status" -ne 0 ] || { echo "the isolated scan stayed GREEN on a planted absolute bind — it cannot discriminate" >&2; return 1; }
  n="$(printf '%s\n' "$output" | /usr/bin/grep -c 'handoff-fire-kitty-daemon.bats')"
  [ "$n" -ge 1 ] || { echo "the isolated scan went red without naming the site: $output" >&2; return 1; }

  CC_AFUNIX_ALLOWLIST="" run bash "$LINT" "$e"
  [ "$status" -eq 0 ] || { echo "the UNPLANTED copy is red too — the red above is not the plant: $output" >&2; return 1; }
}
