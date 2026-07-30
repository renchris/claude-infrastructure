#!/usr/bin/env bats
# bats-shim-parity-lint.bats — proof for row 13's shadow-mode parity check
# (scripts/bats-shim-parity-lint.sh, MACHINE_CAPACITY_V2.md §9.4).
#
# WHAT MUST BE TRUE, and why each is a test rather than a comment:
#   · A machine WITHOUT shadow mode must read NOT-ACTIVE, not a warning. The healthy default is the
#     common case (it is the state of this box), and a lint that cries wolf there gets disabled — at
#     which point it is worth zero on the one day brew restores the symlink.
#   · DRIFT must be rc 1 and LOUD. This is the entire reason the file exists: `brew upgrade
#     bats-core` restores Homebrew's own symlink, nothing breaks, and ~30% of live bats invocations
#     (measured 2026-07-29) silently return to full interactive priority.
#   · "Cannot tell" must never read as "fine" — NO-DATA is its own rc 3, never folded into 0.
#
# PROOF DISCIPLINE (this repo's bar, non-negotiable):
#   · $HOME is FIXTURED. The subject's default seed path is derived from
#     ${CLAUDE_CONFIG_DIR:-$HOME/.claude}, so an unfixtured run would judge — and the parity tests
#     would depend on — the OPERATOR's live state. CLAUDE_CONFIG_DIR is unset for the same reason:
#     on this box it points at ~/.claude-secondary, a live dir.
#   · Non-final `[[ ]]` / `[ ]` are errexit-EXEMPT under bats and therefore DEAD as assertions
#     (memory bats-dead-assertions-errexit-exemptions) — every one here carries `|| false`.
#   · Every ABSENCE assertion has a POSITIVE CONTROL beside it. The two that matter most: the
#     NOT-ACTIVE green is paired with the SAME machine state plus a seed going DRIFT (proving the
#     green is a judgement, not blindness), and the read-only assertion is paired with a canary
#     write proving its find/cksum detector can see one.
#   · Non-vacuity: `[ -f "$LINT" ] || false` guards the greps, and rc≠127 is asserted where a
#     "nothing happened" result would otherwise look like restraint
#     (memory absence-alarm-needs-existence-evidence).
#   · Every seam is driven through `run env …` against FIXTURE dirs. Nothing here touches the real
#     /opt/homebrew, the real seed path, or the real $HOME — the subject is read-only, and this
#     suite must be too, or activating shadow mode would become a side effect of running tests.
#
# RED-PROOF: against a tree without scripts/bats-shim-parity-lint.sh every test fails — the usage
# and verdict tests at rc 127 (file not found, which the assertions distinguish from a verdict), and
# the two grep-based parity tests at their `[ -f "$LINT" ]` guard.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  LINT="$REPO/scripts/bats-shim-parity-lint.sh"
  D="$BATS_TEST_TMPDIR"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # Second hermeticity axis — the AMBIENT environment. Every seam the subject reads comes from the
  # environment, so without this the suite's verdict would silently depend on HOW it was invoked
  # (the exact trap tests/qos-chokepoint.bats:33 records for CC_BATS_ACTIVE). CLAUDE_CONFIG_DIR is
  # in the list because it is SET on this box, to a live directory.
  unset CC_BATS_SEED CC_BATS_SHIM_PATH CC_BATS_EXPECT CC_BATS_PARITY_LINT CLAUDE_CONFIG_DIR

  # Fixture world: a stand-in cc-bats (what the shim path must resolve to), a stand-in real bats
  # (what the seed records), and a Homebrew-ish dir whose `bats` entry we repoint per test.
  mkdir -p "$D/expect" "$D/cellar" "$D/hb"
  printf '#!/bin/bash\necho fixture-cc-bats\n' > "$D/expect/cc-bats"; chmod 755 "$D/expect/cc-bats"
  printf '#!/bin/bash\necho fixture-real-bats\n' > "$D/cellar/bats"; chmod 755 "$D/cellar/bats"
  SEED="$D/seed"
  printf '%s\n' "$D/cellar/bats" > "$SEED"
}

