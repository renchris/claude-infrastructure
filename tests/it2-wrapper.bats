#!/usr/bin/env bats
# it2-wrapper — the single chokepoint every it2 fork in the fleet resolves through
# (cc-sessions, cc-notify, cc-inbox-guard, cc-reconcile, cc-teardown, handoff-fire,
# teammate-auto-shutdown, and Claude Code's own killPane). Interception 3 BOUNDS that
# fork. An unbounded `session list` is what let a congested iTerm2 Python API deadlock
# the entire fleet on 2026-07-25/26: clients piled up 5-8 min apart, load 17, `bats
# tests/` became unrunnable — so no worktree could land the very fix that would end it,
# and finished panes could not even self-retire (self-close and cc-reaper both resolve
# panes through here). Nothing broke that deadlock; it drained by exhausting its callers.
#
# These tests RED-prove the bound against a genuinely hanging CLI, and pin the four
# things a careless bound would break: `monitor` (streams by design), a verbatim
# non-zero exit code, the never-prompt profile injection, and the forced-close leg.
# Every assertion is `[ ]`/`|| false` — `[[ ]]` and `(( ))` are errexit-EXEMPT in bats
# and would be silently DEAD in any but the body's last line (memory:
# bats-dead-assertions-errexit-exemptions).

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  W="$REPO/bin/it2-wrapper"
  FAKE="$BATS_TEST_TMPDIR/fake-it2"
  export IT2_WRAPPER_REAL="$FAKE"
  # PIN THE TERMINAL. Every test below exercises the iTerm2 path, and the wrapper now diverts to
  # bin/it2-kitty when KITTY_WINDOW_ID is set — so without this the suite's verdict depends on which
  # terminal the developer happens to be sitting in. Measured 2026-07-31: run from kitty, 5 of 14
  # failed; from the same shell with the divert pinned off, 14/14 green; baseline HEAD also green.
  # The dependency predates the divert (KITTY_WINDOW_ID was simply never read); the divert only made
  # it observable. Unsetting the real var AND pinning the kill switch covers both spellings.
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
}

# a stand-in for the real it2 CLI; $1 is the body
fake()      { { printf '#!/bin/bash\n'; printf '%s\n' "$1"; } > "$FAKE"; chmod +x "$FAKE"; }
fake_fast() { fake 'printf "ARGS:%s\n" "$*"; exit 0'; }
fake_hang() { fake 'sleep 300'; }

# ── the bound ────────────────────────────────────────────────────────────────────────

@test "RED-proof: a hanging real CLI is BOUNDED, not waited on forever" {
  fake_hang
  export IT2_WRAPPER_TIMEOUT_S=2
  local s e
  s="$(date +%s)"
  run "$W" session list --json
  e="$(( $(date +%s) - s ))"
  [ "$status" -eq 124 ]
  # the pre-fix wrapper `exec`s the real CLI with no bound: this line hung for 300s
  [ "$e" -lt 30 ]
}

@test "a bound-out NAMES itself on stderr — a bare 124 is ambiguous" {
  # 124 collides with an external SIGKILL and with a command-substitution pipe-block;
  # during the incident that ambiguity cost real triage time, so the bound self-attributes.
  fake_hang
  export IT2_WRAPPER_TIMEOUT_S=2
  run "$W" session list --json
  [ "$status" -eq 124 ]
  [[ "$output" == *"it2-wrapper: bounded out after 2s"* ]] || false
}

@test "the bound holds under a launchd-style minimal PATH (no Homebrew)" {
  # The regression guard for the resolver: hooks and launchd jobs run with a PATH that
  # excludes Homebrew, which is exactly where coreutils installs timeout(1). A PATH-only
  # lookup would leave the AUTOMATED callers — the ones that built the pile-up —
  # unbounded while interactive shells stayed safe.
  if [ ! -x /opt/homebrew/bin/timeout ] && [ ! -x /usr/local/bin/timeout ] \
     && [ ! -x /opt/homebrew/bin/gtimeout ] && [ ! -x /usr/local/bin/gtimeout ]; then
    skip "no absolute-path timeout(1) on this host"
  fi
  fake_hang
  run env PATH=/usr/bin:/bin IT2_WRAPPER_REAL="$FAKE" IT2_WRAPPER_TIMEOUT_S=2 "$W" session list
  [ "$status" -eq 124 ]
}

