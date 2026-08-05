#!/usr/bin/env bats
# bin/kitty-split-launch.sh --self-retire + handoff-fire.sh `stamp-peer` (item aba6bcbff6de).
#
# THE INCIDENT THAT IS THE SPEC (2026-08-05). A peer was dispatched into
# ~/Development/.worktrees/wt-handoff-kitty-daemon by bin/kitty-split-launch.sh, landed its work as
# 4353c85f, and then could not retire. `--session-id $KITTY_WINDOW_ID` cleared the IDENTITY gate and
# hit a second, independent one immediately behind it:
#     !! self-close REFUSED: this is an ORIGIN session, not a fired peer.
#     !!   pane 28 has no fired-peer stamp at ~/.claude/cc-fired/28.json
# The denominator refutes the obvious reading: cc-fired held 25 numeric (kitty-window-keyed) stamps
# beside 307 UUID (iTerm2-keyed) ones, so the fire path demonstrably CAN stamp a kitty pane and
# "kitty panes are never stamped" is false. Pane 28's stamp was absent SPECIFICALLY, and so was its
# cc-registry row — and both are written in the same block of handoff-fire's fire path.
#
# The cause, from ~/.claude/logs/bash-commands.log:279124: pane 28 was never fired by handoff-fire at
# all. It was opened by bin/kitty-split-launch.sh, a pure geometry/anchoring helper with no stamping
# and no registration path — so the pane was invisible to cc-fired, cc-registry and cc-reaper alike.
# Not "never written for this dispatch shape", but never written because the dispatch never went
# through the writer.
#
# Isolation: `kitty` is PATH-shimmed (nothing real is launched), HOME and CC_FIRED_DIR are
# redirected. The end-to-end test drives the REAL origin gate, because the property that matters is
# not "a file appeared" but "the pane this stamp describes can now retire".
#
# RED-PROOF: 9 of the 11 below go red against a `git archive` of the tree without this change. The
# two that do not are the CONTRACT-PRESERVATION pair — "no --self-retire" — asserting that the
# default path is byte-for-byte what it was, which is the property that keeps this opt-in.
# One of them had to be tightened to earn its red: "a --cwd that is not a directory is REFUSED"
# originally asserted only exit 1 + no stamp file, and BOTH are true on a tree with no `stamp-peer`
# subcommand at all (the argument falls through to the ordinary fire path, which also exits 1 and
# writes nothing). It passed on the unfixed tree and proved nothing until it asserted the specific
# refusal text.

setup() {
  # HERMETIC $HOME (scripts/test-hermeticity-lint.sh): the subjects resolve state under ~.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  KSL="$REPO/bin/kitty-split-launch.sh"
  HF="$REPO/scripts/handoff-fire.sh"

  # The two M11 pins. handoff-fire's capacity_gate() refuses a net-new fire above 2.0/core and this
  # box lives well above that, so an unpinned suite goes red-by-LOAD rather than by its subject.
  # Both are required: scripts/test-hermeticity-lint.sh checks the first, and the DERIVED pin-guard
  # ratchet (tests/handoff-fire-capacity-gate.bats:384) fails any new fire-executing suite missing
  # either. Pinned rather than grandfathered — both guards say never widen that list.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired"; mkdir -p "$CC_FIRED_DIR"
  PEERWT="$BATS_TEST_TMPDIR/peer-wt"; mkdir -p "$PEERWT"

  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  export KITTY_ARGS_LOG="$BATS_TEST_TMPDIR/kitty-args.log"
  # kitty shim: records argv and prints a window id, exactly as `kitty @ launch` does.
  cat > "$SHIM/kitty" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$KITTY_ARGS_LOG"
printf '%s\n' "${KITTY_STUB_ID-31}"
exit 0
SH
  chmod +x "$SHIM/kitty"
  export PATH="$SHIM:$PATH"
}

# ── the flag is OPT-IN: the default path must be untouched ──────────────────────────────────────

@test "no --self-retire: stdout is the window id and NO stamp is written (ad-hoc splits stay unstamped)" {
  run bash "$KSL" --anchor 2 --cwd "$PEERWT" -- claude
  [ "$status" -eq 0 ]
  [ "$output" = "31" ]
  # The stamp is a CAPABILITY — its presence licenses cc-reaper to auto-reap the pane. A blanket
  # stamp here would hand every ad-hoc split, including one a human is sitting in, to the reaper.
  [ -z "$(ls -A "$CC_FIRED_DIR")" ]
}

@test "no --self-retire: the anchored-split contract is unchanged (--match + --next-to)" {
  run bash "$KSL" --anchor 7 --location hsplit --cwd "$PEERWT" --title T -- claude
  [ "$status" -eq 0 ]
  grep -q -- "--match window_id:7" "$KITTY_ARGS_LOG"
  grep -q -- "--next-to id:7" "$KITTY_ARGS_LOG"
  grep -q -- "--location=hsplit" "$KITTY_ARGS_LOG"
}