# shim_covered / shim_drifted — the two states brew moves the machine between.
shim_covered() { ln -sfn "$D/expect/cc-bats" "$D/hb/bats"; }
shim_drifted() { ln -sfn "$D/cellar/bats" "$D/hb/bats"; }

# ── usage surface ──────────────────────────────────────────────────────────────────────────────

@test "(i) --help exits 0 and documents every exit code" {
  run /bin/bash "$LINT" --help
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ NOT-ACTIVE ]] || false
  [[ "$output" =~ DRIFT ]] || false
  [[ "$output" =~ STALE-SEED ]] || false
  [[ "$output" =~ NO-DATA ]] || false
}

@test "(ii) an unknown argument exits 64, never silently ignored" {
  run /bin/bash "$LINT" --definitely-not-a-flag
  [ "$status" -eq 64 ] || false
  [[ "$output" =~ "unknown argument" ]] || false
}

# ── the healthy default, and the control that proves it is a judgement ─────────────────────────

@test "(iii) NOT-ACTIVE (rc 0) with no seed — even while the shim path is Homebrew's own binary" {
  [ -f "$LINT" ] || false
  shim_drifted                       # exactly the state a fresh box is in: brew owns the symlink
  run env CC_BATS_SEED="$D/nonexistent-seed" CC_BATS_SHIM_PATH="$D/hb/bats" \
      CC_BATS_EXPECT="$D/expect/cc-bats" /bin/bash "$LINT"
  [ "$status" -eq 0 ] || false
  [ "$status" -ne 127 ] || false      # 127 = the lint never ran; that is not a verdict
  [[ "$output" =~ NOT-ACTIVE ]] || false
  [[ "$output" =~ "HEALTHY default" ]] || false
}

@test "(iv) POSITIVE CONTROL for (iii): the SAME machine state WITH a seed is DRIFT (rc 1)" {
  # Without this, (iii) could be green because the detector is blind to the shim path entirely.
  # Identical fixture, one difference — the activation marker exists.
  shim_drifted
  run env CC_BATS_SEED="$SEED" CC_BATS_SHIM_PATH="$D/hb/bats" \
      CC_BATS_EXPECT="$D/expect/cc-bats" /bin/bash "$LINT"
  [ "$status" -eq 1 ] || false
  [[ "$output" =~ DRIFT ]] || false
}

# ── the four judged verdicts ───────────────────────────────────────────────────────────────────

@test "(v) OK (rc 0) — seed present, shim resolves to cc-bats, seeded target executable" {
  shim_covered
  run env CC_BATS_SEED="$SEED" CC_BATS_SHIM_PATH="$D/hb/bats" \
      CC_BATS_EXPECT="$D/expect/cc-bats" /bin/bash "$LINT"
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ "OK — shadow mode intact" ]] || false
}

@test "(vi) DRIFT (rc 1) names both physical paths and hands back the exact repoint command" {
  # The whole point of the lint. A DRIFT that does not print the fix is a nag, not a silver platter
  # (memory feedback-silver-platter-exact-commands).
  shim_drifted
  run env CC_BATS_SEED="$SEED" CC_BATS_SHIM_PATH="$D/hb/bats" \
      CC_BATS_EXPECT="$D/expect/cc-bats" /bin/bash "$LINT"
  [ "$status" -eq 1 ] || false
  [[ "$output" =~ "brew upgrade bats-core" ]] || false
  # `==` with a glob, not `=~`: the fix line is a PATH, so it must match literally — a regex would
  # let `.` and friends in a tmpdir name match something else and pass for the wrong reason.
  [[ "$output" == *"ln -sfn $D/expect/cc-bats $D/hb/bats"* ]] || false
}

