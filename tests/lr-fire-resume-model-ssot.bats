#!/usr/bin/env bats
# lr-fire-resume.sh — the OPUS default is RESOLVED, never a constant.
#
# THE DEFECT. `cfg="" model="claude-opus-4-8" effort="max"` was the default, and the opus path never
# overrode it: lr-handoff appended --model only on the fable branch, and the account map sets a model
# only when CC_ACCT_IS_FABLE=1. So EVERY non-fable transplant resumed on Opus 4.8, while
# ~/.claude/model-config.yaml has said `opus_latest: claude-opus-5` since 2026-07-25.
#
# It is the third member of one family, and the worst. The first demoted the reasoning tier
# (`--model fable` hardcoding `--effort high`); this demotes the MODEL GENERATION. All three share
# the property that makes them expensive: nothing in the resumed pane announces which model or
# effort it came up on, and the operator's constraint for a moved session is that it returns at the
# SAME model and effort. A downgrade is therefore silent by construction, and a limit recovery — the
# one path whose whole job is to lose nothing — was the thing doing it.
#
# THE CURE IS ONE COPY OF A PERISHABLE FACT, so the tests below are mostly about the resolver
# refusing to answer from the wrong place. `opus_prior` is literally the id this replaces and sits on
# the NEXT LINE of the SSOT, so an unanchored read re-creates the bug exactly; a same-named key under
# another section must not answer either.
#
# FAIL CLOSED, matching this file's own binary resolution: a resume that cannot name what it is
# resuming ON must not silently pick something else. A fallback constant is precisely what makes a
# stale answer look like a working one — that is how the original survived the Opus 5 flip.
#
# The resolver is extracted with sed, the house idiom for a unit inside a script that would otherwise
# `exec expect` and spawn a TUI.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIRE="$REPO/scripts/limit-recover/lr-fire-resume.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"

  eval "$(sed -n '/^lr_resolve_opus_model() {/,/^}/p' "$FIRE")"
  # Fail LOUD if extraction produced something unsourceable, rather than letting every test blame its
  # own subject.
  command -v lr_resolve_opus_model >/dev/null || { echo "extraction from $FIRE failed" >&2; return 1; }

  export LR_MODEL_CONFIG="$BATS_TEST_TMPDIR/model-config.yaml"
}

# The SSOT's real shape, reproduced from ~/.claude/model-config.yaml rather than invented — including
# opus_prior on the line after opus_latest, which is the whole point, and a trailing comment on a
# sibling key, which is how that file actually annotates.
mk_ssot() {
  cat > "$LR_MODEL_CONFIG" <<'YAML'
# header prose that mentions claude-opus-4-8 in passing
versions:
  # a comment line inside the block
  opus_latest: claude-opus-5
  opus_prior: claude-opus-4-8
  opus_staged: ""
  sonnet_latest: claude-sonnet-5            # LATERAL 2026-06-30
frontier_access:
  active: true
  opus_latest: claude-opus-DECOY
YAML
}

@test "resolves opus_latest from the versions block" {
  mk_ssot
  run lr_resolve_opus_model
  [ "$status" -eq 0 ]
  [ "$output" = "claude-opus-5" ]
}

@test "never answers with opus_prior — the id it replaces, on the very next line" {
  # The discriminating control. An unanchored `grep opus_` or a read that took the LAST match would
  # return claude-opus-4-8 here and re-create the exact bug, while looking like a working resolver.
  mk_ssot
  run lr_resolve_opus_model
  [ "$output" != "claude-opus-4-8" ]
  [ "$output" = "claude-opus-5" ]
}

@test "stops at the end of the versions block: a same-named key elsewhere cannot answer" {
  # THE FIXTURE MUST OMIT versions.opus_latest, or this test proves nothing. With both keys present
  # the versions one is simply found FIRST and the read stops there — measured, removing the
  # block-end guard entirely reddened zero tests against the ordinary fixture. The guard only binds
  # when the scoped lookup MISSES, so that is the case it has to be asked about: here the answer must
  # be "no opus_latest in versions" and never the decoy one section down.
  cat > "$LR_MODEL_CONFIG" <<'YAML'
versions:
  opus_prior: claude-opus-4-8
  sonnet_latest: claude-sonnet-5
frontier_access:
  active: true
  opus_latest: claude-opus-DECOY
YAML
  run lr_resolve_opus_model
  [ "$output" != "claude-opus-DECOY" ] || { echo "answered from outside the versions block"; false; }
  [ "$status" -ne 0 ]
}

