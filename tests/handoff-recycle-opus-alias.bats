#!/usr/bin/env bats
# --recycle --model opus must type the FAMILY ALIAS, never the SSOT's full id.
#
# WHY (measured 2026-09-22). A recycle types its launcher into the pane's EXISTING zsh, and that
# shell runs the claude() body it sourced at birth. The launcher moved to 2.1.280 + Opus 5.5 that
# afternoon, yet 14 live panes still exec'd 2.1.260 — which refuses claude-opus-5-5 BY NAME
# (400 unrecognized_model). handoff-fire resolved `--model opus` to versions.opus_latest, so the
# moment the SSOT moved to claude-opus-5-5 every recycle of such a pane would relaunch into a dead
# session. The alias is resolved by the binary that actually runs (`--model opus` answered from
# claude-opus-5 on 2.1.260 and from claude-opus-5-5 on 2.1.280, same day), so it cannot name a
# model that binary lacks. A FRESH fire opens a new shell and must keep the full id.
#
# RED-PROOF: test 1 is RED against the parent tree (the dry-run command carries
# `--model claude-opus-5`, the SSOT's full id). Test 2 is GREEN on both trees by construction — it
# is the non-regression guard that the fix did not also strip the full id from fresh fires.
#
# Non-final `[[ ]]` / `(( ))` are errexit-EXEMPT in bats and therefore DEAD as assertions; every
# check below is `[ ]` or `… || false`.

setup() {
  # Environment PINNED, not ambient (MACHINE_CAPACITY_V2 §11.3) — same idiom as
  # tests/handoff-recycle-durable-cwd.bats, whose dry-run harness this suite reuses.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP=off
  # Seams the hermeticity ratchet names for handoff-fire: an ABSOLUTE /tmp default and a BARE
  # tool name, neither redirected by a fixtured $HOME. ABSENT paths — these sensors fail open.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/handoff-account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/claude-accounts-heal-"
  local real_home="$HOME"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  [ -e "$real_home/.claude" ] && ln -s "$real_home/.claude" "$HOME/.claude"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="${HF_UNDER_TEST:-$REPO/scripts/handoff-fire.sh}"
  PF="$BATS_TEST_TMPDIR/payload.txt"; echo "resume the work" > "$PF"
  git init -q "$BATS_TEST_TMPDIR/main"
  MAIN="$(cd "$BATS_TEST_TMPDIR/main" && pwd -P)"
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
}

# The `command:` line of a --dry-run. --launcher is EXPLICIT so the assertion cannot depend on the
# account the RUNNING session uses, and so the --model flag is always appended (the explicit-launcher
# arm appends it unconditionally, which is what makes the value observable here).
cmd_line() { ( cd "$MAIN" && bash "$HF" "$@" --dry-run --prompt-file "$PF" --launcher claude 2>&1 ) | grep -E '^command:' | head -1; }

@test "recycle: --model opus types the alias, not the SSOT's full id" {
  run cmd_line --recycle --session-id "fake:UUID" --model opus
  [ -n "$output" ] || false
  echo "$output" | grep -qE -- '--model opus( |$)' || false
  ! echo "$output" | grep -qE -- '--model claude-opus-' || false
}

@test "fresh fire: --model opus still resolves to a full claude-opus-* id (non-regression)" {
  # A FRESH fire composes its launcher from the ~/.claude account/launcher layout that setup()
  # links in; off-box (empty HOME) there is none and the script exits before printing a command.
  # That is an absent PRECONDITION, not a regression, so it skips. Test 1 — the red-proof — needs
  # no layout and runs everywhere.
  if [ ! -e "$HOME/.claude" ]; then
    skip "fresh fire needs the ~/.claude launcher/account layout (absent off-box)"
  fi
  run cmd_line --cwd "$MAIN" --model opus
  [ -n "$output" ] || false
  echo "$output" | grep -qE -- '--model claude-opus-[0-9]' || false
}