@test "(vii) STALE-SEED (rc 2) when the seeded real bats is MISSING" {
  shim_covered
  printf '%s\n' "$D/cellar/upgraded-away" > "$D/seed-gone"
  run env CC_BATS_SEED="$D/seed-gone" CC_BATS_SHIM_PATH="$D/hb/bats" \
      CC_BATS_EXPECT="$D/expect/cc-bats" /bin/bash "$LINT"
  [ "$status" -eq 2 ] || false
  [[ "$output" =~ STALE-SEED ]] || false
  [[ "$output" =~ missing ]] || false
}

@test "(viii) STALE-SEED (rc 2) when the seeded real bats exists but is NOT EXECUTABLE" {
  # Distinct from (vii): a present-but-chmod-644 target is the shape a partial brew relink leaves,
  # and `[ -e ]` alone would call it fine.
  shim_covered
  printf 'not a binary\n' > "$D/cellar/inert"; chmod 644 "$D/cellar/inert"
  printf '%s\n' "$D/cellar/inert" > "$D/seed-inert"
  run env CC_BATS_SEED="$D/seed-inert" CC_BATS_SHIM_PATH="$D/hb/bats" \
      CC_BATS_EXPECT="$D/expect/cc-bats" /bin/bash "$LINT"
  [ "$status" -eq 2 ] || false
  [[ "$output" =~ not-executable ]] || false
}

@test "(ix) NO-DATA (rc 3) when the judged path is absent entirely — and it says NOT A PASS" {
  run env CC_BATS_SEED="$SEED" CC_BATS_SHIM_PATH="$D/hb/no-such-bats" \
      CC_BATS_EXPECT="$D/expect/cc-bats" /bin/bash "$LINT"
  [ "$status" -eq 3 ] || false
  [[ "$output" =~ NO-DATA ]] || false
  [[ "$output" =~ "not a pass" ]] || false
}

@test "(x) NO-DATA (rc 3) on a DANGLING shim symlink — present but unresolvable" {
  ln -sfn "$D/hb/vanished" "$D/hb/bats"
  run env CC_BATS_SEED="$SEED" CC_BATS_SHIM_PATH="$D/hb/bats" \
      CC_BATS_EXPECT="$D/expect/cc-bats" /bin/bash "$LINT"
  [ "$status" -eq 3 ] || false
  [[ "$output" =~ DANGLING ]] || false
}

@test "(xi) NO-DATA (rc 3) when the seed file is EMPTY — an unreadable recording is not OK" {
  shim_covered
  : > "$D/seed-empty"
  run env CC_BATS_SEED="$D/seed-empty" CC_BATS_SHIM_PATH="$D/hb/bats" \
      CC_BATS_EXPECT="$D/expect/cc-bats" /bin/bash "$LINT"
  [ "$status" -eq 3 ] || false
  [[ "$output" =~ NO-DATA ]] || false
}

@test "(xii) NO-DATA (rc 3) when the expected cc-bats itself is unreadable" {
  # Both sides of a parity claim must be readable before the claim is made; otherwise a missing
  # checkout would be reported as DRIFT and send the operator to repoint a healthy symlink.
  shim_covered
  run env CC_BATS_SEED="$SEED" CC_BATS_SHIM_PATH="$D/hb/bats" \
      CC_BATS_EXPECT="$D/expect/no-such-cc-bats" /bin/bash "$LINT"
  [ "$status" -eq 3 ] || false
  [[ "$output" =~ NO-DATA ]] || false
}

# ── physical-path comparison ───────────────────────────────────────────────────────────────────

@test "(xiii) a symlinked PARENT dir must NOT fabricate DRIFT" {
  # Shadow mode installs a symlink CHAIN and this checkout is reached through symlinked parents, so
  # string equality would report DRIFT on a correct install — the false alarm that gets a lint
  # switched off. Two spellings of ONE physical file must compare equal.
  shim_covered
  ln -sfn "$D/expect" "$D/expect-link"
  run env CC_BATS_SEED="$SEED" CC_BATS_SHIM_PATH="$D/hb/bats" \
      CC_BATS_EXPECT="$D/expect-link/cc-bats" /bin/bash "$LINT"
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ "OK — shadow mode intact" ]] || false
}

