#!/usr/bin/env bats
# A bats run that did not cover its own plan is a NON-VERDICT, and bats says so in a line no reader
# on this box read (backlog da839cd0d89e).
#
# THE STATE. bats validates its own run: lib/bats-core/validator.bash:30 counts the `ok`/`not ok`
# lines it forwarded, compares them against the `1..N` header it forwarded first, and on a mismatch
# prints `# bats warning: Executed <A> instead of expected <B> tests` and returns 1 — which under
# bats:517-524's pipefail IS the run's exit code. A run whose corpus HALF executed and a run whose
# tests genuinely failed therefore arrive at every consumer with the SAME rc 1, and that warning was
# the only thing separating them. `git grep -n 'bats warning'` over scripts/ bin/ hooks/ matched
# NOTHING on 2026-09-07, so both readers below are new.
#
# WHY IT IS A VERDICT DEFECT. The generator is losing $BATS_RUN_TMPDIR under a live run (a tmp
# reaper, a full disk, a peer's cleanup), and bats does not fail loudly for it — it emits ORDINARY
# `not ok` lines, some carrying well-formed `# (in test file …)` diagnostics, which attribute
# cleanly to innocent files. The field instance: `Executed 1328 instead of expected 2789` — 1461
# tests never ran, rendered as three ordinary `not ok` lines. Downstream, either outcome is wrong.
# Convict, and the stamp names files whose tests were never the problem; exonerate — the LIKELY
# branch, since a fresh TMPDIR removes the cause — and the run is stamped GREEN over a corpus that
# 52% never executed. A green stamp is what deploy-live.sh and ship-land.sh:postland_net_live read.
#
# THE ARTIFACT IS REAL AND IS MADE HERE, never a checked-in fixture (memory:
# control-must-replay-the-real-artifact, fixture-literal-date-expires-against-a-ttl). A fixture
# would pin the WORDING of a third-party tool and rot silently the day Homebrew bumps bats; worse,
# it could not tell us that this bats still behaves this way. `make_truncated_tap` runs the REAL
# bats over a real 6-test corpus whose second test removes its own run dir — DETERMINISTIC, no
# sleep race — and every consumer test asserts against what that run actually printed.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SHIP="$REPO/scripts/ship-land.sh"
  PV="$REPO/scripts/postland-verify.sh"
  DL="$REPO/scripts/deploy-live.sh"
  BATS_BIN="${BATS_BIN:-$(command -v bats)}"
  T="$BATS_TEST_TMPDIR/w"; mkdir -p "$T"
}

# ── the generator ────────────────────────────────────────────────────────────────────────────────
# Writes $T/tap. Six planned tests across two files; test 2 deletes $BATS_RUN_TMPDIR, which is what
# a tmp reaper does to a long run. THE GUARD IS NOT DECORATION: bats exports BATS_RUN_TMPDIR, and an
# inner suite that saw the OUTER value would delete the harness running this file. The inner body
# refuses unless the two differ, so the failure mode is a red test, never a shredded corpus run.
make_truncated_tap() {
  mkdir -p "$T/t" "$T/tmp"
  cat > "$T/t/a.bats" <<'INNER'
@test "a1" { true; }
@test "a2 reclaims the run dir" {
  [ -n "$OUTER_RUN_TMPDIR" ] || return 1
  [ "$BATS_RUN_TMPDIR" != "$OUTER_RUN_TMPDIR" ] || return 1
  rm -rf "$BATS_RUN_TMPDIR"
}
@test "a3" { true; }
@test "a4" { true; }
INNER
  cat > "$T/t/b.bats" <<'INNER'
@test "b1" { true; }
@test "b2" { true; }
INNER
  # CC_BATS_QOS=off + CC_BATS_MAX_ROOTS=0: the QoS shim and its admission bound are DIFFERENT
  # mechanisms with their own suite, and an admission refusal here would produce a run that never
  # started — a different non-verdict, and one that would make this file's assertions vacuous.
  env OUTER_RUN_TMPDIR="${BATS_RUN_TMPDIR:-/nonexistent}" TMPDIR="$T/tmp" \
      CC_BATS_QOS=off CC_BATS_MAX_ROOTS=0 \
      "$BATS_BIN" "$T/t" > "$T/tap" 2>&1 </dev/null || true
}