@test "negative control: IT2_WRAPPER_TIMEOUT_BIN set-but-EMPTY disables bounding verbatim" {
  # `${VAR:-}` cannot tell unset from empty; a seam that cannot turn a thing OFF is not a
  # seam (the same defect fixed in cc-inbox-guard, 02c3de8). This proves the OFF switch —
  # and, by contrast with the RED-proof above, that the bound is what produces the 124.
  fake 'sleep 3; printf "unbounded\n"; exit 0'
  export IT2_WRAPPER_TIMEOUT_S=1
  export IT2_WRAPPER_TIMEOUT_BIN=
  run "$W" session list
  [ "$status" -eq 0 ]
  [ "$output" = "unbounded" ]
}

# ── what the bound must NOT break ────────────────────────────────────────────────────

@test "positive control: args reach the real CLI verbatim and rc 0 survives" {
  fake_fast
  run "$W" session list --json
  [ "$status" -eq 0 ]
  [ "$output" = "ARGS:session list --json" ]
}

@test "a real non-zero exit is propagated verbatim, never masked as 124" {
  fake 'exit 3'
  run "$W" session list
  [ "$status" -eq 3 ]
}

@test "monitor is EXEMPT — the one subcommand that streams by design" {
  fake 'sleep 3; printf "streamed\n"; exit 0'
  export IT2_WRAPPER_TIMEOUT_S=1
  run "$W" monitor
  [ "$status" -eq 0 ]
  [ "$output" = "streamed" ]
}

@test "session split still injects the never-prompt Claude-Teammate profile" {
  fake_fast
  run "$W" session split -v -s ABC
  [ "$status" -eq 0 ]
  [ "$output" = "ARGS:session split -p Claude-Teammate -v -s ABC" ]
}

@test "session split is bounded too" {
  fake_hang
  export IT2_WRAPPER_TIMEOUT_S=2
  run "$W" session split -s ABC
  [ "$status" -eq 124 ]
}

@test "a non-forced close falls through to the real CLI, keeping interactive semantics" {
  fake_fast
  run "$W" session close -s ABC
  [ "$status" -eq 0 ]
  [ "$output" = "ARGS:session close -s ABC" ]
}

@test "a forced close with an EMPTY id falls through — never resolves to the active pane" {
  fake_fast
  run "$W" session close -f -s ""
  [ "$status" -eq 0 ]
  [[ "$output" == "ARGS:session close -f -s"* ]] || false
}

# ── the parsed-line contract with handoff-fire.sh ────────────────────────────────────

@test "contract: handoff-fire.sh can still parse REAL_IT2/PYTHON_BIN out of this shim" {
  # handoff-fire.sh treats this file as the SINGLE SOURCE OF TRUTH for the real it2 binary and
  # the interpreter carrying the iterm2 module, reading both with an ANCHORED sed rather than
  # duplicating the paths. So these two lines are a parsed contract, not mere assignments.
  # Writing a seam inline — `REAL_IT2="${IT2_WRAPPER_REAL:-…}"` — still MATCHES that regex and
  # hands handoff-fire the unexpanded, non-executable string `${IT2_WRAPPER_REAL:-…}`, silently
  # degrading handoff splits to this shim (which injects the WRONG, teammate profile) and
  # PYTHON_BIN to bare python3. Caught 2026-07-26 before it shipped; the seams now live on
  # their own lines where this regex cannot see them.
  local r p
  r="$(sed -n 's/^REAL_IT2="\(.*\)"$/\1/p' "$W" | head -1)"
  p="$(sed -n 's/^PYTHON_BIN="\(.*\)"$/\1/p' "$W" | head -1)"
  [ -n "$r" ]
  [ -x "$r" ]
  [ -n "$p" ]
  [ -x "$p" ]
}

