#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # every @test is a subshell BY DESIGN: per-case env is case-local.
# handoff-fire.sh × CC_LADDER=off — the escalation ladder's kill switch (audit row slim-15).
#
# THE DEFECT THIS SUITE PINS. CLAUDE.md § Frontier Tier Routing says "If CC_LADDER=off is set, do
# not fire it", and no code read the variable: `git grep CC_LADDER` found prose only, while the
# plan that defines the switch says it "must be mechanical, not prose"
# (docs/plans/NONLIMIT_RESUME_LADDER.md § 6). The switch refuses exactly the ladder's stage-1→2
# step — a --recycle onto the frontier model — and nothing else: a fresh frontier fire is
# /frontier-run or /frontier-campaign, not the ladder. Cases 1-2 are the red proof (pre-fix they
# exit 0 with the frontier relaunch in the dry-run command); 3-5 pin the switch's narrow scope.
# The hook-side mirror is pinned in tests/frontier-spawn-gate.bats cases 24-26.
#
# Every case is a --dry-run with an explicit --launcher, so nothing is typed into any pane and no
# account is routed; the refusal sits before both, right after model normalization.

setup() {
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_SRC/scripts/handoff-fire.sh"
  [ -f "$HF" ] || { echo "subject missing: $HF" >&2; return 1; }

  # Pinned, not ambient (same pins as tests/handoff-recycle-intent.bats): the capacity/headroom
  # gates read live machine load, and the sweep seams default to real machine paths. An ABSENT
  # path is the right pin — every one of these sensors fails open on a miss.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/no-such-sweep-stamp.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/no-such-heal-lock-"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  export WRAP_DOD_DIR="$BATS_TEST_TMPDIR/dod"; mkdir -p "$WRAP_DOD_DIR"

  export H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H/.claude/bin"
  export HOME="$H"
  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SHIM/osascript"
  chmod +x "$SHIM/osascript"
  export PATH="$SHIM:$PATH"
  # An it2 that enumerates nothing: a dry run must not need a real terminal.
  # shellcheck disable=SC2016  # the $1/$2 belong to the generated stub, not to this shell
  printf '#!/usr/bin/env bash\ncase "$1 $2" in "session list") [ "${3:-}" = --json ] && printf "[]\\n" ;; esac\nexit 0\n' \
    > "$H/.claude/bin/it2"
  chmod +x "$H/.claude/bin/it2"
  export IT2_BIN="$H/.claude/bin/it2"
  unset KITTY_WINDOW_ID; unset CC_TERM; export IT2_WRAPPER_NO_KITTY=1
  unset CC_PANE_CMD_INTERACTIVE
  # The subject under test: an operator who exported it must not decide the "allowed" cases.
  unset CC_LADDER

  write_cfg claude-fable-5-1
  PF="$BATS_TEST_TMPDIR/brief.md"; printf 'body\n' > "$PF"
  export SID_ENV="w1t0p0:AAAAAAAA-0000-0000-0000-0000000000FF"
}

write_cfg() { # <frontier_access.model> — the SSOT handoff-fire resolves `--model fable` from
  printf '%s\n' \
    'versions:' \
    '  opus_latest: claude-opus-5-5' \
    'frontier_access:' \
    "  model: $1" \
    '  active: true' \
    '  end: "2099-12-31"' \
    '  fallback: claude-opus-5-5' > "$H/.claude/model-config.yaml"
}

fire() { # <CC_LADDER value or -> <handoff-fire args...>  (stdout+stderr → $output)
  local ladder="$1"; shift
  if [ "$ladder" = - ]; then
    run env -u CC_LADDER ITERM_SESSION_ID="$SID_ENV" timeout 90 \
      bash "$HF" --prompt-file "$PF" --launcher claude-test --dry-run "$@"
  else
    run env CC_LADDER="$ladder" ITERM_SESSION_ID="$SID_ENV" timeout 90 \
      bash "$HF" --prompt-file "$PF" --launcher claude-test --dry-run "$@"
  fi
}

@test "1 CC_LADDER=off refuses --recycle --model fable with exit 2 and one reason line" {
  fire off --recycle --model fable
  [ "$status" -eq 2 ]
  [[ "$output" == *"CC_LADDER=off: refusing --recycle onto the frontier model (claude-fable-5-1)"* ]] || false
  # refused BEFORE the dry-run plan: nothing past the refusal ran
  [[ "$output" != *"command:"* ]]
}

@test "2 CC_LADDER=off refuses the verbatim frontier id too, prior family member included" {
  fire off --recycle --model claude-fable-5-1
  [ "$status" -eq 2 ]
  fire off --recycle --model claude-fable-5
  [ "$status" -eq 2 ]
  [[ "$output" == *"CC_LADDER=off"* ]]
}

@test "3 a frontier tier past the 5 family is caught by the SSOT arm, not just the prefix" {
  write_cfg claude-fable-6
  fire off --recycle --model fable
  [ "$status" -eq 2 ]
  [[ "$output" == *"(claude-fable-6)"* ]]
}

@test "4 without CC_LADDER=off the same recycle is allowed" {
  fire - --recycle --model fable
  [ "$status" -eq 0 ]
  [[ "$output" != *"CC_LADDER"* ]] || false
  [[ "$output" == *"--model claude-fable-5-1"* ]]
}

@test "5 CC_LADDER=off allows a NON-recycle frontier fire, and a recycle on the default tier" {
  fire off --model fable
  [ "$status" -eq 0 ]
  [[ "$output" != *"CC_LADDER"* ]] || false
  [[ "$output" == *"--model claude-fable-5-1"* ]] || false
  fire off --recycle --model opus
  [ "$status" -eq 0 ]
  [[ "$output" != *"CC_LADDER"* ]]
}

@test "6 a MISSING model-config.yaml does not turn the switch into a silent exit 2 on a non-frontier recycle" {
  # Review finding: the SSOT read ran for every recycle under set -e, and _ssot_scalar's awk exits 2
  # on an absent file, so `--recycle --model opus` died with exit 2 and zero bytes of output, the
  # refusal's own code. The default tier never needs the SSOT, so a missing one must not matter.
  rm -f "$H/.claude/model-config.yaml"
  fire off --recycle --model opus
  [ "$status" -eq 0 ]
  [[ "$output" == *"command:"* ]] || false
  fire off --recycle
  [ "$status" -eq 0 ]
  [[ "$output" == *"command:"* ]]
}
