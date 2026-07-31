#!/usr/bin/env bats
# cc-pane — the terminal-agnostic pane seam (T1 of docs/plans/TERMINAL_AGNOSTIC_L3_L4.md).
#
# What these pin, and why each one can actually go RED:
#   * the CC_PANE_ID → ITERM_SESSION_ID compat contract, INCLUDING precedence and the
#     "neither is set" state, which is legitimate for a headless agent and must be rc 1
#     rather than an empty success;
#   * driver dispatch — default iterm2, sibling executable for anything else, and a NAMED
#     refusal for an unknown driver (a silent fallback to iterm2 would be the worst outcome:
#     a headless caller would quietly start minting real panes);
#   * that a blind `it2 session list` is INDETERMINATE (rc 2) and never "no panes". This is
#     the assertion that stops a caller reaping a live fleet, and it is the one a naive
#     implementation gets wrong.
#
# Hermetic: every it2 fork is redirected to a fake via $CC_PANE_IT2, so no test here touches
# the real iTerm2 or the real CLI. The fake RECORDS its argv, so the assertions are about what
# the seam actually invoked, not about what it printed.
#
# Every assertion is `[ ]` / `|| false` — `[[ ]]` and `(( ))` are errexit-EXEMPT in bats and
# would be silently DEAD in any but the body's last line (memory:
# bats-dead-assertions-errexit-exemptions).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CP="$REPO/bin/cc-pane"
  SHIM="$BATS_TEST_TMPDIR/fake-it2"
  REALF="$BATS_TEST_TMPDIR/fake-it2-real"
  LOG="$BATS_TEST_TMPDIR/argv.log"
  export CC_PANE_IT2="$SHIM"
  unset CC_PANE_ID ITERM_SESSION_ID CC_PANE_DRIVER || true
}

# Build the fake shim. $1 = body. The REAL_IT2= line is part of the fixture on purpose: cc-pane
# parses it out of the shim exactly as handoff-fire.sh:3239 does, so the fixture has to carry the
# same shape or the --inherit-profile leg would be tested against a straw man.
fake() {
  { printf '#!/bin/bash\n'
    printf 'REAL_IT2="%s"\n' "$REALF"
    printf 'printf "shim %%s\\n" "$*" >> "%s"\n' "$LOG"
    printf '%s\n' "$1"
  } > "$SHIM"
  chmod +x "$SHIM"
  { printf '#!/bin/bash\n'
    printf 'printf "real %%s\\n" "$*" >> "%s"\n' "$LOG"
    printf '%s\n' "${2:-$1}"
  } > "$REALF"
  chmod +x "$REALF"
}

# ── the CC_PANE_ID compat contract ────────────────────────────────────────────────────────

@test "address: CC_PANE_ID in iTerm2's prefixed form normalises to the bare id" {
  export CC_PANE_ID="w2t0p3:A5B61882-E2AD-438D-8432-3BC7B7F431F6"
  run "$CP" address
  [ "$status" -eq 0 ]
  [ "$output" = "A5B61882-E2AD-438D-8432-3BC7B7F431F6" ]
}

@test "address: falls back to ITERM_SESSION_ID — the one-release compat that keeps 18 sites working" {
  export ITERM_SESSION_ID="w0t0p0:DEAD-BEEF-0001"
  run "$CP" address
  [ "$status" -eq 0 ]
  [ "$output" = "DEAD-BEEF-0001" ]
}

@test "address: CC_PANE_ID WINS when both are set — otherwise the rename could never take effect" {
  export CC_PANE_ID="NEW-0001"
  export ITERM_SESSION_ID="w0t0p0:OLD-0002"
  run "$CP" address
  [ "$status" -eq 0 ]
  [ "$output" = "NEW-0001" ]
}