# ── the generator's own positive control ─────────────────────────────────────────────────────────
@test "the real bats really does report a shortfall when its run dir vanishes" {
  # Runs FIRST and asserts the premise every other test in this file rests on. Without it, an
  # upstream that stopped emitting the warning (or a bats that refused to start) would make every
  # assertion below pass VACUOUSLY — the shortfall reader would return "" and the legs would be
  # inert, which is byte-identical to "the fix works" (memory: verification-harness-vacuous-pass).
  make_truncated_tap
  [ -s "$T/tap" ]
  grep -q '^1\.\.6$' "$T/tap"
  grep -q '^# bats warning: Executed 3 instead of expected 6 tests$' "$T/tap"
  # …and the signature the field instance was reported under, so this is the same event and not a
  # different truncation that happens to share a warning line.
  grep -q 'test_list_file\.txt: No such file or directory' "$T/tap"
}

@test "the truncated run is INDISTINGUISHABLE from a red by every pre-existing signal" {
  # The other half of the premise: this is why a new reader was needed rather than a new use of an
  # old one. rc 1 (bats' 'something failed'), a plan that does NOT contradict the corpus size, and
  # `not ok` lines that pass the strict TAP grammar — one of them even carrying a well-formed
  # `# (in test file …)` diagnostic, which is what walks it into the attribution ladder.
  make_truncated_tap
  run grep -acE '^not ok [0-9]+' "$T/tap"
  [ "$output" -eq 2 ]
  grep -qE '^# \(in test file .*a\.bats, line [0-9]+\)' "$T/tap"
}

# ── scripts/ship-land.sh — LEG C ─────────────────────────────────────────────────────────────────
ship_fns() {  # tap_plan + tap_shortfall + tap_named_failures, as the lander will run them
  {
    sed -n '/^tap_plan() {/,/^}/p'            "$SHIP"
    sed -n '/^tap_shortfall() {/,/^}/p'       "$SHIP"
    sed -n '/^tap_named_failures() {/,/^}/p'  "$SHIP"
  } > "$T/ship-fns.sh"
  [ -s "$T/ship-fns.sh" ]
}