@test "--self-retire without --cwd is REFUSED, and nothing is launched" {
  run bash "$KSL" --anchor 2 --self-retire -- claude
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires --cwd"* ]] || false
  # Defaulting to \$PWD would stamp the DISPATCHER's directory as the peer's, and the origin gate
  # binds tenancy on exactly that field — the peer would then be refused as a stale tenant of a
  # worktree it never ran in, i.e. the original bug wearing a stamp. So it refuses instead.
  [ ! -f "$KITTY_ARGS_LOG" ]
}

# ── the stamp ───────────────────────────────────────────────────────────────────────────────────

@test "--self-retire stamps the NEW pane and still prints the window id verbatim" {
  run bash "$KSL" --anchor 2 --cwd "$PEERWT" --self-retire -- claude
  [ "$status" -eq 0 ]
  # The id is the only place the new pane's identity exists, and callers chain further splits on it.
  [ "$(printf '%s\n' "$output" | head -1)" = "31" ]
  [ -s "$CC_FIRED_DIR/31.json" ]
  [ "$(jq -r '.selfRetire'  "$CC_FIRED_DIR/31.json")" = "true" ]
  [ "$(jq -r '.originClass' "$CC_FIRED_DIR/31.json")" = "fired-peer" ]
  [ "$(jq -r '.firedBy'     "$CC_FIRED_DIR/31.json")" = "2" ]
  [ "$(jq -r '.cwd'         "$CC_FIRED_DIR/31.json")" = "$PEERWT" ]
}

@test "--self-retire: an unnameable pane is LOUD but never fatal to the launch" {
  # A pane may well have been created; what failed is our ability to NAME it, and an unnamed pane
  # cannot be stamped. Killing the caller over its own bookkeeping would be the worse trade.
  KITTY_STUB_ID="" run bash "$KSL" --anchor 2 --cwd "$PEERWT" --self-retire -- claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not stamp"* ]] || false
  [ -z "$(ls -A "$CC_FIRED_DIR")" ]
}

# ── stamp-peer: ONE writer for the format ───────────────────────────────────────────────────────
# The obvious fix — teach the other launcher to write the JSON itself — mints a SECOND writer of a
# format whose only consumer contract is "additive-only; cc-reaper keys auto-reap on presence +
# selfRetire". Two writers of one format drift, silently, until a reaper decision goes wrong.

@test "stamp-peer: --cwd is REQUIRED (an unvalidatable stamp is the bug wearing a stamp)" {
  run bash "$HF" stamp-peer --pane 28
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs --cwd"* ]] || false
  [ ! -f "$CC_FIRED_DIR/28.json" ]
}

@test "stamp-peer: a --cwd that is not a directory is REFUSED" {
  run bash "$HF" stamp-peer --pane 28 --cwd "$BATS_TEST_TMPDIR/no-such-dir"
  [ "$status" -eq 1 ]
  # Assert the SPECIFIC refusal, not just a nonzero exit and an absent file. Against a tree with no
  # `stamp-peer` subcommand at all those two facts are also true — the argument falls through to the
  # ordinary fire path, which exits 1 and writes no stamp — so the loose form passed on the unfixed
  # tree and proved nothing. A control must be able to fail the same way the subject does.
  [[ "$output" == *"is not a directory"* ]] || false
  [ ! -f "$CC_FIRED_DIR/28.json" ]
}

@test "stamp-peer: --pane is REQUIRED" {
  run bash "$HF" stamp-peer --cwd "$PEERWT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs --pane"* ]] || false
}

@test "stamp-peer: FAILS LOUDLY when the stamp could not be written" {
  # mark_fired_peer is best-effort by contract — it returns 0 even when jq is missing or the write
  # fails, because a FIRE must never die on its own bookkeeping. A caller that ASKED for a stamp is
  # in the opposite position: a silent no-op here re-creates the unretirable pane this fixes.
  chmod 500 "$CC_FIRED_DIR"
  run bash "$HF" stamp-peer --pane 28 --cwd "$PEERWT"
  chmod 700 "$CC_FIRED_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no stamp written"* ]] || false
}

# ── END-TO-END: the property the item actually asked for ────────────────────────────────────────

@test "END-TO-END: a stamped peer CLEARS the origin gate from its own cwd (pane 28's exact failure)" {
  run bash "$HF" stamp-peer --pane 28 --cwd "$PEERWT" --by 2
  [ "$status" -eq 0 ]
  cd "$PEERWT"
  run bash "$HF" self-close --terminal --session-id 28 --dry-run
  # It may still stop at a LATER gate (dirty tree, registry); it must NOT stop at the provenance one.
  [ "$(echo "$output" | grep -ciE "ORIGIN session|DIFFERENT session")" -eq 0 ]
}

@test "END-TO-END: the same stamp does NOT authorise a close from a DIFFERENT cwd" {
  # The other polarity, in one pair with the test above: the stamp must license the pane it
  # describes and no other. Kitty reuses small integer window ids across restarts, so a later,
  # unrelated tenant of id 28 must not inherit a self-retiring contract it was never granted.
  run bash "$HF" stamp-peer --pane 28 --cwd "$PEERWT" --by 2
  [ "$status" -eq 0 ]
  OTHER="$BATS_TEST_TMPDIR/a-different-worktree"; mkdir -p "$OTHER"; cd "$OTHER"
  run bash "$HF" self-close --terminal --session-id 28 --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"DIFFERENT session"* ]] || false
}
