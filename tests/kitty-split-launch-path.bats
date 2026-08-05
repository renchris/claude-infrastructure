#!/usr/bin/env bats
# bin/kitty-split-launch.sh resolves the kitty binary ABSOLUTELY (item eafe3e78a852).
#
# THE DEFECT. The script invoked a BARE `kitty` at both of its call sites. Hooks and launchd jobs run
# with PATH=/usr/bin:/bin:/usr/sbin:/sbin, which excludes Homebrew — and on this box kitty exists
# ONLY at /opt/homebrew/bin/kitty (asserted below, because that is what makes the red-proof real
# rather than assumed). So the launcher did not exist for exactly the AUTOMATED callers the script
# was written to serve — resume flows, handoff, peer dispatch — while working perfectly from the
# operator's shell. Worst possible polarity: green where a human tests it, dead where it runs.
#
# SAME CLASS AS THE 3h09m NO-OP. bin/cc-kitty-bin exists as the ONE resolver for this exact failure
# (2026-08-01: a hook-issued pane close exited `kitty: command not found` and the pane survived 3h09m
# with its 653 MB claude.exe resident), and its header already claims "so the seventh file cannot
# reintroduce it". This file was the EIGHTH — written after the resolver landed, never wired to it.
# The claim was true of the six it converted and had no mechanism behind it.
#
# WHY THE SECOND CALL SITE GETS ITS OWN TEST. `--self-retire` captures the window id in a subshell
# (`new_id="$(kitty @ …)"`) instead of exec'ing, so it is a SEPARATE invocation. A fix applied only
# to the visible `exec` line would leave every stamped peer dispatch — the whole shape item
# aba6bcbff6de built --self-retire for — still dead under a daemon PATH, and the ad-hoc split it
# does fix is the one nobody was failing on.
#
# THE ENVIRONMENT IS THE FIXTURE. Every daemon-path case runs under `env -i` with an explicitly
# enumerated environment, not an exported var over the inherited one. A test that merely prepends to
# PATH still carries the operator's Homebrew entries underneath, which is the vacuous-pass shape
# this whole class hides in: the subject would resolve kitty by the very route the item says is
# unavailable, and the suite would go green on a tree with no fix at all.
#
# KNOWN ADJACENT GAP, named rather than driven: handoff-fire.sh reaches jq by bare name at 60 sites
# (all guarded by `command -v jq`, so they degrade to the jq-missing branch rather than crashing),
# and jq is Homebrew-only here too. Under a genuinely minimal PATH the LAUNCH now succeeds and the
# STAMP still fails — loudly, via stamp-peer's own artifact check. That is a wider change than this
# item and is filed separately; the --self-retire case below therefore puts a jq-only symlink dir on
# the path so it tests kitty resolution and not jq's.
#
# RED-PROOF, measured against THREE tree states, because the cases do not all discriminate the same
# fault. The subject is always the real file — `git show HEAD:bin/kitty-split-launch.sh` for the
# prior one — never a hand-edited approximation.
#
#   vs. the PRIOR file (bare `kitty`): 4 of the 7 below go red. Both call sites (exit 127, `exec:
#   kitty: not found`), and BOTH pin cases. The second pin red was NOT predicted and is the more
#   interesting half: a broken CC_TERM_KITTY was expected to be harmless because the old script
#   ignored the variable anyway. It is not harmless — ignoring the pin means the old script LAUNCHED,
#   happily, off whatever `kitty` PATH offered ("a broken pin was silently substituted: 31"). That is
#   cc-kitty-bin's stated refusal contract, "the operator pins a binary and gets a different one",
#   violated by a script that never read the pin at all.
#
#   vs. THIS FIX'S OWN FIRST DRAFT (bare `$HOME` in the candidate list): 1 red — the HOME-unset case,
#   and only that one. It is green against BOTH the prior file and the final one, which is precisely
#   what makes it a blast-radius regression test rather than a feature test: it pins that the
#   resolver did not make the script fail in a situation where it used to work.
#
#   Green on every tree BY DESIGN, and only these two: the PREMISE case (which exists to stop this
#   suite going vacuous, so it must not depend on the fix) and the CONTRACT case (the interactive
#   `command -v` resolution, which must not change).

