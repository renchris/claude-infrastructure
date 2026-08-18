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
  # Fixture $HOME before anything else. cc-pane's it2_bin() defaults to $HOME/.claude/bin/it2, so
  # an unfixtured suite would resolve the OPERATOR'S REAL shim the moment a test forgot to set
  # $CC_PANE_IT2 — running the fleet's live it2 from a test run. Caught by the land gate's
  # test-hermeticity ratchet, which is right: an unfixtured suite mutates live state and makes the
  # whole run's results untrustworthy, not just its own.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # Pin the fire capacity gate off: it refuses above 2.0/core and this box lives well above that,
  # so leaving it ambient makes a suite go red-by-LOAD rather than by its subject.
  export CC_FIRE_CAPACITY_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CP="$REPO/bin/cc-pane"
  SHIM="$BATS_TEST_TMPDIR/fake-it2"
  REALF="$BATS_TEST_TMPDIR/fake-it2-real"
  LOG="$BATS_TEST_TMPDIR/argv.log"
  export CC_PANE_IT2="$SHIM"
  # PIN THE TERMINAL. Every test in this file exercises the iTerm2 path, and it2_real_bin() now
  # resolves the SHIM instead of the raw binary when KITTY_WINDOW_ID is set (inside kitty the shim
  # execs bin/it2-kitty and never injects -p Claude-Teammate, so there is nothing to bypass). Without
  # this pin the suite's verdict depends on which terminal the developer happens to be sitting in:
  # measured 2026-07-31, run from kitty, "spawn --inherit-profile uses the REAL binary" failed; from
  # the same shell with the divert pinned off it passes, and so does baseline HEAD.
  # This is the SAME defect tests/it2-wrapper.bats:setup() already carries, for the same reason, and
  # it predates the divert in both files — KITTY_WINDOW_ID was simply never read before. Unsetting
  # the real var AND pinning the kill switch covers both spellings.
  unset CC_PANE_ID ITERM_SESSION_ID CC_PANE_DRIVER KITTY_WINDOW_ID || true
  export IT2_WRAPPER_NO_KITTY=1
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

# ── argv the seam does not implement is a NAMED refusal, never a silent drop ───────────────
# The three tests below are one per SITE in bin/cc-pane's verb dispatch. The defect they pin was
# real and measured (backlog d65dcfd22ce2): `list` dropped "$@", so `list --json` and `list` were
# BYTE-IDENTICAL — bare ids, exit 0. json.load() on that raises, which is the parser being right
# about a liar, and the consumer then reads its own failure as the DATA's fault. The test above is
# this one's positive control: bare `list` must stay rc 0 with the ids, or the refusal below has
# merely broken the verb rather than made it honest.

@test "list REFUSES --json with rc 3 — a silently-ignored flag is worse than an absent one" {
  fake 'printf "[{\"id\":\"AAA\"},{\"id\":\"BBB\"}]\n"; exit 0'
  run "$CP" list --json
  [ "$status" -eq 3 ]
  # Count, never `grep -q` on a pipe: under pipefail -q exits on the first hit and the still-writing
  # producer takes SIGPIPE, so the filter FAILS on the very input it matched (memory:
  # grep-q-under-pipefail-inverts-the-verdict).
  nmsg="$(printf '%s\n' "$output" | grep -cF 'list: takes no arguments' || true)"
  [ "${nmsg:-0}" -ge 1 ]
  # A refusal that ALSO prints the ids is the same lie in a louder voice — the caller could still
  # parse them and never notice the rc.
  nid="$(printf '%s\n' "$output" | grep -cF 'AAA' || true)"
  [ "${nid:-0}" -eq 0 ]
}

@test "address takes exactly ONE id — a trailing flag is rc 3, not an ignored argument" {
  fake 'printf "[{\"id\":\"AAA\"}]\n"; exit 0'
  run "$CP" address AAA --json
  [ "$status" -eq 3 ]
  n="$(printf '%s\n' "$output" | grep -cF 'address: takes exactly one id' || true)"
  [ "${n:-0}" -ge 1 ]
}

