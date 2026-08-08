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
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. handoff-fire.sh's
  # capacity_gate reads the box's live loadavg AND (M10) its memory headroom, exiting 9 when either is
  # past its bar, so an unpinned suite goes RED purely because the box is busy — the corpus deciding a
  # verdict on machine state instead of on the tree. Both terms are pinned off here (they are the two
  # TERMS of one exit 9, handoff-fire.sh:4487); tests/handoff-fire-capacity-gate.bats is the ONE place
  # the gate runs ON, against synthetic inputs.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
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
  # CC_TERM is the THIRD spelling (2026-08-05): the gate grew a second arm honouring cc-in-kitty's
  # documented override, so an ambient CC_TERM=kitty would divert even with KITTY_WINDOW_ID unset —
  # and "outside kitty the divert is inert" below is the test it would silently turn red, in exactly
  # the environment-dependent way this block exists to stop. Tests that want it set export it.
  unset KITTY_WINDOW_ID CC_TERM
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
# divert's states; the wrapper's own `setup` pins it OFF, so each one opts back in explicitly.
#
# KITTY_WINDOW_ID IS NOT WHAT DECIDES THIS, and these tests used to say it was. It is an ordinary
# exported env var: an iTerm2.app launched from a kitty pane hands it to every iTerm2 pane under it
# forever, so on 2026-07-31 the wrapper diverted inside genuine iTerm2 panes and every Agent Teams
# spawn died at USE time while `session list` stayed green. bin/cc-in-kitty now answers the question
# by ancestry; the wrapper's job — and all this file asserts — is to ASK it and obey.

# A stand-in translator and a stand-in verdict, so the divert is proven WITHOUT needing a live kitty.
# $1 is the exit code cc-in-kitty returns: 0 = genuinely kitty, 1 = inherited vars only, 2 = cannot
# tell. Passing "none" omits the helper entirely (the stale/partial-deploy state).
fake_kitty_translator() {
  KDIR="$BATS_TEST_TMPDIR/bin"; mkdir -p "$KDIR"
  cp "$W" "$KDIR/it2-wrapper"
  { printf '#!/bin/bash\n'; printf 'printf "KITTYPATH:%%s\\n" "$*"; exit 0\n'; } > "$KDIR/it2-kitty"
  chmod +x "$KDIR/it2-kitty"
  rm -f "$KDIR/cc-in-kitty"
  if [ "${1:-0}" != "none" ]; then
    { printf '#!/bin/bash\n'; printf 'exit %s\n' "${1:-0}"; } > "$KDIR/cc-in-kitty"
    chmod +x "$KDIR/cc-in-kitty"
  fi
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

@test "REGRESSION ANCHOR: an iTerm2 pane that INHERITED KITTY_WINDOW_ID must NOT divert" {
  # The exact 2026-07-31 state. Under the old predicate this diverted, `session list` returned rc 0
  # from a background kitty, Claude Code cached the backend as AVAILABLE, and every teammate spawn
  # then died on `not a kitty window id` with no fallback. KITTY_WINDOW_ID is set here on purpose:
  # if the wrapper ever goes back to reading it directly, this test is what goes red.
  fake_kitty_translator 1
  fake 'printf "ITERM2PATH:%s\n" "$*"; exit 0'
  unset IT2_WRAPPER_NO_KITTY
  export KITTY_WINDOW_ID=11
  run "$KDIR/it2-wrapper" session split -v -s E5D77446-2AE5-4463-929A-7ACBCD97018E
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'ITERM2PATH')" -eq 1 ] || { echo "$output"; false; }
  [ "$(printf '%s' "$output" | grep -c 'KITTYPATH')" -eq 0 ] || { echo "$output"; false; }
}

@test "an UNVERIFIABLE terminal (rc 2) is treated as not-kitty, not as kitty" {
  # rc 2 means cc-in-kitty could not walk the tree. Fail-closed: the iTerm2 path is the one that is
  # correct in the common polluted case, and on a real kitty box the real it2 fails loudly instead.
  fake_kitty_translator 2
  fake 'printf "ITERM2PATH:%s\n" "$*"; exit 0'
  unset IT2_WRAPPER_NO_KITTY
  export KITTY_WINDOW_ID=7
  run "$KDIR/it2-wrapper" session list
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'KITTYPATH')" -eq 0 ] || { echo "$output"; false; }
}

@test "cc-in-kitty MISSING: falls back to iTerm2 and says so — never a silent terminal choice" {
  # ~/.claude/bin/it2 is a COPY and cc-in-kitty a SYMLINK, so a partial deploy really can land a
  # wrapper whose verifier is absent. Guessing either way would be the original defect; the wrapper
  # takes the pre-divert path and names the missing file.
  fake_kitty_translator none
  fake 'printf "ITERM2PATH:%s\n" "$*"; exit 0'
  unset IT2_WRAPPER_NO_KITTY
  export KITTY_WINDOW_ID=7
  run "$KDIR/it2-wrapper" session list
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'KITTYPATH')" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s' "$output" | grep -c 'ITERM2PATH')" -eq 1 ] || { echo "$output"; false; }
  echo "$output" | grep -q 'cannot verify the terminal' || { echo "$output"; false; }
}

