#!/usr/bin/env bats
# ship-land.sh :: postland_net_live / postland_offbox_note — the post-land net's FRESHNESS SENSOR.
#
# WHY THIS FILE EXISTS SEPARATELY FROM tests/ship-land.bats. That suite drives the whole lander and
# is listed in scripts/offbox-excluded.manifest ("the land and verify machinery itself … excluding
# them from the off-box second opinion costs the least of anything here"), so it is proven ONLY by
# the on-box verifier — which is exactly the producer this sensor reports on. A sensor whose only
# coverage runs behind the thing it measures is untested precisely when its subject is broken: the
# starvation this discriminates is the same starvation that stops the on-box corpus from returning
# a verdict at all. This file carries no lander, no git, no launchd and no BSD-only date flag, so it
# lands INSIDE the hermetic partition by default and the sensor is re-proven hourly off-box.
#
# HOW IT TESTS THE SHIPPED TEXT AND NOT A COPY. Each case extracts the two functions out of
# scripts/ship-land.sh at run time with the repo's established idiom (`sed -n '/^fn() {/,/^}/p'`,
# tests/cc-reaper.bats:2218) and sources them into a bare bash. A hand-transcribed body would pass
# forever after the real one was edited.
#
# MTIME SEEDING IS PORTABLE, DELIBERATELY. tests/ship-land.bats seeds with `date -v -48H`, a BSD
# flag; this suite must also be green on the Linux and macOS runners the partition uses, so ages are
# stamped with python3 os.utime against a relative offset. Relative, never an absolute literal, for
# the reason that suite already records: a fixture pinned to a wall-clock constant changes meaning
# as the clock advances and has taken the fleet's gate down on a calendar boundary with no code
# change. python3 is a hard dependency of this repo (tests/python-deps.bats).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SHIPLAND="$REPO_ROOT/scripts/ship-land.sh"
  # Fixture HOME: both functions fall back to $HOME/.claude/autonomy/postland when POSTLAND_DIR is
  # unset, so an unfixtured HOME would let a case that forgets the export read the operator's real
  # store — and on this box that store IS the subject, so the miss would look like a pass.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export POSTLAND_DIR="$BATS_TEST_TMPDIR/postland"
  mkdir -p "$POSTLAND_DIR/stamps"
  FN="$BATS_TEST_TMPDIR/fn.sh"
  {
    sed -n '/^postland_mtime() {/,/^}/p'       "$SHIPLAND"
    sed -n '/^postland_offbox_note() {/,/^}/p' "$SHIPLAND"
    sed -n '/^postland_net_live() {/,/^}/p'    "$SHIPLAND"
  } > "$FN"
  # A silent extraction miss (a rename, a reflow) would make every case below vacuously green.
  grep -q '^postland_net_live() {'    "$FN"
  grep -q '^postland_offbox_note() {' "$FN"
  grep -q '^postland_mtime() {'       "$FN"
}

# age <file> <hours> — stamp <file>'s mtime <hours> in the past, portably.
age() {
  python3 - "$1" "$2" <<'PY'
import os, sys, time
p, h = sys.argv[1], float(sys.argv[2])
t = time.time() - h * 3600
os.utime(p, (t, t))
PY
}

# net — run the sensor over the fixture and print "<NET_STATE>\t<the warning, if any>".
net() {
  bash -c '
    set -uo pipefail
    . "$1"
    postland_net_live 2>"$2"
    printf "%s\n" "$NET_STATE"
  ' _ "$FN" "$BATS_TEST_TMPDIR/warn"
}
warned() { cat "$BATS_TEST_TMPDIR/warn" 2>/dev/null; }

green_stamp() { printf '{"head":"%s","verdict":"green"}\n' "$1" > "$POSTLAND_DIR/stamps/$1.json"; }
red_stamp()   { printf '{"head":"%s","verdict":"red"}\n'   "$1" > "$POSTLAND_DIR/stamps/$1.json"; }

# ── THE DISCRIMINATOR ────────────────────────────────────────────────────────────────────────────
# v2 keyed on GREEN stamps alone, so the two faults below were ONE value. They have opposite
# remedies — one says read the corpus, the other says look at launchd — and reporting the wrong one
# is not a cosmetic loss: backlog 01ab05685857 was filed verbatim out of v2's text and two later
# passes each had to hand-correct its premise before they could act.

@test "STARVED: the job is advancing and the green is cold ⇒ net:starved, and NOT the launchctl remedy" {
  green_stamp cold; age "$POSTLAND_DIR/stamps/cold.json" 48
  red_stamp fresh                                   # written minutes ago — the daemon is alive
  [ "$(net)" = "starved" ]
  warned | grep -q "GREEN-STARVED"
  warned | grep -q "the job IS loaded and its stamps dir IS advancing"
  warned | grep -q "do not go check launchctl"
  warned | grep -q "This land PROCEEDS"             # the v2 inversion survives v3 unchanged
  [ "$(warned | grep -c 'looks INERT')" -eq 0 ]
}

@test "INERT: nothing of any verdict is fresh ⇒ net:inert, and the launchctl remedy IS the right one" {
  green_stamp cold;  age "$POSTLAND_DIR/stamps/cold.json"  48
  red_stamp alsocold; age "$POSTLAND_DIR/stamps/alsocold.json" 30
  [ "$(net)" = "inert" ]
  warned | grep -q "looks INERT"
  warned | grep -q "check that com.claude.postland-verify is loaded"
  warned | grep -q "This land PROCEEDS"
  [ "$(warned | grep -c 'GREEN-STARVED')" -eq 0 ]   # exclusive — starved did not swallow inert
}