@test "close takes exactly ONE id, and the refusal happens BEFORE any pane is reaped" {
  fake 'exit 0'
  run "$CP" close "VICTIM-1" --force
  [ "$status" -eq 3 ]
  n="$(printf '%s\n' "$output" | grep -cF 'close: takes exactly one id' || true)"
  [ "${n:-0}" -ge 1 ]
  # The worst possible shape for this bug: refuse the argv AND close the pane anyway. The fake
  # shim records its argv, so this asserts against what the seam INVOKED, not what it printed.
  m="$(grep -cF 'session close' "$LOG" 2>/dev/null || true)"
  [ "${m:-0}" -eq 0 ]
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

# ── the class-2 rename is LIVE, not merely green ──────────────────────────────────────────
# The 31 suites over the 15 renamed files stayed 636/636 green, but green-because-untested is
# exactly this repo's recorded failure mode: nothing in those suites sets CC_PANE_ID, so they
# would have passed identically had the rename done nothing at all. These two assert the new
# capability itself.

@test "the rename is LIVE at a real consumer: session-register.sh honours CC_PANE_ID alone" {
  command -v jq >/dev/null 2>&1 || false   # a skip here would be a NON-VERDICT, not a pass
  local reg="$BATS_TEST_TMPDIR/reg" u="FEEDFACE-0001-0002-0003-000000000004"
  run env -u ITERM_SESSION_ID CC_PANE_ID="w0t0p0:$u" CC_REGISTRY_DIR="$reg" \
      /bin/bash -c 'printf "{\"cwd\":\"/tmp\",\"session_id\":\"s-1\"}" | "$0"' \
      "$REPO/hooks/session-register.sh"
  [ -f "$reg/$u.json" ]
  grep -q "$u" "$reg/$u.json" || false
}

@test "negative control: with NEITHER var set that same consumer registers NOTHING" {
  # Without this the test above could pass for a reason unrelated to CC_PANE_ID — a row written
  # from some other resolution path would look identical.
  command -v jq >/dev/null 2>&1 || false
  local reg="$BATS_TEST_TMPDIR/reg2"
  run env -u ITERM_SESSION_ID -u CC_PANE_ID CC_REGISTRY_DIR="$reg" \
      /bin/bash -c 'printf "{\"cwd\":\"/tmp\",\"session_id\":\"s-1\"}" | "$0"' \
      "$REPO/hooks/session-register.sh"
  [ -z "$(ls -A "$reg" 2>/dev/null)" ]
}

@test "ratchet: no production file reads a BARE \$ITERM_SESSION_ID without the CC_PANE_ID fallback" {
  # Stops the rename silently un-doing itself as new code is written. Exemptions are the class-3
  # files (T3 owns them; this track must not touch them — plan §6.1) and any line carrying an
  # explicit `cc-pane-id-lint:allow` marker, which is how bin/cc-pane's own fallback DEFINITION
  # opts out. Deliberately a per-LINE marker and not a per-FILE path exemption: exempting the
  # whole seam file would blind the ratchet to a genuine bare read added to it later (memory:
  # blanket-remedy-inverts-guards). This fired on its first run and caught exactly that line,
  # which is also the proof it can go red.
  local hits
  hits="$(grep -rn -F '${ITERM_SESSION_ID:-}' "$REPO/bin" "$REPO/scripts" "$REPO/hooks" 2>/dev/null \
          | grep -v 'CC_PANE_ID' \
          | grep -v 'cc-pane-id-lint:allow' \
          | grep -vE 'handoff-fire\.sh|handoff-selfclose-e2e\.sh|lr-handoff\.sh' || true)"
  [ -z "$hits" ] || { printf 'bare reads still present:\n%s\n' "$hits"; false; }
}

@test "address <id> does NOT downgrade an indeterminate enumeration into 'gone'" {
  # The bug this forbids: a blind probe answering "that pane is dead", which a caller then acts
  # on by reaping a live agent. Indeterminate must propagate as indeterminate.
  fake 'exit 1'
  run "$CP" address "AAA"
  [ "$status" -eq 2 ]
}