# ── the CC_TERM seam: the caller that has NO terminal env at all (2026-08-05) ─────────────────────
# bin/cc-in-kitty:51 documents CC_TERM as "honored verbatim ahead of every check", and the callers
# that set it are exactly the ones with nothing to infer from — a launchd job, the desk dispatcher,
# a detached watcher or Stop hook resolve the verdict where the ancestry walk is still valid and
# hand the ANSWER down (handoff-fire.sh's pin_term_verdict_for_watcher, teammate-auto-shutdown.sh's
# pin_term_verdict). None of them carries a KITTY_* var, so the gate's first clause short-circuited
# ABOVE the line that consults cc-in-kitty and silently vetoed the documented seam: measured on one
# env 2026-08-05, the verifier answered rc 0 "CC_TERM=kitty — explicit override" while the shim
# forwarded to the iTerm2 CLI. handoff-fire.sh:3861 routes AROUND this shim for that very reason.
#
# THE VERIFIER IS THE REAL bin/cc-in-kitty here, not a stand-in. What is under test is whether the
# wrapper ASKS it, and a stand-in returning a fixed code cannot show that. Hermetic regardless: with
# CC_TERM set, cc-in-kitty short-circuits at its own line 67 and never walks the process tree.
real_kitty_verifier() {
  fake_kitty_translator none                       # translator + wrapper copy, no stand-in verifier
  cp "$REPO/bin/cc-in-kitty" "$KDIR/cc-in-kitty"
  chmod +x "$KDIR/cc-in-kitty"
}

@test "CC_TERM=kitty with NO KITTY_* diverts — the documented seam, honoured end to end" {
  real_kitty_verifier
  fake 'printf "ITERM2PATH:%s\n" "$*"; exit 0'
  unset IT2_WRAPPER_NO_KITTY KITTY_WINDOW_ID KITTY_PID
  export CC_TERM=kitty
  run "$KDIR/it2-wrapper" session list
  [ "$status" -eq 0 ]
  # Pre-fix this was ITERM2PATH — the whole defect in one line.
  [ "$(printf '%s' "$output" | grep -c 'KITTYPATH')" -eq 1 ] || { echo "$output"; false; }
  [ "$(printf '%s' "$output" | grep -c 'ITERM2PATH')" -eq 0 ] || { echo "$output"; false; }
}

@test "MUTANT CONTROL: the GATE discriminates on '== kitty', not on 'CC_TERM is set'" {
  # The mutant this kills is `-n \"\${CC_TERM:-}\"`, which would divert on ANY non-empty value.
  # It has to be caught AT THE GATE, so the verifier here is a stand-in that says kitty
  # UNCONDITIONALLY: against the real cc-in-kitty this mutant is invisible, because cc-in-kitty's
  # own CC_TERM check refuses second and the observable behaviour is identical. Stripping that
  # second line of defence is what makes the control able to FAIL.
  fake_kitty_translator 0                          # "yes, kitty" no matter what it is asked
  fake 'printf "ITERM2PATH:%s\n" "$*"; exit 0'
  unset IT2_WRAPPER_NO_KITTY KITTY_WINDOW_ID KITTY_PID
  export CC_TERM=iterm2
  run "$KDIR/it2-wrapper" session list
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'KITTYPATH')" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s' "$output" | grep -c 'ITERM2PATH')" -eq 1 ] || { echo "$output"; false; }
}

@test "MUTANT CONTROL, end to end: CC_TERM=iterm2 with no KITTY_* still reaches the iTerm2 CLI" {
  # Same claim through the REAL verifier — the production shape. The test above pins the gate; this
  # one pins that gate and verifier agree, so neither can be quietly carrying the other.
  real_kitty_verifier
  fake 'printf "ITERM2PATH:%s\n" "$*"; exit 0'
  unset IT2_WRAPPER_NO_KITTY KITTY_WINDOW_ID KITTY_PID
  export CC_TERM=iterm2
  run "$KDIR/it2-wrapper" session list
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'KITTYPATH')" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s' "$output" | grep -c 'ITERM2PATH')" -eq 1 ] || { echo "$output"; false; }
}

@test "the A/B kill switch governs the CC_TERM arm too — it is repeated on it, not hoisted" {
  # IT2_WRAPPER_NO_KITTY=1 must restore the iTerm2 path from EVERY arm. The kill switch is repeated
  # rather than factored out of both because two suites pin the first clause as normalised text
  # (tests/kitty-divert-real-it2.bats, tests/handoff-fire-kitty.bats); this asserts the duplicated
  # copy actually works, so the reason for the duplication cannot outlive its effect.
  real_kitty_verifier
  fake 'printf "ITERM2PATH:%s\n" "$*"; exit 0'
  unset KITTY_WINDOW_ID KITTY_PID
  export CC_TERM=kitty IT2_WRAPPER_NO_KITTY=1
  run "$KDIR/it2-wrapper" session list
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'KITTYPATH')" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s' "$output" | grep -c 'ITERM2PATH')" -eq 1 ] || { echo "$output"; false; }
}

@test "no CC_TERM and no KITTY_* is UNCHANGED — the new arm adds no default divert" {
  # The blast-radius pin. Differencing a 48-row env matrix pre/post fix changed exactly 3 rows, all
  # of them CC_TERM=kitty with the switch off; this holds the untouched majority to that.
  real_kitty_verifier
  fake 'printf "ITERM2PATH:%s\n" "$*"; exit 0'
  unset IT2_WRAPPER_NO_KITTY KITTY_WINDOW_ID KITTY_PID CC_TERM
  run "$KDIR/it2-wrapper" session list
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'ITERM2PATH')" -eq 1 ] || { echo "$output"; false; }
}