@test "ship-land: a truncated run names ZERO failures (pre-fix it named 2)" {
  make_truncated_tap; ship_fns
  run bash -c '. "$1"; tap_named_failures "$2" 0 tests/a.bats 2>/dev/null' _ "$T/ship-fns.sh" "$T/tap"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "ship-land: the discard SAYS SO on stderr, with both counts" {
  # A silent discard is the defect one layer down: the reader of a land refusal must be able to see
  # that the run was truncated, not that the suite was clean.
  make_truncated_tap; ship_fns
  run bash -c '. "$1"; tap_named_failures "$2" 0 tests/a.bats 2>&1 >/dev/null' _ "$T/ship-fns.sh" "$T/tap"
  printf '%s\n' "$output" | grep -q 'executed 3 of the 6 tests it planned'
  printf '%s\n' "$output" | grep -q 'never ran'
}

@test "CONTROL: a genuine red with NO shortfall line keeps every one of its failures" {
  # THE MUTANT GUARD. Leg C discards `not ok` lines, so its failure mode is over-firing — eating a
  # real red and softening it to 'retry when quieter', the one direction this split must never fail
  # in. A complete run, plan and executed equal, emits no warning at all and must be untouched.
  ship_fns
  cat > "$T/red.tap" <<'TAP'
1..3
ok 1 fine
not ok 2 genuinely broken
# (in test file tests/a.bats, line 9)
not ok 3 also broken
# (in test file tests/a.bats, line 14)
TAP
  run bash -c '. "$1"; tap_named_failures "$2" 0 tests/a.bats 2>/dev/null' _ "$T/ship-fns.sh" "$T/red.tap"
  [ "$output" = "2" ]
}

@test "CONTROL: a TEST'S OWN output that merely mentions the warning does not disarm the gate" {
  # This stream is captured 2>&1 and this repo runs suites that print about bats, so the needle is
  # bats' full line at column 0 — the `# ` TAP-comment prefix and both digit groups — never the word
  # `Executed`. Three near-misses that must all stay RED.
  ship_fns
  cat > "$T/near.tap" <<'TAP'
1..2
not ok 1 a test whose body echoes
#   Executed 3 instead of expected 6 tests
# (in test file tests/a.bats, line 3)
not ok 2 and one that indents bats' exact line
#    # bats warning: Executed 3 instead of expected 6 tests
# (in test file tests/a.bats, line 7)
TAP
  run bash -c '. "$1"; tap_named_failures "$2" 0 tests/a.bats 2>/dev/null' _ "$T/ship-fns.sh" "$T/near.tap"
  [ "$output" = "2" ]
}

# ── scripts/postland-verify.sh — the belt ────────────────────────────────────────────────────────
pv_reader() { sed -n '/^tap_shortfall() {/,/^}/p' "$PV" > "$T/pv-fn.sh"; [ -s "$T/pv-fn.sh" ]; }

@test "postland-verify: tap_shortfall reads the real artifact as executed/planned" {
  make_truncated_tap; pv_reader
  run bash -c '. "$1"; tap_shortfall "$2"' _ "$T/pv-fn.sh" "$T/tap"
  [ "$output" = "3/6" ]
}

@test "postland-verify: a COMPLETE run reports no shortfall at all" {
  # Including the empty-corpus plan `1..0`, which bats does not warn about (0 == 0) and which this
  # file already treats as its own non-verdict elsewhere. A reader that returned a value here would
  # route every clean run into the cut path and no tree could ever be stamped green again.
  pv_reader
  printf '1..2\nok 1 a\nok 2 b\n' > "$T/green.tap"
  printf '1..0\n'                 > "$T/empty.tap"
  run bash -c '. "$1"; tap_shortfall "$2"' _ "$T/pv-fn.sh" "$T/green.tap"
  [ -z "$output" ]
  run bash -c '. "$1"; tap_shortfall "$2"' _ "$T/pv-fn.sh" "$T/empty.tap"
  [ -z "$output" ]
}

@test "postland-verify: the shortfall gate CUTS the run and never reaches classify_failures" {
  # The routing, executed rather than grepped. The block is lifted verbatim out of run_target and
  # run against stubs, so this asserts the three things that decide the stamp: CUT is set (so the
  # green branch is unreachable), CUT_WHY names both counts, and classify_failures — whose retry
  # ladder would spend bounded re-runs to answer a question already settled, and whose likeliest
  # answer is the false green — is never called.
  sed -n '/^  SHORTFALL="\$(tap_shortfall "\$tap")"$/,/^  fi$/p' "$PV" > "$T/gate.sh"
  [ -s "$T/gate.sh" ]
  run bash -c '
    set -u
    tap_shortfall() { printf "1328/2789"; }
    classify_failures() { echo "LADDER-RAN"; }
    log() { :; }
    CUT=0; CUT_WHY=""; rc=1; tap=/dev/null
    . "$1"
    echo "CUT=$CUT"; echo "WHY=$CUT_WHY"
  ' _ "$T/gate.sh"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '^CUT=1$'
  printf '%s\n' "$output" | grep -q 'executed 1328 of the 2789 tests it planned'
  printf '%s\n' "$output" | grep -q '1461 never ran'
  ! printf '%s\n' "$output" | grep -q 'LADDER-RAN'
}

@test "postland-verify: a CLEAN run still reaches classify_failures" {
  # The other side of the same branch — without this, deleting the else arm outright would pass.
  sed -n '/^  SHORTFALL="\$(tap_shortfall "\$tap")"$/,/^  fi$/p' "$PV" > "$T/gate.sh"
  run bash -c '
    set -u
    tap_shortfall() { printf ""; }
    classify_failures() { echo "LADDER-RAN"; }
    log() { :; }
    CUT=0; CUT_WHY=""; rc=1; tap=/dev/null
    . "$1"
    echo "CUT=$CUT"
  ' _ "$T/gate.sh"
  printf '%s\n' "$output" | grep -q 'LADDER-RAN'
  printf '%s\n' "$output" | grep -q '^CUT=0$'
}

# ── the two readers may not drift apart ──────────────────────────────────────────────────────────
@test "both readers spell the shortfall literal IDENTICALLY" {
  # Same argument tests/tap-grammar-parity.bats makes for the not-ok grammar, and the same reason it
  # is a test rather than a shared library: ~/.claude is reached by PER-FILE symlinks, so a new lib
  # file is ABSENT from the live layer until deploy-live converges, and the `[ -f lib ] && . lib`
  # guard every consumer would need turns that absence into a SILENT fall-back — on exactly the
  # boxes that run a land. The literal is repeated deliberately; this keeps the repetitions equal.
  local needle='^# bats warning: Executed [0-9]+ instead of expected [0-9]+ tests$' f
  for f in "$SHIP" "$PV" "$DL"; do
    grep -qF -- "$needle" "$f"
    run bash -c 'grep -cF -- "$1" "$2"' _ "$needle" "$f"
    [ "$output" = "1" ]
  done
}

# ── scripts/deploy-live.sh — the host-suite belt ─────────────────────────────────────────────────
# The same defect with the widest blast radius in the repo, and the reason it is folded in here
# rather than filed: this ladder does not merely mis-report. A RED writes `$s($notok)` into a page
# AND into cc-backlog, whose event key is project+title+source — so the failing SET, which is a
# function of WHERE the truncation landed, becomes part of the key and a NEW work item is minted
# every time load moves that point. The file's own comment already records that exact
# non-idempotency for the rc-124 case it fixed (cb9980e4b0e5); a shortfall reaches the identical
# outcome by the door that fix does not cover, because bats exits 1, not 124.
dl_ladder() {  # the verdict ladder, lifted verbatim out of host_checks
  sed -n '/^    if \[ "\$rc" -eq 124 \]; then$/,/^    fi$/p' "$DL" > "$T/dl.sh"
  [ -s "$T/dl.sh" ]
  grep -q 'short' "$T/dl.sh"
}

@test "deploy-live: a truncated host suite is a CUT, and files nothing" {
  # rc 1 + named `not ok` lines + a shortfall = the shape our own bound cannot see. Pre-fix this
  # arm did not exist, so control fell to `notok -gt 0` and the suite was reported RED.
  dl_ladder
  run bash -c '
    set -u
    say() { echo "$*"; }
    rc=1; notok=2; short="1328/2789"; s=tests/x.bats; reached=""
    red=""; redset=""; cut=""; iscut=0; greenset=""; newgreen=""; sha=deadbeef
    . "$1"
    echo "RED=[$red] CUT=[$cut] ISCUT=$iscut"
  ' _ "$T/dl.sh"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'RED=\[\] CUT=\[ tests/x.bats\] ISCUT=1'
  printf '%s\n' "$output" | grep -q 'executed 1328 of the 2789 tests it planned'
  printf '%s\n' "$output" | grep -q '1461 never ran'
  # the reached-but-discarded count is REPORTED, not swallowed: a non-verdict must not also be a
  # silence, which is the rule the rc-124 arm one branch up already follows.
  printf '%s\n' "$output" | grep -q '2 reached failure(s) discarded'
}

@test "CONTROL: deploy-live still REDS a complete run that named failures" {
  # The mutant guard for the new arm: identical inputs minus the shortfall must stay a red, or the
  # arm has eaten the channel it was inserted into.
  dl_ladder
  run bash -c '
    set -u
    say() { echo "$*"; }
    rc=1; notok=2; short=""; s=tests/x.bats; reached=""
    red=""; redset=""; cut=""; iscut=0; greenset=""; newgreen=""; sha=deadbeef
    . "$1"
    echo "RED=[$red] CUT=[$cut]"
  ' _ "$T/dl.sh"
  printf '%s\n' "$output" | grep -q 'RED=\[ tests/x.bats(2)\] CUT=\[\]'
}

@test "CONTROL: deploy-live still greens a clean run" {
  dl_ladder
  run bash -c '
    set -u
    say() { echo "$*"; }
    rc=0; notok=0; short=""; s=tests/x.bats; reached=""
    red=""; redset=""; cut=""; iscut=0; greenset=""; newgreen=""; sha=deadbeef
    . "$1"
    echo "GREEN=[$greenset] RED=[$red] CUT=[$cut]"
  ' _ "$T/dl.sh"
  printf '%s\n' "$output" | grep -q 'GREEN=\[ tests/x.bats\] RED=\[\] CUT=\[\]'
}
