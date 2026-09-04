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

# ── `send`: the transport follows the PAYLOAD (backlog 07ac6d58d88d) ──────────────────────
# The three below are one contract, split by the only distinction that matters to a pane that
# runs a shell. A control-only payload types no command line, so there is no first word for
# `setopt CORRECT` to offer a correction for and nothing to echo-verify: it goes raw. Anything
# else IS a command line the moment it lands on ZLE's input line, and a raw send of one is the
# silent-hang landmine scripts/typed-send-lint.sh exists to stop — this file used to pin the
# opposite, asserting that `send … hello there` reached `session send` verbatim.
@test "send raw-transports a control-only payload verbatim" {
  fake 'exit 0'; : > "$LOG"
  local osa="$BATS_TEST_TMPDIR/osascript-unused" olog="$BATS_TEST_TMPDIR/osa-unused.log"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$olog" > "$osa"
  chmod +x "$osa"; : > "$olog"
  OSA_LOG="$olog" CC_OSASCRIPT_BIN="$osa" run "$CP" send "w1t1p1:TARGET-9" $'\r'
  [ "$status" -eq 0 ] || { echo "control send failed: $output"; false; }
  grep -q 'shim session send -s TARGET-9' "$LOG" || { echo "no raw send recorded"; cat "$LOG"; false; }
  # The verified path costs three AppleEvents and a settle per line. A bare CR must not pay it.
  [ ! -s "$olog" ] || { echo "a control payload went through verified typing"; cat "$olog"; false; }
}

@test "send routes a COMMAND LINE through verified typing, never the raw transport" {
  fake 'exit 0'; : > "$LOG"
  local stub="$BATS_TEST_TMPDIR/osascript" olog="$BATS_TEST_TMPDIR/osa.log"
  cat > "$stub" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${OSA_LOG:?}"
case "$*" in
  *"contents of s"*) for a in "$@"; do case "$a" in ": cctv-"*) printf '%s\n' "$a" ;; esac; done ;;
esac
exit 0
STUB
  chmod +x "$stub"; : > "$olog"
  OSA_LOG="$olog" CC_OSASCRIPT_BIN="$stub" CC_NOCORRECT=0 CC_TYPE_ATTEMPTS=2 CC_TYPE_SETTLE=0 \
    CC_TYPE_PRESETTLE=0 run "$CP" send "w1t1p1:TARGET-9" echo hi
  [ "$status" -eq 0 ] || { echo "verified send failed: $output"; cat "$olog"; false; }
  grep -q 'TARGET-9' "$olog" || { echo "the normalised id never reached the helper"; cat "$olog"; false; }
  grep -q 'echo hi' "$olog" || { echo "the command was never typed"; cat "$olog"; false; }
  # `write text "" newline yes` is the Enter. Its presence is the proof the line was read back
  # first — the helper sends it only on a match, which tests/typed-send-shared-discipline.bats pins.
  grep -q 'newline yes' "$olog" || { echo "typed but never submitted"; cat "$olog"; false; }
  ! grep -q 'session send' "$LOG" || { echo "a command line took the RAW transport"; cat "$LOG"; false; }
}

@test "send FAILS LOUD when verified typing cannot be sourced — never a blind raw send" {
  # The one condition under which the old blind behaviour looks like a reasonable fallback. It is
  # not: a caller told "sent" over a pane parked on [nyae] is exactly the loss this replaced.
  # $HOME is already the fixture, so the ladder's last rung is absent; CLAUDE_CONFIG_DIR is the
  # middle one and must be pointed somewhere real-but-empty rather than left ambient.
  fake 'exit 0'; : > "$LOG"
  mkdir -p "$BATS_TEST_TMPDIR/isolated/bin" "$BATS_TEST_TMPDIR/isolated/cfg"
  cp "$CP" "$BATS_TEST_TMPDIR/isolated/bin/cc-pane"
  CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/isolated/cfg" \
    run "$BATS_TEST_TMPDIR/isolated/bin/cc-pane" send "w1t1p1:TARGET-9" echo hi
  [ "$status" -eq 1 ] || { echo "expected rc 1 (the driver said no), got $status: $output"; false; }
  case "$output" in
    *"needs verified typing and cannot source"*) ;;
    *) echo "wrong failure, and a wrong failure here is indistinguishable from the bug: $output"; false ;;
  esac
  ! grep -q 'session send' "$LOG" || { echo "fell back to a blind raw send"; cat "$LOG"; false; }
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

