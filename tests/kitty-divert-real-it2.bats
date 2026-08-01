#!/usr/bin/env bats
# The REAL_IT2 bypass, and why it INVERTS under kitty.
#
# Two files deliberately resolve the RAW it2 binary instead of ~/.claude/bin/it2, for one reason:
# the shim injects `-p Claude-Teammate` on every `session split` (the teammate never-prompt profile),
# and a HANDOFF split wants the firing pane's OWN profile — the ⌘D "same profile" experience.
#
#   scripts/handoff-fire.sh  the REAL_IT2= block   → used by it2_split, the DEFAULT fire path
#   bin/cc-pane              it2_real_bin()        → used by `spawn --inherit-profile`
#
# Inside kitty that reasoning inverts. The profile injection sits BELOW the shim's terminal dispatch
# (bin/it2-wrapper:75), so within kitty the shim execs bin/it2-kitty and the flag is never added:
# the shim already IS the profile-neutral binary. Bypassing it therefore buys nothing and costs
# everything — it resolves an iTerm2 Python-API client which, from inside kitty, has no iTerm2 to
# talk to and exits 2 ("Not running inside iTerm2"). Since it2_split is the default fire path
# (handoff-fire.sh:3922 — it2py only saves/restores focus around it), that single resolution decided
# whether handoff fired at all on kitty. cc-pane's was the KNOWN GAP named in 171673df.
#
# THE DRIFT RISK THIS SUITE EXISTS FOR: the predicate is now written in THREE files. If they ever
# disagree about which terminal this is, a handoff would split the pane with one binary and address
# it with another — so the last test pins that they agree, textually.
#
# Every assertion is `[ ]` or `… || false` — `[[ ]]` and `(( ))` are errexit-EXEMPT in bats and are
# silently DEAD anywhere but a body's last line (memory: bats-dead-assertions-errexit-exemptions).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  CP="$REPO/bin/cc-pane"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"
  # A stand-in shim carrying the anchored REAL_IT2= line both files scrape, plus a real, EXECUTABLE
  # target — the resolution requires -x, so a non-existent path would degrade to the shim and the
  # iTerm2-side assertions would pass vacuously.
  FAKE_REAL="$BATS_TEST_TMPDIR/real-it2"; printf '#!/bin/sh\nexit 0\n' > "$FAKE_REAL"; chmod +x "$FAKE_REAL"
  SHIM="$HOME/.claude/bin/it2"
  printf 'REAL_IT2="%s"\n' "$FAKE_REAL" > "$SHIM"; chmod +x "$SHIM"
  unset KITTY_WINDOW_ID IT2_WRAPPER_NO_KITTY IT2_BIN CC_PANE_IT2
}

# Sourcing either file whole is not an option (top-level side effects, and handoff-fire.sh FIRES
# SESSIONS). Extract just the resolution, exactly as the sibling handoff-fire suites do.
# `|| true`: the block's LAST line is `[ -n "${IT2_BIN:-}" ] && REAL_IT2=…`, which is legitimately
# FALSE whenever the test seam is unset — so the eval returns non-zero and bats' errexit would fail
# the test for a reason that has nothing to do with the property under test. Guarded here rather
# than in the subject, because that trailing `&&` is the subject's real (and correct) shape.
load_hf_block() { eval "$(sed -n '/^IT2_SHIM=/,/# test seam (same convention as cc-sessions)/p' "$HF")" || true; }
load_cp_fn()    { eval "$(sed -n '/^it2_bin() {/,/^}/p' "$CP")"; eval "$(sed -n '/^it2_real_bin() {/,/^}/p' "$CP")"; }

# ── handoff-fire.sh: the default fire path ───────────────────────────────────────────────────────

@test "handoff-fire: on iTerm2 the bypass STANDS — the raw binary wins (unchanged behaviour)" {
  load_hf_block
  [ "$REAL_IT2" = "$FAKE_REAL" ]
}

@test "handoff-fire: inside kitty the bypass INVERTS — the shim wins, so the divert can fire" {
  export KITTY_WINDOW_ID=25
  load_hf_block
  # Pre-fix this was $FAKE_REAL: the real iTerm2 client, forked from inside kitty, exit 2.
  [ "$REAL_IT2" = "$SHIM" ]
}

@test "handoff-fire: IT2_WRAPPER_NO_KITTY=1 restores the iTerm2 path (A/B kill switch honoured)" {
  export KITTY_WINDOW_ID=25 IT2_WRAPPER_NO_KITTY=1
  load_hf_block
  [ "$REAL_IT2" = "$FAKE_REAL" ]
}

@test "handoff-fire: the IT2_BIN test seam still outranks BOTH branches" {
  export KITTY_WINDOW_ID=25 IT2_BIN=/bin/echo
  load_hf_block
  [ "$REAL_IT2" = "/bin/echo" ]
}

# ── cc-pane: spawn --inherit-profile ─────────────────────────────────────────────────────────────

@test "cc-pane: on iTerm2 it2_real_bin resolves the raw binary (unchanged behaviour)" {
  load_cp_fn
  [ "$(it2_real_bin)" = "$FAKE_REAL" ]
}

@test "cc-pane: inside kitty it2_real_bin resolves the SHIM (closes the 171673df known gap)" {
  export KITTY_WINDOW_ID=25
  load_cp_fn
  [ "$(it2_real_bin)" = "$SHIM" ]
}

@test "cc-pane: IT2_WRAPPER_NO_KITTY=1 restores the iTerm2 path" {
  export KITTY_WINDOW_ID=25 IT2_WRAPPER_NO_KITTY=1
  load_cp_fn
  [ "$(it2_real_bin)" = "$FAKE_REAL" ]
}

@test "cc-pane: an UNREADABLE shim still degrades to the shim, not to empty" {
  # Positive control for the guard above: the kitty branch must not be what makes this pass.
  rm -f "$SHIM"
  load_cp_fn
  [ "$(it2_real_bin)" = "$SHIM" ]
}

# ── the three copies must not drift ──────────────────────────────────────────────────────────────

@test "all THREE terminal predicates agree — a split addressed by the wrong binary is the failure" {
  # bin/it2-wrapper is the origin; the other two mirror it. Compared as normalised text so a
  # reworded-but-equivalent copy still counts, and a genuinely different condition does not.
  norm() { grep -ho 'KITTY_WINDOW_ID[^&]*&&*[^]]*IT2_WRAPPER_NO_KITTY' "$1" \
            | head -1 | tr -d '[:space:]"${}:-[]' ; }
  local w h c
  w="$(norm "$REPO/bin/it2-wrapper")"
  h="$(norm "$HF")"
  c="$(norm "$CP")"
  [ -n "$w" ]
  [ "$w" = "$h" ]
  [ "$w" = "$c" ]
}
