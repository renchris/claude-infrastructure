#!/usr/bin/env bats
# scripts/handoff-fire.sh hf_canary_hook — the W5b real-canary test hook. It must be INERT unless a
# canary daemon set LR_RECON_CANARY, must never fail its caller, and must sit at exactly the two
# points the canaries time: after the transplant confirm, and in the watcher before the launch lock.
#
# HERMETIC: HOME points into BATS_TEST_TMPDIR; the function is extracted from the script and run
# alone, so nothing else in handoff-fire executes.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  # handoff-fire never executes here (one function is extracted), but its seams are pinned anyway
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  mkdir -p "$HOME"
  FN="$BATS_TEST_TMPDIR/fn.sh"
  sed -n '/^hf_canary_hook() {/,/^}/p' "$S" >"$FN"
  HOOK="$BATS_TEST_TMPDIR/hook"
  LOG="$BATS_TEST_TMPDIR/hook.log"
  printf '#!/bin/bash\nprintf "%%s|" "$@" >> "%s"\nexit 7\n' "$LOG" >"$HOOK"
  chmod +x "$HOOK"
  unset LR_RECON_CANARY HF_CANARY_HOOK
}

@test "extracted: the hook function exists and parses" {
  [ -s "$FN" ]
  /bin/bash -n "$FN"
}

@test "inert without LR_RECON_CANARY, even with HF_CANARY_HOOK set" {
  HF_CANARY_HOOK="$HOOK" run /bin/bash -c ". '$FN'; hf_canary_hook after-confirm 12 sid-x; echo rc=\$?"
  [ "$output" = "rc=0" ]
  [ ! -e "$LOG" ]
}

@test "under a canary it runs with point, pane, sid and pid, and a failing hook never fails the caller" {
  LR_RECON_CANARY=s HF_CANARY_HOOK="$HOOK" run /bin/bash -c ". '$FN'; hf_canary_hook before-relaunch 12 sid-x; echo rc=\$?"
  [ "$output" = "rc=0" ]
  run cat "$LOG"
  [[ "$output" == "before-relaunch|12|sid-x|"* ]]
}

@test "the two call sites: after the confirm, and in the watcher before the launch lock" {
  [ "$(grep -c 'RCY_CONFIRM_RAN=1$' "$S")" -eq 1 ]
  confirm="$(grep -n 'RCY_CONFIRM_RAN=1$' "$S" | head -1 | cut -d: -f1)"
  after="$(grep -n 'hf_canary_hook after-confirm' "$S" | cut -d: -f1)"
  [ "$after" -eq "$((confirm + 1))" ]
  before="$(grep -n 'hf_canary_hook before-relaunch' "$S" | cut -d: -f1)"
  lock="$(grep -n 'THE LAUNCH LOCK, THEN H(sid)' "$S" | cut -d: -f1)"
  [ "$lock" -eq "$((before + 1))" ]
}