# ── THE THREE PRE-v3 ANSWERS, PINNED SO THE SPLIT CANNOT HAVE MOVED THEM ─────────────────────────

@test "LIVE: a fresh green ⇒ net:live and silence — a red stamp beside it changes nothing" {
  green_stamp fresh
  red_stamp alsofresh                               # `red ≠ liveness`, in both directions
  [ "$(net)" = "live" ]
  [ -z "$(warned)" ]
}

@test "NOT ADOPTED: stamps but no green one EVER ⇒ net:none — the bootstrap land must not warn" {
  # This is the case v3 could most easily have broken: a bootstrap box writes red stamps and no
  # green one, which is byte-for-byte the `starved` shape. The `newest -gt 0` guard, not the new
  # discriminator, is what keeps it silent.
  red_stamp only; age "$POSTLAND_DIR/stamps/only.json" 48
  [ "$(net)" = "none" ]
  [ -z "$(warned)" ]

  red_stamp alsoonly                                # …and equally when the job is plainly running
  [ "$(net)" = "none" ]
  [ -z "$(warned)" ]
}

@test "NOT ADOPTED: no stamps dir at all ⇒ net:none; and the kill switch really is one" {
  rm -rf "$POSTLAND_DIR/stamps"
  [ "$(net)" = "none" ]
  [ -z "$(warned)" ]

  mkdir -p "$POSTLAND_DIR/stamps"
  green_stamp cold; age "$POSTLAND_DIR/stamps/cold.json" 48
  red_stamp fresh
  [ "$(net)" = "starved" ]                          # positive control: the guard has something to suppress
  run env POSTLAND_STALENESS_GUARD=off bash -c '. "$1"; postland_net_live 2>"$2"; printf "%s\n" "$NET_STATE"' \
      _ "$FN" "$BATS_TEST_TMPDIR/warn"
  [ "$output" = "none" ]
  [ -z "$(warned)" ]
}

@test "the max-age seam moves BOTH clocks, so neither state is pinned to a literal 24" {
  green_stamp cold; age "$POSTLAND_DIR/stamps/cold.json" 48
  red_stamp fresh
  [ "$(net)" = "starved" ]
  # Widen past the green's age and the whole condition dissolves…
  run env POSTLAND_MAX_STAMP_AGE_H=72 bash -c '. "$1"; postland_net_live 2>"$2"; printf "%s\n" "$NET_STATE"' \
      _ "$FN" "$BATS_TEST_TMPDIR/warn"
  [ "$output" = "live" ]
  # …and narrow it under the RUNNING clock and starved becomes inert with no fixture change.
  age "$POSTLAND_DIR/stamps/fresh.json" 4
  run env POSTLAND_MAX_STAMP_AGE_H=2 bash -c '. "$1"; postland_net_live 2>"$2"; printf "%s\n" "$NET_STATE"' \
      _ "$FN" "$BATS_TEST_TMPDIR/warn"
  [ "$output" = "inert" ]
}

# ── THE OFF-BOX CLAUSE: A SENTENCE, AND NEVER A VERDICT ──────────────────────────────────────────
# v2's message asserted "nothing is re-proving the trunk". That was true when written and is false
# whenever .github/workflows/hermetic.yml is alive — it acquits the hermetic partition hourly and
# scripts/offbox-green-pull.sh transports those greens into $POSTLAND_DIR/offbox. The clause reports
# them. It may never do more than that: offbox-green-pull.sh § IT WRITES TO offbox/, NEVER TO
# stamps/ measured why a subset green must stay separable from a full-corpus one.

@test "a fresh off-box green ADDS the correcting sentence and does NOT change the state" {
  green_stamp cold; age "$POSTLAND_DIR/stamps/cold.json" 48
  red_stamp fresh
  mkdir -p "$POSTLAND_DIR/offbox"
  printf '{"tree":"abc","verdict":"green","scope":"offbox-hermetic"}\n' > "$POSTLAND_DIR/offbox/abc.json"
  [ "$(net)" = "starved" ]                          # THE STATE IS UNMOVED — the load-bearing half
  warned | grep -q "Trunk is NOT unverified meanwhile"
  warned | grep -q "SUBSET claim"
}

@test "a STALE off-box green says nothing, and no offbox dir says nothing" {
  green_stamp cold; age "$POSTLAND_DIR/stamps/cold.json" 48
  red_stamp fresh
  [ "$(net)" = "starved" ]
  [ "$(warned | grep -c 'Trunk is NOT unverified')" -eq 0 ]   # absent dir ⇒ absent clause

  mkdir -p "$POSTLAND_DIR/offbox"
  printf '{"tree":"abc","verdict":"green"}\n' > "$POSTLAND_DIR/offbox/abc.json"
  age "$POSTLAND_DIR/offbox/abc.json" 48
  [ "$(net)" = "starved" ]
  [ "$(warned | grep -c 'Trunk is NOT unverified')" -eq 0 ]   # a cold second opinion is not one
}

@test "the off-box clause rides the INERT message too — both non-live states carry it" {
  green_stamp cold;   age "$POSTLAND_DIR/stamps/cold.json" 48
  red_stamp alsocold; age "$POSTLAND_DIR/stamps/alsocold.json" 30
  mkdir -p "$POSTLAND_DIR/offbox"
  printf '{"tree":"abc","verdict":"green"}\n' > "$POSTLAND_DIR/offbox/abc.json"
  [ "$(net)" = "inert" ]
  warned | grep -q "Trunk is NOT unverified meanwhile"
}