@test "contract: handoff-fire.sh still reads this shim with the parse it is written for" {
  # Pin the CONSUMER's regex too. If handoff-fire stops parsing these lines (or changes how),
  # the guarantee above quietly stops applying to anything — a test that only re-checks our own
  # copy of the regex would still pass while the real coupling had moved.
  local hf="$REPO/scripts/handoff-fire.sh"
  [ -f "$hf" ]
  [ "$(grep -cF 's/^REAL_IT2="' "$hf")" -ge 1 ]
  [ "$(grep -cF 's/^PYTHON_BIN="' "$hf")" -ge 1 ]
}

@test "the forced-close python leg is bounded — its 20s RPC guard never covered the connect" {
  export IT2_WRAPPER_PYTHON="$BATS_TEST_TMPDIR/fake-python"
  printf '#!/bin/bash\nsleep 300\n' > "$IT2_WRAPPER_PYTHON"
  chmod +x "$IT2_WRAPPER_PYTHON"
  export IT2_WRAPPER_TIMEOUT_S=2
  run "$W" session close -f -s ABC-123
  [ "$status" -eq 124 ]
}

# ── terminal dispatch: inside kitty this shim must speak kitty, not iTerm2 ────────────────────────
# Claude Code's ITermBackend spawns a PATH-resolved `it2` and never handshakes with iTerm2, so the
# divert is what turns Agent Teams assignee panes into NATIVE KITTY SPLITS. These tests own the
# divert's three states; the wrapper's own `setup` pins it OFF, so each one opts back in explicitly.

# A stand-in translator, so the divert is proven WITHOUT needing a live kitty.
fake_kitty_translator() {
  KDIR="$BATS_TEST_TMPDIR/bin"; mkdir -p "$KDIR"
  cp "$W" "$KDIR/it2-wrapper"
  { printf '#!/bin/bash\n'; printf 'printf "KITTYPATH:%%s\\n" "$*"; exit 0\n'; } > "$KDIR/it2-kitty"
  chmod +x "$KDIR/it2-kitty"
}

@test "inside kitty, the wrapper diverts to it2-kitty instead of the iTerm2 CLI" {
  fake_kitty_translator
  fake 'printf "ITERM2PATH:%s\n" "$*"; exit 0'
  unset IT2_WRAPPER_NO_KITTY
  export KITTY_WINDOW_ID=7
  run "$KDIR/it2-wrapper" session split -v -s 7
  [ "$status" -eq 0 ]
  # Positive control: it reached the translator...
  [ "$(printf '%s' "$output" | grep -c 'KITTYPATH:session split -v -s 7')" -eq 1 ]
  # ...and NEGATIVE control: it must not ALSO have run the iTerm2 CLI. Without this a wrapper that
  # ran both would pass the assertion above while still driving a background iTerm2.
  [ "$(printf '%s' "$output" | grep -c 'ITERM2PATH')" -eq 0 ]
}

@test "IT2_WRAPPER_NO_KITTY=1 forces the iTerm2 path even inside kitty (A/B seam)" {
  fake_kitty_translator
  fake 'printf "ITERM2PATH:%s\n" "$*"; exit 0'
  export KITTY_WINDOW_ID=7 IT2_WRAPPER_NO_KITTY=1
  run "$KDIR/it2-wrapper" session list
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'ITERM2PATH')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'KITTYPATH')" -eq 0 ]
}

@test "outside kitty the divert is inert — the iTerm2 path is untouched" {
  fake_kitty_translator
  fake 'printf "ITERM2PATH:%s\n" "$*"; exit 0'
  unset IT2_WRAPPER_NO_KITTY KITTY_WINDOW_ID
  run "$KDIR/it2-wrapper" session list
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'ITERM2PATH')" -eq 1 ]
}

@test "translator present but NOT executable REFUSES (rc 4) rather than driving iTerm2 from kitty" {
  fake_kitty_translator
  chmod -x "$KDIR/it2-kitty"
  fake 'printf "ITERM2PATH:%s\n" "$*"; exit 0'
  unset IT2_WRAPPER_NO_KITTY
  export KITTY_WINDOW_ID=7
  run "$KDIR/it2-wrapper" session list
  # "present but unusable" is a THIRD state. Falling through would silently drive whatever iTerm2
  # happens to be running — a pane in a window the operator is not even looking at.
  [ "$status" -eq 4 ]
  [ "$(printf '%s' "$output" | grep -c 'ITERM2PATH')" -eq 0 ]
}