@test "(xiv) POSITIVE CONTROL for (xiii): a DIFFERENT physical file still reports DRIFT" {
  # Proves (xiii) passed because the paths are the same FILE, not because the comparison is inert.
  shim_drifted
  ln -sfn "$D/expect" "$D/expect-link"
  run env CC_BATS_SEED="$SEED" CC_BATS_SHIM_PATH="$D/hb/bats" \
      CC_BATS_EXPECT="$D/expect-link/cc-bats" /bin/bash "$LINT"
  [ "$status" -eq 1 ] || false
  [[ "$output" =~ DRIFT ]] || false
}

# ── kill switch ────────────────────────────────────────────────────────────────────────────────

@test "(xv) kill switch CC_BATS_PARITY_LINT=off exits 0 as DISABLED, over a real DRIFT state" {
  shim_drifted
  run env CC_BATS_PARITY_LINT=off CC_BATS_SEED="$SEED" CC_BATS_SHIM_PATH="$D/hb/bats" \
      CC_BATS_EXPECT="$D/expect/cc-bats" /bin/bash "$LINT"
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ DISABLED ]] || false
  # DISABLED must be its own word: reporting "turned off" as NOT-ACTIVE would claim a judgement
  # about the machine that was never made.
  [[ ! "$output" =~ NOT-ACTIVE ]] || false
}

@test "(xvi) POSITIVE CONTROL for (xv): the identical run WITHOUT the kill switch is rc 1" {
  shim_drifted
  run env CC_BATS_SEED="$SEED" CC_BATS_SHIM_PATH="$D/hb/bats" \
      CC_BATS_EXPECT="$D/expect/cc-bats" /bin/bash "$LINT"
  [ "$status" -eq 1 ] || false
}

# ── seams: unset / set-empty / set are THREE states ────────────────────────────────────────────