setup() {
  # HERMETIC $HOME (scripts/test-hermeticity-lint.sh rule 1).
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  KSL="$REPO/bin/kitty-split-launch.sh"

  # The two M11 pins. The --self-retire cases reach scripts/handoff-fire.sh, whose capacity_gate()
  # reads LIVE sysctl load and refuses above 2.0/core on a box that sits well above it — an unpinned
  # suite goes red-by-LOAD rather than by its subject (test-hermeticity-lint rule 2, and the DERIVED
  # pin-guard ratchet at tests/handoff-fire-capacity-gate.bats:384).
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired"; mkdir -p "$CC_FIRED_DIR"
  PEERWT="$BATS_TEST_TMPDIR/peer-wt"; mkdir -p "$PEERWT"

  # The PATH a hook or launchd job actually gets — no Homebrew, so no kitty. Verbatim from
  # bin/cc-kitty-bin's header, which is where the measurement came from.
  MINPATH="/usr/bin:/bin:/usr/sbin:/sbin"

  KITTY_ARGS_LOG="$BATS_TEST_TMPDIR/kitty-args.log"
  ALT_ARGS_LOG="$BATS_TEST_TMPDIR/alt-args.log"

  # Two DISTINCT kitty shims, each logging to its own file. One shim could never tell "the pin was
  # honored" from "PATH happened to reach the same binary" — the discrimination the pin test needs.
  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  ALT="$BATS_TEST_TMPDIR/alt"; mkdir -p "$ALT"
  mkshim "$SHIM/kitty" "$KITTY_ARGS_LOG"
  mkshim "$ALT/kitty"  "$ALT_ARGS_LOG"

  # jq only — NEVER the whole Homebrew bin, which would put kitty back on the path and make the
  # daemon-PATH cases vacuous. See the adjacent-gap note in the header.
  TOOLS="$BATS_TEST_TMPDIR/tools"; mkdir -p "$TOOLS"
  if command -v jq >/dev/null 2>&1; then ln -sf "$(command -v jq)" "$TOOLS/jq"; fi
}

# mkshim <path> <logfile> — a kitty stand-in that records its argv and prints a window id, exactly
# as `kitty @ launch` does. The log path is BAKED IN rather than read from the environment, because
# `env -i` is the whole point of this suite and an env-read shim would need it re-passed everywhere.
mkshim() {
  { printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "$*" >> %q\n' "$2"
    printf 'printf "%%s\\n" "${KITTY_STUB_ID-31}"\n'
    printf 'exit 0\n'
  } > "$1"
  chmod +x "$1"
}

# daemon_run <path> <pin> [args…] — run the subject the way a hook does: a fully enumerated
# environment, nothing inherited. <pin> becomes CC_TERM_KITTY (pass "" to leave it unset).
daemon_run() {
  local path="$1" pin="$2"; shift 2
  if [ -n "$pin" ]; then
    run env -i HOME="$HOME" PATH="$path" CC_TERM_KITTY="$pin" \
      CC_FIRED_DIR="$CC_FIRED_DIR" CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off \
      /bin/bash "$KSL" "$@"
  else
    run env -i HOME="$HOME" PATH="$path" \
      CC_FIRED_DIR="$CC_FIRED_DIR" CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off \
      /bin/bash "$KSL" "$@"
  fi
}

# ── the fixture's own premise ───────────────────────────────────────────────────────────────────

@test "PREMISE: the daemon PATH really has no kitty (a box where it does makes every case below vacuous)" {
  # Not ceremony. If kitty were installed into /usr/bin on some future box, the unfixed script would
  # find it there and the two red-proofs below would silently stop discriminating — passing on a
  # tree with no fix, which is precisely the vacuous green this repo keeps re-learning.
  run env -i PATH="$MINPATH" /usr/bin/which kitty
  [ "$status" -ne 0 ] || { echo "kitty IS on $MINPATH — the red-proof below is vacuous"; false; }
}

# ── the defect, at both call sites ──────────────────────────────────────────────────────────────

@test "daemon PATH: the DEFAULT launch fires (call site 1 — the bare exec was a no-op for every hook)" {
  daemon_run "$MINPATH" "$SHIM/kitty" --anchor 2 --cwd "$PEERWT" -- claude
  [ "$status" -eq 0 ] || { echo "status=$status out=$output"; false; }
  [ "$output" = "31" ] || { echo "out=$output"; false; }
  # The anchoring contract is the whole reason this script exists — it must survive the resolution.
  grep -q -- "--match window_id:2" "$KITTY_ARGS_LOG" || { cat "$KITTY_ARGS_LOG"; false; }
  grep -q -- "--next-to id:2" "$KITTY_ARGS_LOG" || { cat "$KITTY_ARGS_LOG"; false; }
}