@test "ratchet: no production file reads ANOTHER pid's ITERM_SESSION_ID without CC_PANE_ID first" {
  # CLASS B — the population the ratchet above is STRUCTURALLY BLIND TO (item 0f796daa0c76).
  #
  # That ratchet greps for the shell spelling `${ITERM_SESSION_ID:-}`, i.e. a process reading its
  # OWN id. A second, entirely disjoint class reads the pane id of ANOTHER pid, out of a `ps eww`
  # environment blob, where the key is a STRING and never a parameter expansion:
  #
  #     grep -m1 '^ITERM_SESSION_ID='        env_val "$blob" ITERM_SESSION_ID
  #     index($i, "ITERM_SESSION_ID=") == 1
  #
  # None of those contain `${ITERM_SESSION_ID:-}`, so the rename's own enforcement could not see
  # them and five sites sat un-migrated behind a green ratchet. The fix for the rename existed,
  # had landed, and simply could not reach the call sites that needed it (memory:
  # conclusion-must-reach-the-enforcing-store). This case is that reach.
  #
  # SAME per-LINE marker as above, not a per-file exemption: the correct implementation of a
  # PREFERENCE necessarily contains one line that reads ITERM_SESSION_ID alone — the fallback
  # branch — exactly as bin/cc-pane:80's own fallback DEFINITION opts out.
  #
  # Comment lines are dropped BEFORE judging. A prose line that merely says the word "grep" near
  # the key is not a read, and a detector that cannot tell them apart answers a different question
  # than the one asked (memory: spec-named-mechanism-may-be-prose-only).
  #
  # EXEMPTIONS are the class-3 files the sibling track owns (plan §6.1), carried over verbatim from
  # the ratchet above. NOTE, because it is a live fact and not a rounding error: handoff-fire.sh:3277
  # IS a genuine class-B site (`grep -m1 '^ITERM_SESSION_ID='` over a `ps eww` blob). It is excluded
  # BY CONSTRUCTION here, not overlooked — item 0f796daa0c76 named "4 sites" and the true in-track
  # population is 5 (it missed bin/cc-teardown's occupancy oracle), plus this 6th behind T3's fence.
  local hits
  hits="$(grep -rnE '(grep|index\(|env_val).*ITERM_SESSION_ID' "$REPO/bin" "$REPO/scripts" "$REPO/hooks" 2>/dev/null \
          | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' \
          | grep -v 'CC_PANE_ID' \
          | grep -v 'cc-pane-id-lint:allow' \
          | grep -vE 'handoff-fire\.sh|handoff-selfclose-e2e\.sh|lr-handoff\.sh' || true)"
  [ -z "$hits" ] || { printf 'class-B env-blob reads still ITERM-only:\n%s\n' "$hits"; false; }
}

# Extract a shell function VERBATIM from a production file into $2, so the cases below exercise the
# shipped code rather than a retyped copy. A retyped copy is a DEAD assertion: it keeps passing after
# the subject changes, and it passes on the pre-fix tree too, which is the same thing as not testing.
# A missing anchor is a LOUD failure, never a silent green (memory: control-must-replay-the-real-artifact).
extract_fn() { # <file> <fn-name> <out-path>
  python3 - "$1" "$2" "$3" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^%s\(\) \{.*?\n\}" % re.escape(sys.argv[2]), src, re.S | re.M)
assert m, "ANCHOR MISSING: %s() not found in %s — this control is BLIND, not green" % (sys.argv[2], sys.argv[1])
open(sys.argv[3], "w", encoding="utf-8").write(m.group(0) + "\n")
PY
}