@test "address: NEITHER set is rc 1 and empty — a headless agent has no surface, which is not an error to fake" {
  run "$CP" address
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

# ── driver dispatch ───────────────────────────────────────────────────────────────────────

@test "the default driver is iterm2 — today's behaviour is reproduced unless asked otherwise" {
  run "$CP" driver
  [ "$status" -eq 0 ]
  [ "$output" = "iterm2" ]
}

@test "CC_PANE_DRIVER selects a sibling executable, and its exit code is NOT laundered" {
  local d="$BATS_TEST_TMPDIR/drv"; mkdir -p "$d"
  printf '#!/bin/bash\nprintf "mock-%%s\\n" "$1"\nexit 7\n' > "$d/cc-pane-mock"
  chmod +x "$d/cc-pane-mock"
  export CC_PANE_DRIVER_DIR="$d" CC_PANE_DRIVER=mock
  run "$CP" list
  [ "$status" -eq 7 ]
  [ "$output" = "mock-list" ]
}

@test "an unknown driver is a NAMED rc 3 — never a silent fall-through to iterm2" {
  # A silent fallback is the dangerous failure: a caller that asked for headless would start
  # minting real panes, which is precisely what the 38-pane ceiling cannot absorb.
  export CC_PANE_DRIVER_DIR="$BATS_TEST_TMPDIR/empty" CC_PANE_DRIVER=nosuch
  run "$CP" list
  [ "$status" -eq 3 ]
  printf '%s' "$output" | grep -q 'no driver nosuch' || false
}

@test "the real headless driver is reachable through the seam by name" {
  # Guards the plan §6.5 contract: `headless` must resolve to bin/cc-pane-headless with no
  # special-casing. A rename or a lost +x bit breaks the whole T2 track and must go red here.
  export CC_PANE_DRIVER=headless
  run "$CP" driver
  [ "$status" -eq 0 ]
  [ "$output" = "headless" ]
}

# ── the iterm2 driver: today's behaviour, exactly ─────────────────────────────────────────

@test "spawn parses it2's 'Created new pane:' contract and returns the bare id" {
  fake 'printf "Created new pane: NEW-PANE-42\n"; exit 0'
  export CC_PANE_ID="w1t1p1:ANCHOR-1"
  run "$CP" spawn
  [ "$status" -eq 0 ]
  [ "$output" = "NEW-PANE-42" ]
  grep -q 'shim session split -s ANCHOR-1' "$LOG" || false
}

@test "RED-proof: a split that does NOT return an id is a FAILURE, not a silent empty success" {
  # An exit-0 with unexpected stdout is the shape that would hand callers an empty pane id and
  # let every later address/send/close target nothing at all.
  fake 'printf "some other chatter\n"; exit 0'
  export CC_PANE_ID="w1t1p1:ANCHOR-1"
  run "$CP" spawn
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'did not return a pane id' || false
}

@test "spawn without an anchor and without CC_PANE_ID refuses instead of splitting some other pane" {
  fake 'printf "Created new pane: X\n"; exit 0'
  run "$CP" spawn
  [ "$status" -eq 1 ]
  [ ! -f "$LOG" ]
}

@test "spawn --inherit-profile uses the REAL binary, plain spawn uses the SHIM" {
  # Both are today's behaviour and the difference is load-bearing: the shim injects
  # -p Claude-Teammate (never-prompt) for teammate panes, while a handoff split must inherit the
  # FIRING pane's own profile — handoff-fire.sh:3232-3240 bypasses the shim for exactly this.
  fake 'printf "Created new pane: P1\n"; exit 0'
  export CC_PANE_ID="w1t1p1:ANCHOR-1"
  run "$CP" spawn
  [ "$status" -eq 0 ]
  run "$CP" spawn --inherit-profile
  [ "$status" -eq 0 ]
  grep -q '^shim session split' "$LOG" || false
  grep -q '^real session split' "$LOG" || false
}

@test "close passes -f — the ONLY reliable suppressor of iTerm2's running-job modal" {
  fake 'exit 0'
  run "$CP" close "w9t9p9:VICTIM-1"
  [ "$status" -eq 0 ]
  grep -q 'shim session close -f -s VICTIM-1' "$LOG" || false
}

@test "send delivers the text verbatim to the addressed id" {
  fake 'exit 0'
  run "$CP" send "w1t1p1:TARGET-9" hello there
  [ "$status" -eq 0 ]
  grep -q 'shim session send -s TARGET-9 hello there' "$LOG" || false
}

@test "list returns the enumerated ids" {
  fake 'printf "[{\"id\":\"AAA\"},{\"id\":\"BBB\"}]\n"; exit 0'
  run "$CP" list
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "AAA" ]
  [ "${lines[1]}" = "BBB" ]
}

@test "RED-proof: a ZERO-row enumeration is INDETERMINATE (rc 2), never 'no panes'" {
  # iTerm2 always has at least the calling pane, so 0 rows means the PROBE failed. Reporting an
  # empty fleet here is what lets a caller reap live sessions — cc-teardown:198 refuses for the
  # same reason. This is the single most dangerous wrong answer the seam could give.
  fake 'printf "[]\n"; exit 0'
  run "$CP" list
  [ "$status" -eq 2 ]
}

@test "RED-proof: an unreadable enumeration is INDETERMINATE (rc 2), not an empty fleet" {
  fake 'printf "not json at all\n"; exit 0'
  run "$CP" list
  [ "$status" -eq 2 ]
}

@test "a failing it2 makes list indeterminate rather than confidently empty" {
  fake 'exit 1'
  run "$CP" list
  [ "$status" -eq 2 ]
}

@test "address <id> verifies against the live enumeration, and an absent id is rc 1" {
  fake 'printf "[{\"id\":\"AAA\"}]\n"; exit 0'
  run "$CP" address "AAA"
  [ "$status" -eq 0 ]
  [ "$output" = "AAA" ]
  run "$CP" address "ZZZ"
  [ "$status" -eq 1 ]
}

@test "address <id> does NOT downgrade an indeterminate enumeration into 'gone'" {
  # The bug this forbids: a blind probe answering "that pane is dead", which a caller then acts
  # on by reaping a live agent. Indeterminate must propagate as indeterminate.
  fake 'exit 1'
  run "$CP" address "AAA"
  [ "$status" -eq 2 ]
}
