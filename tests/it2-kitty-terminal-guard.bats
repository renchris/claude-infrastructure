#!/usr/bin/env bats
# it2-kitty — the translator's own refusal to drive kitty from a pane that is not kitty's.
#
# THE DEFECT THIS PINS (2026-07-31). it2-kitty's only sanity gate was KITTY_LISTEN_ON, which is as
# inherited as every other KITTY_* var: an iTerm2 launched from a kitty pane carries it into every
# pane under it. So when bin/it2-wrapper wrongly diverted, this file happily opened the socket and
# drove a background kitty the operator was not looking at, and `session list` returned rc 0 — which
# is what Claude Code caches availability from. Every teammate spawn then died at USE time.
#
# WHY THE CHECK IS DUPLICATED HERE rather than left to the wrapper: the two halves deploy by
# different mechanisms. ~/.claude/bin/it2 is a COPY refreshed only by install.sh / kitty-setup.sh,
# while ~/.claude/bin/it2-kitty is a SYMLINK that tracks the repo the moment it moves — so a partial
# deploy leaves a stale wrapper diverting into a current translator. The always-fresh half has to be
# able to say no.
#
# Assertions are `[ ]` / `|| false`; `[[ ]]` and `(( ))` are errexit-EXEMPT in bats.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # it2-kitty reads no path under $HOME, but the hermeticity ratchet judges the SUITE, not the
  # subject — an un-fixtured $HOME runs against the operator's live ~/ and, once landed, reds the
  # lint for every subsequent lander (scripts/test-hermeticity-lint.sh).
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  D="$BATS_TEST_TMPDIR/bin"; mkdir -p "$D"
  # it2-kitty resolves cc-in-kitty as its own SIBLING, so the pair has to be copied together.
  cp "$REPO/bin/it2-kitty" "$D/it2-kitty"; chmod +x "$D/it2-kitty"
  K="$D/it2-kitty"

  # A stand-in kitty that RECORDS being called — "did not touch kitty" is the assertion that a
  # refusal has to make, and an exit code alone cannot make it.
  TOUCHED="$BATS_TEST_TMPDIR/kitty-was-driven"
  KB="$BATS_TEST_TMPDIR/fake-kitty"
  { printf '#!/bin/bash\n'
    printf 'printf "%%s\\n" "$*" >> "%s"\n' "$TOUCHED"
    printf 'case "$*" in *launch*) printf "42\\n" ;; esac\n'
    printf 'exit 0\n'; } > "$KB"
  chmod +x "$KB"
  export CC_TERM_KITTY="$KB"
  export KITTY_LISTEN_ON="unix:/tmp/kitty-test"
  unset CC_TERM_KITTY_TO
  # …and the variables the subject puts on every pane it launches, inherited by every descendant of
  # a fired pane — bats included, when an agent runs this from the pane that fired it (0588d255).
  # In setup, not per-test: a per-test unset leaves every OTHER test inheriting.
  unset CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE
}

# $1 = exit code the stub verdict returns; "none" omits it entirely.
verdict() {
  rm -f "$D/cc-in-kitty"
  if [ "$1" != "none" ]; then
    { printf '#!/bin/bash\n'; printf '[ "${1:-}" = --why ] && printf "stub says not kitty\\n"\n'
      printf 'exit %s\n' "$1"; } > "$D/cc-in-kitty"
    chmod +x "$D/cc-in-kitty"
  fi
}

@test "REGRESSION ANCHOR: refuses (rc 3) when the pane is not kitty's, and does not touch kitty" {
  # KITTY_LISTEN_ON is set here on purpose — it was the ONLY gate, and it passes. If the socket
  # check ever becomes the gate again, this goes red.
  verdict 1
  run "$K" session split -v -s E5D77446-2AE5-4463-929A-7ACBCD97018E
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ ! -e "$TOUCHED" ] || { echo "kitty was driven anyway: $(cat "$TOUCHED")"; false; }
}

@test "the refusal names the consequence, not just the verdict" {
  verdict 1
  run "$K" session list
  [ "$status" -eq 3 ]
  echo "$output" | grep -q 'not kitty' || { echo "$output"; false; }
  echo "$output" | grep -qi 'window you are not looking at' || { echo "$output"; false; }
}

@test "an UNVERIFIABLE terminal (rc 2) also refuses — fail-closed" {
  verdict 2
  run "$K" session list
  [ "$status" -eq 3 ]
  [ ! -e "$TOUCHED" ] || { echo "kitty was driven on an unverifiable terminal"; false; }
}

@test "positive control: a verified kitty pane proceeds and really splits" {
  # Without this, every assertion above could be satisfied by a translator that refuses everything.
  verdict 0
  run "$K" session split -v -s 11
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # The exact line ITermBackend regexes out of our stdout.
  echo "$output" | grep -q '^Created new pane: 42$' || { echo "$output"; false; }
  grep -q 'launch' "$TOUCHED" || { echo "kitty was never driven"; false; }
}

@test "CC_TERM_KITTY_TO bypasses the ancestry gate — naming a socket IS the intent" {
  verdict 1
  export CC_TERM_KITTY_TO="unix:/tmp/kitty-explicit"
  run "$K" session split -v -s 11
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -q '^Created new pane: 42$' || { echo "$output"; false; }
}

@test "cc-in-kitty absent: the translator still runs — the wrapper is the primary gate" {
  # Deliberate, not an oversight. The wrapper refuses to DIVERT without a verifier, so reaching here
  # without one means a direct invocation, which is the pre-existing (and operator-driven) path.
  verdict none
  run "$K" session split -v -s 11
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# ── the rejection has to name its own cause ──────────────────────────────────────────────────────

@test "an iTerm2 UUID is rejected with the CAUSE, not just 'not a kitty window id'" {
  # `not a kitty window id: 'E5D77446-…'` was the entire diagnostic an operator got while every
  # teammate spawn failed, and it points at the id — the one innocent party in the whole chain.
  verdict 0
  run "$K" session split -v -s E5D77446-2AE5-4463-929A-7ACBCD97018E
  [ "$status" -eq 65 ] || { echo "$output"; false; }
  echo "$output" | grep -q 'iTerm2 session UUID' || { echo "$output"; false; }
  echo "$output" | grep -qi 'inherited' || { echo "$output"; false; }
  echo "$output" | grep -q 'kitty-setup.sh' || { echo "$output"; false; }
  [ ! -e "$TOUCHED" ] || { echo "a rejected id still reached kitty"; false; }
}

@test "close/send/run reject a UUID too — a wrong id must never reach a live pane" {
  verdict 0
  for verb in close send run; do
    run "$K" session "$verb" -f -s E5D77446-2AE5-4463-929A-7ACBCD97018E
    [ "$status" -eq 65 ] || { echo "verb $verb: status $status"; echo "$output"; false; }
  done
  [ ! -e "$TOUCHED" ] || { echo "a rejected id still reached kitty: $(cat "$TOUCHED")"; false; }
}