@test "class B: pane_of_env PREFERS CC_PANE_ID when a STALE ITERM_SESSION_ID sits beside it" {
  # The behaviour the ratchet above only asserts the SHAPE of. $ITERM_SESSION_ID inherits across
  # exec and across pane boundaries, so "both keys present, disagreeing" is the designed-for case,
  # not a corner: an OR-match would resolve the pid to the pane it USED to be in.
  #
  # BOTH copies are pinned, in one loop. The two desk scripts carry the helper independently (they
  # source no shared lib), so the duplication is real and a diverging copy is the live risk — one
  # case covering only one file would credit neither site (memory: per-site-mutation-attributes-coverage).
  local f fn out blob
  blob="$(printf '%s\n' 'PWD=/tmp' 'ITERM_SESSION_ID=w0t0p0:STALE-1111' 'CC_PANE_ID=REAL-2222')"
  for f in scripts/desk-arm-live.sh scripts/desk-recycle-invariant.sh; do
    fn="$BATS_TEST_TMPDIR/$(basename "$f").fn"
    extract_fn "$REPO/$f" pane_of_env "$fn"
    out="$(CC_TEST_BLOB="$blob" bash -c '. "$1"; pane_of_env "$CC_TEST_BLOB"' _ "$fn")"
    [ "$out" = "REAL-2222" ] || { printf '%s: got %s, want REAL-2222\n' "$f" "$out"; false; }
  done
}

@test "class B: a BARE CC_PANE_ID survives the wNtNpN: strip (the trap a grep-widening misses)" {
  # CC_PANE_ID is a SUPERSET that also accepts the bare uuid, which contains no colon. The original
  # sites did `sid="${line##*:}"` on the WHOLE matched line, so on a bare value that yields
  # `CC_PANE_ID=<uuid>` — which every downstream UUID check then rejects. Widening the grep alone
  # would have looked like the fix and changed nothing (memory: lookup-miss-is-not-absence).
  # Stripping `KEY=` BEFORE `##*:` is the load-bearing half.
  local fn out naive
  fn="$BATS_TEST_TMPDIR/bare.fn"
  extract_fn "$REPO/scripts/desk-arm-live.sh" pane_of_env "$fn"
  out="$(CC_TEST_BLOB="CC_PANE_ID=BARE-3333" bash -c '. "$1"; pane_of_env "$CC_TEST_BLOB"' _ "$fn")"
  [ "$out" = "BARE-3333" ] || { printf 'got %s, want BARE-3333\n' "$out"; false; }

  # The pre-fix order, pinned as a CONTROL: it must still produce the WRONG answer, or this case is
  # passing for a free reason and proves nothing about the ordering.
  naive="$(CC_TEST_BLOB="CC_PANE_ID=BARE-3333" bash -c 'v="$CC_TEST_BLOB"; printf "%s" "${v##*:}"')"
  [ "$naive" = "CC_PANE_ID=BARE-3333" ] || { printf 'control drifted: %s\n' "$naive"; false; }
}

@test "class B: teammate-auto-shutdown resolves a CC_PANE_ID-only pane it would otherwise call absent" {
  # The escalation-surface site: _pane_from_env feeds a caller that resolves a pane IN ORDER TO
  # CLOSE IT, and its UUID regex means a miss is SILENT — it answers "no pane" rather than erroring.
  # Pre-fix, a headless/kitty teammate carrying only CC_PANE_ID was exactly that silent miss.
  local fn out
  fn="$BATS_TEST_TMPDIR/tas.fn"
  extract_fn "$REPO/hooks/teammate-auto-shutdown.sh" _pane_from_env "$fn"
  # `ps` is stubbed, so the case exercises the resolution logic and never the process table.
  out="$(bash -c '
    ps() { printf "%s\n" "PWD=/tmp CC_PANE_ID=D0D0D0D0-1111-2222-3333-444455556666"; }
    . "$1"; _pane_from_env 4242' _ "$fn")"
  [ "$out" = "D0D0D0D0-1111-2222-3333-444455556666" ] || { printf 'got [%s]\n' "$out"; false; }
}

@test "class B: cc-teardown's occupancy oracle scores CC_PANE_ID and counts BOTH keys as sighted" {
  # pane_occupants' tri-state turns on `tok` — "did the scan see ANY pane-id token at all". While
  # that control counted only ITERM_SESSION_ID, an all-headless process table measured tok=0 and the
  # oracle returned 2 BLIND forever: a permanent non-verdict that reads like a safety property.
  # Three assertions in one table: preference (pid 111 is claimed by its CC_PANE_ID, NOT nominated
  # by the stale ITERM id beside it), the bare form (333), and the tok control seeing all four.
  # The awk program is EXTRACTED FROM bin/cc-teardown, never retyped here. A copy pasted into the
  # test would keep passing after the subject changed underneath it; extraction makes drift
  # impossible and a moved anchor fail LOUD rather than silently green (memory:
  # control-must-replay-the-real-artifact, absent-range-endpoint-selects-everything).
  local prog="$BATS_TEST_TMPDIR/occ.awk" res
  python3 - "$REPO/bin/cc-teardown" "$prog" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"""awk -v u="\$uuid" '(.*?)' 2>/dev/null\)""", src, re.S)
assert m, "ANCHOR MISSING: pane_occupants' awk program moved — this control is BLIND, not green"
open(sys.argv[2], "w", encoding="utf-8").write(m.group(1))
PY
  [ -s "$prog" ] || { echo "extracted awk program is empty"; false; }

  res="$(printf '%s\n' \
      '111 claude ITERM_SESSION_ID=w0t0p0:AAAA CC_PANE_ID=BBBB' \
      '222 claude ITERM_SESSION_ID=w0t0p0:CCCC' \
      '333 claude CC_PANE_ID=DDDD' \
    | awk -v u="BBBB" -f "$prog")"
  [ "$(printf '%s\n' "$res" | sed -n '1p')" = "tok=4" ] || { printf 'tok wrong:\n%s\n' "$res"; false; }
  [ "$(printf '%s\n' "$res" | sed 1d | tr -d '[:space:]')" = "111" ] || { printf 'pids wrong:\n%s\n' "$res"; false; }
}