@test "(xvii) set-but-EMPTY CC_BATS_SEED is honoured verbatim — no fallback to the default path" {
  # Two-sided, because only the pair proves the distinction. A seed sitting at the DEFAULT path is
  # found when the seam is UNSET; the same run with the seam set to EMPTY must report NOT-ACTIVE.
  # `${VAR:-}` cannot express that difference, which is why the subject uses `${VAR+set}`.
  shim_covered
  mkdir -p "$HOME/.claude/state"
  printf '%s\n' "$D/cellar/bats" > "$HOME/.claude/state/cc-bats-real"

  run env CC_BATS_SHIM_PATH="$D/hb/bats" CC_BATS_EXPECT="$D/expect/cc-bats" /bin/bash "$LINT"
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ "OK — shadow mode intact" ]] || false     # unset ⇒ default path IS consulted

  run env CC_BATS_SEED= CC_BATS_SHIM_PATH="$D/hb/bats" CC_BATS_EXPECT="$D/expect/cc-bats" \
      /bin/bash "$LINT" --json
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ \"verdict\":\"NOT-ACTIVE\" ]] || false     # set-empty ⇒ NO fallback
  [[ "$output" =~ \"seed\":\"\" ]] || false
}

@test "(xviii) set-but-EMPTY CC_BATS_SHIM_PATH is honoured verbatim — no Homebrew fallback" {
  # Asserting the emitted shim_path is EMPTY, not merely that rc is 3: a fallback to the real
  # /opt/homebrew/bin/bats could also produce rc 3 on a box without bats installed, and then this
  # test would pass for the wrong reason.
  run env CC_BATS_SEED="$SEED" CC_BATS_SHIM_PATH= CC_BATS_EXPECT="$D/expect/cc-bats" \
      /bin/bash "$LINT" --json
  [ "$status" -eq 3 ] || false
  [[ "$output" =~ \"verdict\":\"NO-DATA\" ]] || false
  [[ "$output" =~ \"shim_path\":\"\" ]] || false
}

@test "(xix) set-but-EMPTY CC_BATS_EXPECT is honoured verbatim — no repo fallback" {
  shim_covered
  run env CC_BATS_SEED="$SEED" CC_BATS_SHIM_PATH="$D/hb/bats" CC_BATS_EXPECT= \
      /bin/bash "$LINT" --json
  [ "$status" -eq 3 ] || false
  [[ "$output" =~ \"verdict\":\"NO-DATA\" ]] || false
  [[ "$output" =~ \"expect\":\"\" ]] || false
}

@test "(xx) the default seed path is \$HOME/.claude — NOT CLAUDE_CONFIG_DIR — matching bin/cc-bats" {
  # DELIBERATELY CHANGED 2026-07-29, not relaxed. This test asserted the seed default was derived
  # from CLAUDE_CONFIG_DIR. That premise was FALSIFIED: the seed records a MACHINE fact (where
  # Homebrew's real bats lives), and this box runs sessions across four config dirs
  # (CLAUDE_CONFIG_DIR=~/.claude-secondary here). A per-account default meant the lint judged a path
  # NOTHING reads — it would report the healthy-looking "NOT-ACTIVE" while shadow mode was live,
  # i.e. the brew-fragility watchdog silently inert, which is the exact failure class it exists to
  # catch. bin/cc-bats:122-127 uses $HOME/.claude; the lint now matches it.
  # Asserted TWO-SIDEDLY: a seed at the $HOME/.claude location IS read, and one placed at a
  # CLAUDE_CONFIG_DIR location is NOT — so a regression to the old behaviour fails here.
  shim_covered
  mkdir -p "$D/home/.claude/state" "$D/cfg/state"
  printf '%s\n' "$D/cellar/bats" > "$D/home/.claude/state/cc-bats-real"
  run env HOME="$D/home" CLAUDE_CONFIG_DIR="$D/cfg" CC_BATS_SHIM_PATH="$D/hb/bats" \
      CC_BATS_EXPECT="$D/expect/cc-bats" /bin/bash "$LINT"
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ "OK — shadow mode intact" ]] || false

  # the negative half: a seed ONLY at the CLAUDE_CONFIG_DIR location must NOT be found
  rm -f "$D/home/.claude/state/cc-bats-real"
  printf '%s\n' "$D/cellar/bats" > "$D/cfg/state/cc-bats-real"
  run env HOME="$D/home" CLAUDE_CONFIG_DIR="$D/cfg" CC_BATS_SHIM_PATH="$D/hb/bats" \
      CC_BATS_EXPECT="$D/expect/cc-bats" /bin/bash "$LINT"
  [[ "$output" =~ "NOT-ACTIVE" ]] || false
}

@test "(xxi) POSITIVE CONTROL for (xx): a CLAUDE_CONFIG_DIR with no seed reads NOT-ACTIVE" {
  # Proves (xx) went green because the seed was FOUND under the config dir, not because the seed
  # check is satisfied by something else in the environment.
  shim_covered
  mkdir -p "$D/cfg-empty/state"
  run env CLAUDE_CONFIG_DIR="$D/cfg-empty" CC_BATS_SHIM_PATH="$D/hb/bats" \
      CC_BATS_EXPECT="$D/expect/cc-bats" /bin/bash "$LINT"
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ NOT-ACTIVE ]] || false
}

# ── output contracts ───────────────────────────────────────────────────────────────────────────

@test "(xxii) --json emits ONE parseable object carrying the verdict and rc" {
  shim_covered
  run env CC_BATS_SEED="$SEED" CC_BATS_SHIM_PATH="$D/hb/bats" \
      CC_BATS_EXPECT="$D/expect/cc-bats" /bin/bash "$LINT" --json
  [ "$status" -eq 0 ] || false
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ] || false
  local parsed
  parsed="$(printf '%s' "$output" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["verdict"], d["rc"], d["seed_present"])')" || false
  [ "$parsed" = "OK 0 True" ] || false
}

@test "(xxiii) --quiet prints nothing but still exits with the verdict code" {
  shim_drifted
  run env CC_BATS_SEED="$SEED" CC_BATS_SHIM_PATH="$D/hb/bats" \
      CC_BATS_EXPECT="$D/expect/cc-bats" /bin/bash "$LINT" --quiet
  [ "$status" -eq 1 ] || false        # the verdict survives the silence
  [ -z "$output" ] || false
}

@test "(xxiv) POSITIVE CONTROL for (xxiii): the identical run without --quiet DOES print" {
  # An empty-output assertion whose subject prints nothing ever is vacuous.
  shim_drifted
  run env CC_BATS_SEED="$SEED" CC_BATS_SHIM_PATH="$D/hb/bats" \
      CC_BATS_EXPECT="$D/expect/cc-bats" /bin/bash "$LINT"
  [ "$status" -eq 1 ] || false
  [ -n "$output" ] || false
}

# ── read-only by construction ──────────────────────────────────────────────────────────────────

@test "(xxv) the lint writes NOTHING under the paths it judges" {
  # It reports a repoint command for a package-manager-owned symlink; it must never run one. And it
  # must not create the state dir either — that would make "shadow mode activated" a side effect of
  # running a check.
  [ -f "$LINT" ] || false
  mkdir -p "$D/ro/state" "$D/ro/hb"
  ln -sfn "$D/expect/cc-bats" "$D/ro/hb/bats"
  printf '%s\n' "$D/cellar/bats" > "$D/ro/state/cc-bats-real"
  local before after
  before="$(find "$D/ro" | sort; find "$D/ro" -type f -exec cksum {} + 2>/dev/null | sort)"
  run env CC_BATS_SEED="$D/ro/state/cc-bats-real" CC_BATS_SHIM_PATH="$D/ro/hb/bats" \
      CC_BATS_EXPECT="$D/expect/cc-bats" /bin/bash "$LINT"
  [ "$status" -eq 0 ] || false        # it RAN (127 would make "wrote nothing" meaningless)
  after="$(find "$D/ro" | sort; find "$D/ro" -type f -exec cksum {} + 2>/dev/null | sort)"
  [ "$before" = "$after" ] || false
}

@test "(xxvi) POSITIVE CONTROL for (xxv): the find/cksum detector can SEE a write" {
  mkdir -p "$D/ro2"
  printf 'a\n' > "$D/ro2/f"
  local before mid after
  before="$(find "$D/ro2" | sort; find "$D/ro2" -type f -exec cksum {} + 2>/dev/null | sort)"
  : > "$D/ro2/canary"                                  # a NEW file must be visible
  mid="$(find "$D/ro2" | sort; find "$D/ro2" -type f -exec cksum {} + 2>/dev/null | sort)"
  [ "$before" != "$mid" ] || false
  printf 'b\n' > "$D/ro2/f"                            # …and so must a CONTENT change
  after="$(find "$D/ro2" | sort; find "$D/ro2" -type f -exec cksum {} + 2>/dev/null | sort)"
  [ "$mid" != "$after" ] || false
}

# ── parity with the subject the lint judges ────────────────────────────────────────────────────

@test "(xxvii) seed-path parity — the lint and bin/cc-bats name the SAME default state file" {
  # A lint that judges a different file than the shim reads is worse than no lint: it reports OK
  # about a path nothing consults. This is the assertion that catches a future rename of the seed.
  [ -f "$LINT" ] || false
  [ -f "$REPO/bin/cc-bats" ] || false
  run grep -c 'state/cc-bats-real' "$REPO/bin/cc-bats"
  [ "$status" -eq 0 ] || false
  [ "$output" -ge 1 ] || false
  run grep -c 'state/cc-bats-real' "$LINT"
  [ "$status" -eq 0 ] || false
  [ "$output" -ge 1 ] || false
}

@test "(xxviii) POSITIVE CONTROL for (xxvii): the parity grep discriminates" {
  # A check whose own grep is broken reports clean forever (memory named-failure-vs-no-verdict).
  printf 'nothing relevant in here\n' > "$D/bait"
  run grep -c 'state/cc-bats-real' "$D/bait"
  [ "$status" -ne 0 ] || false
}
