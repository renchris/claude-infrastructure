#!/usr/bin/env bats
# iterm2-perf-parity.bats — row 13 M8 (MACHINE_CAPACITY_V2.md §11.3). The render-knob drift check.
#
# The properties that matter, in priority order:
#   1. The script is READ-ONLY. Applying these knobs is the operator's C10 activation; a checker
#      that can also write is an actuator nobody audited.
#   2. A wrong live value MUST report DRIFT — the check has to be able to FAIL, or a green run
#      means nothing (memory verification-harness-vacuous-pass-traps).
#   3. UNSET counts as DRIFT, because SET is the activation.
#   4. THE SPOTLIGHT PROBE CANNOT ASSERT EXCLUSION FROM A BARE ZERO. Zero indexed attributes is
#      returned both by "excluded" and by "the instrument is broken", so a dead positive control
#      must degrade to NO-DATA, never MATCH.
#   5. A missing `defaults` is NO-DATA, never DRIFT — "cannot measure" != "measured, and wrong".
#
# `|| false` on every non-final [[ ]]/[ ] chain — errexit-exempt assertions are DEAD (memory
# bats-dead-assertions-errexit-exemptions). No backticks in @test names — bash evaluates them
# during test GATHERING and fails the whole file before a single test runs.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  PARITY="$REPO/scripts/iterm2-perf-parity.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages"
  STUB="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB"

  # A two-row keys fixture: one bool, one float. Small on purpose — this suite tests the LADDER,
  # not the contents of the shipped SSOT.
  export CC_IPP_KEYS="$BATS_TEST_TMPDIR/test.keys"
  cat > "$CC_IPP_KEYS" <<'EOF'
# fixture
com.googlecode.iterm2 fastForegroundJobUpdates bool false why it costs 0.15-0.4 cores
com.googlecode.iterm2 maximumFrameRate float 30 why the frame ceiling halves drawing work
EOF

  # Probe + control files for the Spotlight row. Their CONTENT is irrelevant; the mdls stub decides.
  export CC_IPP_PROBE_FILE="$BATS_TEST_TMPDIR/transcript.jsonl"
  export CC_IPP_CONTROL_FILE="$BATS_TEST_TMPDIR/control.psd"
  printf '{}\n' > "$CC_IPP_PROBE_FILE"
  printf 'x\n'  > "$CC_IPP_CONTROL_FILE"
  make_mdls 0 3   # default: excluded probe, live control — the measured real-world state
}