@test "address <id> does NOT downgrade an indeterminate enumeration into 'gone'" {
  # The bug this forbids: a blind probe answering "that pane is dead", which a caller then acts
  # on by reaping a live agent. Indeterminate must propagate as indeterminate.
  fake 'exit 1'
  run "$CP" address "AAA"
  [ "$status" -eq 2 ]
}

# ── the enumeration's SIZE, which the two tests above cannot see ───────────────────────────
# Both of those pin this exact contract and both stay GREEN over the defect this guards: measured
# 2026-08-26T21:56Z, all 31 cases passed with drv_iterm2_address carrying `grep -qxF` in a
# pipeline. Two independent reasons, and making the fixture bigger only fixes the first.
#   (1) SCALE. Their lists are one and three ids; the SIGPIPE regime for that two-stage shape
#       starts at 37,121 bytes and is unconditional from 87,122.
#   (2) THE rc IS THE SAME ON BOTH SIDES. The inverted PRESENT case and the correct ABSENT case
#       both return RC_NO. So `address ZZZ` is rc 1 whether the subject is fixed or broken, and
#       the only assertion that discriminates is a PRESENT id at a size past the floor.
# Sized from the measurement rather than from taste: 3,301 ids is ~122 KB of id feed, past the
# always-inverted floor, so a re-introduced `grep -q` fails every run rather than one in twenty.
# THIS ARM IS THE ONLY GUARD ON THAT LINE. pipefail-sigpipe-lint reads the last stage's own exit
# and cannot observe a caller, so a pipeline in `||` position is in neither `--census` nor the
# allowlist (both 0 rows for bin/cc-pane, measured 2026-08-26T21:52Z) — there is no ratchet here
# to catch a revert.
@test "address <id> answers PRESENT for a live pane even when the enumeration is past the SIGPIPE floor" {
  local big="$BATS_TEST_TMPDIR/big-list.json"
  local needle="AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
  # Needle FIRST: grep exits on line 1, leaving the producer the largest possible unwritten
  # remainder, which is the condition that raises SIGPIPE.
  awk -v n="$needle" 'BEGIN{
    printf "[{\"id\":\"%s\"}", n
    for (i = 0; i < 3300; i++) printf ",{\"id\":\"F%011d-FFFF-FFFF-FFFF-FFFFFFFFFFFF\"}", i
    printf "]\n"
  }' > "$big"
  [ -s "$big" ]
  # The fixture must actually contain the needle, matched the way the subject matches it — a
  # whole line of the extracted id list. Without this column a broken generator ships as data.
  [ "$(jq -r '.[].id' "$big" | grep -cxF -e "$needle")" -eq 1 ]
  [ "$(jq -r '.[].id' "$big" | wc -c | tr -d ' ')" -gt 87122 ]

  fake "cat '$big'; exit 0"
  run "$CP" address "$needle"
  [ "$status" -eq 0 ]
  [ "$output" = "$needle" ]

  # NEG control at the SAME size: a genuinely absent id must still be RC_NO, so this arm cannot
  # pass by a subject that has stopped discriminating and always answers 0.
  run "$CP" address "ZZZZZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZZZZZZZZZ"
  [ "$status" -eq 1 ]
  true
}