@test "daemon PATH: --self-retire fires AND stamps (call site 2 — fixing only the exec leaves this dead)" {
  if [ ! -e "$TOOLS/jq" ]; then skip "jq not installed — stamp-peer cannot write its artifact"; fi
  daemon_run "$MINPATH:$TOOLS" "$SHIM/kitty" --anchor 2 --cwd "$PEERWT" --self-retire -- claude
  [ "$status" -eq 0 ] || { echo "status=$status out=$output"; false; }
  # The id is the only place the new pane's identity exists; callers chain further splits on it.
  [ "$(printf '%s\n' "$output" | head -1)" = "31" ] || { echo "out=$output"; false; }
  [ -s "$CC_FIRED_DIR/31.json" ] || { echo "no stamp: $output"; false; }
}

@test "daemon PATH: CC_TERM_KITTY is HONORED — the operator's pin wins over whatever is on PATH" {
  # Before this change the script hardcoded the NAME, so an operator pin was silently ignored and
  # PATH always won. Two distinct shims make that observable: the pin names $ALT, PATH offers $SHIM.
  daemon_run "$MINPATH:$SHIM" "$ALT/kitty" --anchor 3 --cwd "$PEERWT" -- claude
  [ "$status" -eq 0 ] || { echo "status=$status out=$output"; false; }
  [ -f "$ALT_ARGS_LOG" ] || { echo "the pinned binary was never invoked"; false; }
  [ ! -f "$KITTY_ARGS_LOG" ] || { echo "PATH beat the pin: $(cat "$KITTY_ARGS_LOG")"; false; }
}

@test "daemon PATH: an unresolvable pin FAILS LOUDLY and launches nothing (never a silent substitute)" {
  # The other polarity of the pin pair, and the one that measured red unexpectedly. cc-kitty-bin
  # REFUSES rather than auto-detecting when CC_TERM_KITTY is set but not executable — "the operator
  # pins a binary and gets a different one" is the failure it is written against. A script that
  # ignores the pin does not merely lose the refusal; it actively performs the substitution, which
  # is what the old file did here (status 0, launched off PATH).
  daemon_run "$MINPATH:$SHIM" "$BATS_TEST_TMPDIR/not-a-kitty" --anchor 5 --cwd "$PEERWT" -- claude
  [ "$status" -ne 0 ] || { echo "a broken pin was silently substituted: $output"; false; }
  [ ! -f "$KITTY_ARGS_LOG" ] || { echo "launched anyway: $(cat "$KITTY_ARGS_LOG")"; false; }
}

@test "the resolver never fails WIDER than itself: HOME unset still launches" {
  # A side-car must fail no wider than the thing it supplements. Bash expands the ENTIRE for-list
  # before the loop body, so a bare \$HOME in the candidate list aborts on the THIRD entry even
  # though the first one exists and resolves — measured, `line 86: HOME: unbound variable`. Before
  # this change the default path never read \$HOME at all, so that would have been a NEW failure
  # mode introduced by the fix. This is the regression test for the fix's own blast radius.
  run env -i PATH="$MINPATH:$SHIM" /bin/bash "$KSL" --anchor 9 --cwd "$PEERWT" -- claude
  [ "$status" -eq 0 ] || { echo "status=$status out=$output"; false; }
  [ "$output" = "31" ] || { echo "out=$output"; false; }
}

# ── CONTRACT PRESERVATION — green on both trees, by design ──────────────────────────────────────

@test "CONTRACT: an unpinned daemon PATH with kitty PRESENT is unchanged (command -v still wins)" {
  # cc-kitty-bin's first candidate is `command -v kitty`, so the ordinary interactive resolution is
  # untouched. This is what keeps the change a resolution fix and not a behaviour change.
  daemon_run "$MINPATH:$SHIM" "" --anchor 4 --cwd "$PEERWT" -- claude
  [ "$status" -eq 0 ] || { echo "status=$status out=$output"; false; }
  [ "$output" = "31" ] || { echo "out=$output"; false; }
  grep -q -- "--match window_id:4" "$KITTY_ARGS_LOG" || { cat "$KITTY_ARGS_LOG"; false; }
}