# Stub `defaults`: answers `read <domain> <key>` from a table, exits 1 for anything absent (which is
# exactly how the real one behaves for an unset key).
make_defaults() { # stdin = "key value" lines
  cat > "$STUB/table"
  cat > "$STUB/defaults" <<'EOF'
#!/bin/bash
[ "$1" = "read" ] || exit 1
v="$(awk -v k="$3" '$1==k{print $2; found=1} END{exit !found}' "${0%/*}/table")" || exit 1
printf '%s\n' "$v"
EOF
  chmod +x "$STUB/defaults"
  export CC_IPP_DEFAULTS_BIN="$STUB/defaults"
}

# Stub `mdls`: prints $1 indexed-content attribute lines for the probe file and $2 for the control.
make_mdls() { # $1=probe_attr_count $2=control_attr_count
  cat > "$STUB/mdls" <<EOF
#!/bin/bash
n=0
case "\$1" in
  *transcript.jsonl) n=$1 ;;
  *control.psd)      n=$2 ;;
esac
echo "kMDItemFSName = \"x\""
i=0; while [ "\$i" -lt "\$n" ]; do echo "kMDItemContentType = \"public.data\""; i=\$((i+1)); done
EOF
  chmod +x "$STUB/mdls"
  export CC_IPP_MDLS_BIN="$STUB/mdls"
}

all_match_table() {
  make_defaults <<'EOF'
fastForegroundJobUpdates 0
maximumFrameRate 30
EOF
}

@test "(i) selftest GREEN — MATCH/DRIFT/NO-DATA all reachable (positive control, R6)" {
  run /bin/bash "$PARITY" --selftest
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ "selftest GREEN" ]] || false
  [[ "$output" =~ "→ MATCH" ]] || false
  [[ "$output" =~ "→ DRIFT" ]] || false
  [[ "$output" =~ "→ NO-DATA" ]] || false
}

@test "(ii) every row at its declared value → exit 0 MATCH" {
  all_match_table
  run /bin/bash "$PARITY" --json
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ \"verdict\":\"MATCH\" ]] || false
  [[ "$output" =~ \"drift\":0 ]] || false
}

@test "(iii) THE LOAD-BEARING ONE — a wrong live value reports DRIFT (the check can FAIL)" {
  # Without this, (ii) passing would prove only that the script never says DRIFT.
  make_defaults <<'EOF'
fastForegroundJobUpdates 1
maximumFrameRate 30
EOF
  run /bin/bash "$PARITY" --json
  [ "$status" -eq 1 ] || false
  [[ "$output" =~ \"verdict\":\"DRIFT\" ]] || false
  [[ "$output" =~ \"key\":\"fastForegroundJobUpdates\",\"state\":\"DRIFT\" ]] || false
  # the correct row must still read MATCH — a blanket DRIFT would also pass a naive assertion
  [[ "$output" =~ \"key\":\"maximumFrameRate\",\"state\":\"MATCH\" ]] || false
}

@test "(iv) UNSET counts as DRIFT — the app default is live, and SET is the activation" {
  make_defaults <<'EOF'
maximumFrameRate 30
EOF
  run /bin/bash "$PARITY" --json
  [ "$status" -eq 1 ] || false
  [[ "$output" =~ \"key\":\"fastForegroundJobUpdates\",\"state\":\"UNSET\" ]] || false
  [[ "$output" =~ \"unset\":1 ]] || false
}

@test "(v) a float is compared NUMERICALLY — 30.0 is not phantom drift against 30" {
  make_defaults <<'EOF'
fastForegroundJobUpdates 0
maximumFrameRate 30.0
EOF
  run /bin/bash "$PARITY" --json
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ \"key\":\"maximumFrameRate\",\"state\":\"MATCH\" ]] || false
}

@test "(vi) missing defaults binary → NO-DATA (rc 3), never DRIFT" {
  # "Cannot measure" and "measured, and it is wrong" have different remedies. Reporting a blind run
  # as drift would send the operator to set knobs that may already be correct.
  all_match_table
  run env CC_IPP_DEFAULTS_BIN=/nonexistent/defaults /bin/bash "$PARITY" --json
  [ "$status" -eq 3 ] || false
  [[ "$output" =~ \"verdict\":\"NO-DATA\" ]] || false
  [[ "$output" =~ \"drift\":0 ]] || false
}

@test "(vii) spotlight probe: 0 attrs with a LIVE control → MATCH (still excluded)" {
  all_match_table; make_mdls 0 3
  run /bin/bash "$PARITY" --json
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ \"key\":\"spotlight_exclusion\",\"state\":\"MATCH\" ]] || false
}

@test "(viii) THE OTHER LOAD-BEARING ONE — 0 attrs with a DEAD control → NO-DATA, never MATCH" {
  # A bare zero is returned BOTH by "this file is excluded" and by "the instrument is broken".
  # §11.9(3) is explicit: never assert exclusion from a bare zero. Same input as (vii) for the
  # probe — ONLY the control differs — so this isolates the control's contribution exactly.
  all_match_table; make_mdls 0 0
  run /bin/bash "$PARITY" --json
  [ "$status" -eq 3 ] || false
  [[ "$output" =~ \"key\":\"spotlight_exclusion\",\"state\":\"NO-DATA\" ]] || false
  ! [[ "$output" =~ \"key\":\"spotlight_exclusion\",\"state\":\"MATCH\" ]] || false
}

@test "(ix) spotlight probe: indexed transcript with a live control → DRIFT" {
  # If the dot-prefix exclusion ever stops holding, this is the row that says so.
  all_match_table; make_mdls 4 3
  run /bin/bash "$PARITY" --json
  [ "$status" -eq 1 ] || false
  [[ "$output" =~ \"key\":\"spotlight_exclusion\",\"state\":\"DRIFT\" ]] || false
}

@test "(x) a missing mdls binary is NO-DATA too, not a silent MATCH" {
  all_match_table
  run env CC_IPP_MDLS_BIN=/nonexistent/mdls /bin/bash "$PARITY" --json
  [ "$status" -eq 3 ] || false
  [[ "$output" =~ \"key\":\"spotlight_exclusion\",\"state\":\"NO-DATA\" ]] || false
}

@test "(xi) DRIFT outranks NO-DATA — an actionable finding is not masked by a blind row" {
  make_defaults <<'EOF'
fastForegroundJobUpdates 1
maximumFrameRate 30
EOF
  make_mdls 0 0   # probe blind at the same time as a real knob drift
  run /bin/bash "$PARITY" --json
  [ "$status" -eq 1 ] || false
  [[ "$output" =~ \"verdict\":\"DRIFT\" ]] || false
}

@test "(xii) page is written on drift and names the keys file, then SELF-CLEARS on match" {
  make_defaults <<'EOF'
fastForegroundJobUpdates 1
maximumFrameRate 30
EOF
  run /bin/bash "$PARITY" --quiet
  [ "$status" -eq 1 ] || false
  [ -f "$CC_PAGES_DIR/iterm2-perf-drift.page" ] || false
  run cat "$CC_PAGES_DIR/iterm2-perf-drift.page"
  [[ "$output" =~ "ADRIFT" ]] || false
  [[ "$output" =~ "DECLARES the state, it never sets it" ]] || false
  # a passed condition is misinformation, not history
  printf 'stale\n' > "$CC_PAGES_DIR/iterm2-perf-drift.page.notified"
  all_match_table
  run /bin/bash "$PARITY" --quiet
  [ "$status" -eq 0 ] || false
  [ ! -f "$CC_PAGES_DIR/iterm2-perf-drift.page" ] || false
  [ ! -f "$CC_PAGES_DIR/iterm2-perf-drift.page.notified" ] || false
}

@test "(xiii) READ-ONLY — the script never writes or deletes a default (EXECUTABLE lines only)" {
  # Comments are stripped first: the header prose explains at length that it never writes, and a
  # bare grep would convict the documentation of the property it checks (memory
  # detector-matching-its-own-skill-description). The existence guard stops a vacuous pass against
  # a tree where the script does not exist at all.
  [ -f "$PARITY" ] || false
  run bash -c "sed 's/#.*//' '$PARITY' | grep -nE 'defaults[^|]*(write|delete)|DEFAULTS_BIN\" (write|delete)'"
  [ "$status" -ne 0 ] || false
}

@test "(xiv) POSITIVE CONTROL for (xiii): the same grep catches a real defaults write" {
  printf '# never writes a default\ndefaults write com.googlecode.iterm2 UseMetal -bool true\n' \
    > "$BATS_TEST_TMPDIR/bait.sh"
  run bash -c "sed 's/#.*//' '$BATS_TEST_TMPDIR/bait.sh' | grep -nE 'defaults[^|]*(write|delete)'"
  [ "$status" -eq 0 ] || false
  printf '# never writes a default\ndefaults read com.googlecode.iterm2 UseMetal\n' \
    > "$BATS_TEST_TMPDIR/clean.sh"
  run bash -c "sed 's/#.*//' '$BATS_TEST_TMPDIR/clean.sh' | grep -nE 'defaults[^|]*(write|delete)'"
  [ "$status" -ne 0 ] || false
}

@test "(xv) kill switch CC_IPP_PARITY=off → rc 0 and NO page written" {
  make_defaults <<'EOF'
fastForegroundJobUpdates 1
EOF
  run env CC_IPP_PARITY=off /bin/bash "$PARITY" --quiet
  [ "$status" -eq 0 ] || false
  [ ! -f "$CC_PAGES_DIR/iterm2-perf-drift.page" ] || false
}

@test "(xvi) the SHIPPED keys file parses and declares every knob §11.9 priced" {
  # Guards the SSOT itself, not the ladder: a typo'd domain or a dropped row would silently shrink
  # the checked set, and a parity run over four rows would still report a confident MATCH.
  KEYS="$REPO/config/iterm2-perf.keys"
  [ -f "$KEYS" ] || false
  run bash -c "grep -vE '^[[:space:]]*(#|\$)' '$KEYS' | wc -l | tr -d ' '"
  [ "$output" -eq 8 ] || false
  for k in disableAdaptiveFrameRateInInteractiveApps maximumFrameRate activeUpdateCadence \
           slowFrameRate fastForegroundJobUpdates animateGraphStatusBarComponents \
           DimInactiveSplitPanes DimOnlyText; do
    run bash -c "grep -cE '^com\.googlecode\.iterm2 $k (bool|float) ' '$KEYS'"
    [ "$output" -eq 1 ] || false
  done
  # UseMetal is a CANDIDATE at MEDIUM risk (60 CAMetalLayers) — it must NOT be parity-checked yet.
  run bash -c "grep -vE '^[[:space:]]*#' '$KEYS' | grep -c UseMetal"
  [ "$output" -eq 0 ] || false
}
