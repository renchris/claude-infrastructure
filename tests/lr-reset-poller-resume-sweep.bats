#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # each @test is its own subshell; per-test exports are the intent
# lr-reset-poller.sh — the resume-debt BACKSTOP (docs/plans/CLOSE_RESUME_CUSTODY.md §2 D4): every tick
# runs `cc-resume-debt sweep` once, so a debt whose settling watcher died still reaches proof or
# escalation. Four contracts: the sweep runs and its output is logged `RESUME-DEBT:`; --dry-run logs
# only; LR_RESUME_DEBT_SWEEP=off skips; an absent binary skips silently.
#
# Hermetic: HOME is a fixture, the poller's census/fleet/upgrade legs are stubs (the harness is
# tests/lr-upgrade.bats's poller_env), and cc-resume-debt is a recorder behind CC_RESUME_DEBT_BIN.

setup() {
  command -v jq >/dev/null || skip "jq required"
  export CC_FIRE_CAPACITY_GATE=off
  export CC_ADMIT_GATE=off
  unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  export LR_POLLER_NO_CENSUS=1
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/preg"; mkdir -p "$CC_REGISTRY_DIR"
  export LR_POLLER_LAUNCH_DIR="$BATS_TEST_TMPDIR/launchers"; mkdir -p "$LR_POLLER_LAUNCH_DIR"
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/no-kitty-socket"
  unset KITTY_WINDOW_ID CC_TERM_KITTY_TO
  printf '#!/bin/bash\nexit 1\n' > "$STUBS/osascript"; chmod +x "$STUBS/osascript"
  mkdir -p "$HOME/bin"; printf '#!/bin/bash\necho %s\n' "'{\"rows\":[]}'" > "$HOME/bin/claude-accounts"; chmod +x "$HOME/bin/claude-accounts"
  export PATH="$STUBS:$PATH"
  export LR_FLEET_BIN="$STUBS/lr-fleet"; printf '#!/bin/bash\necho "$*" >> %s\n' "$BATS_TEST_TMPDIR/fleet.log" > "$LR_FLEET_BIN"; chmod +x "$LR_FLEET_BIN"
  export LR_UPGRADE_BIN="$STUBS/lr-upgrade"
  printf '#!/bin/bash\necho "$*" >> %s\n' "$BATS_TEST_TMPDIR/drain.log" > "$LR_UPGRADE_BIN"; chmod +x "$LR_UPGRADE_BIN"
  PSTATE="$HOME/.reso/limit-recover"; mkdir -p "$PSTATE/requests" "$PSTATE/parked" "$PSTATE/resumed"
  # the recorder: logs its argv, answers `sweep` with two verdict lines and one blank
  export CC_RESUME_DEBT_BIN="$STUBS/cc-resume-debt"
  cat > "$CC_RESUME_DEBT_BIN" <<EOF
#!/bin/bash
echo "\$*" >> "$BATS_TEST_TMPDIR/rd.log"
[ "\$1" = sweep ] && printf 'resume:aaaaaaaa-1:100 proven\n\nresume:bbbbbbbb-2:200 escalated backlog=abc123\n'
exit 0
EOF
  chmod +x "$CC_RESUME_DEBT_BIN"
}

@test "the tick runs ONE sweep and logs each non-empty output line as RESUME-DEBT:" {
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$(grep -cx 'sweep' "$BATS_TEST_TMPDIR/rd.log")" -eq 1 ] || { cat "$PSTATE/poller.log"; false; }
  grep -q 'RESUME-DEBT: resume:aaaaaaaa-1:100 proven$' "$PSTATE/poller.log"
  grep -q 'RESUME-DEBT: resume:bbbbbbbb-2:200 escalated backlog=abc123$' "$PSTATE/poller.log"
  [ "$(grep -c 'RESUME-DEBT:' "$PSTATE/poller.log")" -eq 2 ]      # the blank line is not logged
}

@test "--dry-run logs the sweep it WOULD run and never runs it" {
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --dry-run --once
  grep -q "DRY   resume-debt sweep would run: $CC_RESUME_DEBT_BIN sweep" "$PSTATE/poller.log" \
    || { cat "$PSTATE/poller.log"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/rd.log" ]
}

@test "LR_RESUME_DEBT_SWEEP=off skips the sweep entirely" {
  LR_RESUME_DEBT_SWEEP=off LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ -f "$PSTATE/poller.log" ]                                    # the tick itself ran
  [ ! -e "$BATS_TEST_TMPDIR/rd.log" ]
  ! grep -q 'resume-debt\|RESUME-DEBT' "$PSTATE/poller.log" || false
}

@test "an absent cc-resume-debt is a SILENT skip — no log line, the tick still completes" {
  export CC_RESUME_DEBT_BIN="$BATS_TEST_TMPDIR/no-such-cc-resume-debt"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ] || { echo "$output"; cat "$PSTATE/poller.log"; false; }
  [ -f "$PSTATE/poller.log" ]
  ! grep -q 'resume-debt\|RESUME-DEBT' "$PSTATE/poller.log" || false
}