@test "a versions block with NO opus_latest fails rather than guessing" {
  cat > "$LR_MODEL_CONFIG" <<'YAML'
versions:
  opus_prior: claude-opus-4-8
  sonnet_latest: claude-sonnet-5
YAML
  run lr_resolve_opus_model
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "an absent SSOT fails rather than falling back to a constant" {
  export LR_MODEL_CONFIG="$BATS_TEST_TMPDIR/no-such-file.yaml"
  run lr_resolve_opus_model
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "a quoted value is unwrapped" {
  cat > "$LR_MODEL_CONFIG" <<'YAML'
versions:
  opus_latest: "claude-opus-5"
YAML
  run lr_resolve_opus_model
  [ "$status" -eq 0 ]
  [ "$output" = "claude-opus-5" ]
}

# ── the SSOT this actually runs against ──────────────────────────────────────────────────────────

@test "against the LIVE model-config, it resolves a current-generation opus id" {
  # Every test above runs on a fixture, which proves the resolver reads YAML and nothing about the
  # file it will read in production. This one reads the real SSOT — and asserts the PROPERTY (a
  # plausible opus id that is not the superseded one) rather than a literal, so a future lateral bump
  # does not redden a healthy resolver. Skips rather than fails where the SSOT is absent: this suite
  # tests lr-fire-resume, not the operator's install.
  live="$HOME/.claude/model-config.yaml"
  [ -f "$live" ] || live="${REAL_HOME:-/Users/$(id -un)}/.claude/model-config.yaml"
  [ -f "$live" ] || skip "no live model-config.yaml to read"
  LR_MODEL_CONFIG="$live" run lr_resolve_opus_model
  [ "$status" -eq 0 ]
  [[ "$output" == claude-opus-* ]] || { echo "not an opus id: $output"; false; }
  [ "$output" != "claude-opus-4-8" ] || { echo "the live SSOT still names the superseded id"; false; }
}

# ── THE WIRING — the half the unit tests above cannot see ────────────────────────────────────────
# Every test above calls the resolver directly, so ALL OF THEM STAY GREEN if the default is restored
# to a constant and the resolver is simply never called. That is the exact mutant this change exists
# to prevent, so it needs a test that fails when the CALL SITE goes away, not when the function does.
#
# The discriminator is the script's own exit taxonomy. Resolution happens after the account case and
# before the config-dir check, so with a fixture $HOME (where the account's config dir does not
# exist) the two outcomes are distinguishable without spawning anything:
#   exit 1 + "cannot resolve"  ⇒ the resolver ran and refused
#   exit 2 + "config dir …"    ⇒ it got PAST resolution
# A restored constant makes the first case return the second, and only these two tests notice.

@test "WIRING: a broken SSOT stops the opus path — no constant to fall back on" {
  cat > "$LR_MODEL_CONFIG" <<'YAML'
versions:
  opus_prior: claude-opus-4-8
YAML
  run bash "$FIRE" next2 "$BATS_TEST_TMPDIR/wt" "sid-0000" --branch feat/x
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot resolve versions.opus_latest"* ]] || { echo "$output"; false; }
  [[ "$output" == *"Refusing to guess"* ]] || { echo "$output"; false; }
}

@test "WIRING CONTROL: a good SSOT gets PAST resolution, failing later and differently" {
  # Without this the test above could pass on a script that exits 1 for any reason at all.
  mk_ssot
  run bash "$FIRE" next2 "$BATS_TEST_TMPDIR/wt" "sid-0000" --branch feat/x
  [ "$status" -ne 1 ]
  [[ "$output" != *"cannot resolve versions.opus_latest"* ]] || { echo "$output"; false; }
}

@test "WIRING: an explicit --model needs no SSOT at all" {
  # Resolution is reached only when nothing has already decided the model, so a caller pinning a
  # generation must not be able to be stopped by an unreadable SSOT.
  export LR_MODEL_CONFIG="$BATS_TEST_TMPDIR/no-such-file.yaml"
  run bash "$FIRE" next2 "$BATS_TEST_TMPDIR/wt" "sid-0000" --model claude-opus-5 --branch feat/x
  [ "$status" -ne 1 ]
  [[ "$output" != *"cannot resolve versions.opus_latest"* ]] || { echo "$output"; false; }
}

@test "WIRING: a fable account decides the model itself, and is likewise SSOT-independent" {
  export LR_MODEL_CONFIG="$BATS_TEST_TMPDIR/no-such-file.yaml"
  run bash "$FIRE" fable2 "$BATS_TEST_TMPDIR/wt" "sid-0000" --branch feat/x
  [ "$status" -ne 1 ]
  [[ "$output" != *"cannot resolve versions.opus_latest"* ]] || { echo "$output"; false; }
}
