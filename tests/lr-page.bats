#!/usr/bin/env bats
# lr-page.sh — the liveness-free operator page (FLEET_V2 W6 resolution 13, D6.3). Every leg is a stub:
# no test posts a real notification or reaches Pushover.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  PAGE="$REPO/scripts/limit-recover/lr-page.sh"
  STUB="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB"
  export LR_PAGE_LOG="$BATS_TEST_TMPDIR/pages.log"
  export LR_PAGE_OS_CHANNEL=on
  unset PUSHOVER_TOKEN PUSHOVER_USER CC_SUP_OS_CHANNEL
  # osascript stub: records argv and the script it was fed on stdin; exit code from OSA_RC.
  cat >"$STUB/osascript" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$BATS_TEST_TMPDIR/osa.argv"
cat >"$BATS_TEST_TMPDIR/osa.stdin"
[ -n "${OSA_SLEEP:-}" ] && sleep "$OSA_SLEEP"
exit "${OSA_RC:-0}"
EOF
  cat >"$STUB/push-send.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$BATS_TEST_TMPDIR/push.argv"
exit "${PUSH_RC:-0}"
EOF
  chmod +x "$STUB/osascript" "$STUB/push-send.sh"
  export LR_PAGE_OSASCRIPT_BIN="$STUB/osascript" LR_PAGE_PUSH_BIN="$STUB/push-send.sh"
}

@test "Notification Center posts: verdict=posted, phone skipped silently without credentials" {
  run bash "$PAGE" --title "held draft" "session abc is holding a draft"
  [ "$status" -eq 0 ]
  [ "$output" = "lr-page: verdict=posted os=posted phone=skipped" ]
  [ ! -e "$BATS_TEST_TMPDIR/push.argv" ]
}

@test "the text reaches osascript as argv, never inside the script source" {
  msg='draft: "; do shell script "touch /tmp/pwned" --$(id)'
  run bash "$PAGE" --title t "$msg"
  [ "$status" -eq 0 ]
  grep -qxF -- "$msg" "$BATS_TEST_TMPDIR/osa.argv"
  run grep -F 'pwned' "$BATS_TEST_TMPDIR/osa.stdin"
  [ "$status" -ne 0 ]
  grep -q 'item 2 of argv' "$BATS_TEST_TMPDIR/osa.stdin"
}

@test "no channel reached: exit 1, verdict=failed, and the failure is counted" {
  export LR_PAGE_OS_CHANNEL=off
  run bash "$PAGE" "nobody will see this"
  [ "$status" -eq 1 ]
  [ "$output" = "lr-page: verdict=failed os=off phone=skipped" ]
  run bash "$PAGE" --failures
  [ "$output" = "1" ]
}

@test "a failed osascript post is not a success" {
  export OSA_RC=1
  run bash "$PAGE" "x"
  [ "$status" -eq 1 ]
  [ "$output" = "lr-page: verdict=failed os=failed phone=skipped" ]
}

@test "phone leg runs only with both credentials, and carries the page when the OS leg fails" {
  export OSA_RC=1 PUSHOVER_TOKEN=t PUSHOVER_USER=u
  run bash "$PAGE" --title hold "wake failed"
  [ "$status" -eq 0 ]
  [ "$output" = "lr-page: verdict=posted os=failed phone=sent" ]
  grep -qx -- "--message" "$BATS_TEST_TMPDIR/push.argv"
  grep -qx -- "wake failed" "$BATS_TEST_TMPDIR/push.argv"
}

@test "one credential alone skips the phone leg" {
  export PUSHOVER_TOKEN=t
  run bash "$PAGE" "x"
  [ "$status" -eq 0 ]
  [ "$output" = "lr-page: verdict=posted os=posted phone=skipped" ]
  [ ! -e "$BATS_TEST_TMPDIR/push.argv" ]
}

@test "both legs failing is counted once per page" {
  export OSA_RC=1 PUSH_RC=5 PUSHOVER_TOKEN=t PUSHOVER_USER=u
  run bash "$PAGE" "a"
  [ "$status" -eq 1 ]
  [ "$output" = "lr-page: verdict=failed os=failed phone=failed" ]
  run bash "$PAGE" "b"
  export OSA_RC=0
  run bash "$PAGE" "c"
  [ "$status" -eq 0 ]
  run bash "$PAGE" --failures
  [ "$output" = "2" ]
}

@test "the page log never holds the message text" {
  run bash "$PAGE" "secret draft body"
  [ "$status" -eq 0 ]
  run grep -F 'secret' "$LR_PAGE_LOG"
  [ "$status" -ne 0 ]
}

@test "a hung osascript is cut at the bound and reads failed" {
  tb="$(command -v timeout || command -v gtimeout || true)"
  [ -n "$tb" ] || skip "no timeout(1) on this box"
  export OSA_SLEEP=30 LR_PAGE_OS_TIMEOUT_S=1
  start=$(date +%s)
  run bash "$PAGE" "x"
  [ "$status" -eq 1 ]
  [ "$output" = "lr-page: verdict=failed os=failed phone=skipped" ]
  [ $(($(date +%s) - start)) -lt 15 ]
}

@test "usage errors exit 2 and are not counted" {
  run bash "$PAGE"
  [ "$status" -eq 2 ]
  run bash "$PAGE" --bogus x
  [ "$status" -eq 2 ]
  run bash "$PAGE" --failures
  [ "$output" = "0" ]
}

@test "sourcing defines lr_page without running it" {
  run bash -c "source '$PAGE'; type lr_page >/dev/null && lr_page --title t msg"
  [ "$status" -eq 0 ]
  [ "$output" = "lr-page: verdict=posted os=posted phone=skipped" ]
}

@test "auto mode with no osascript on the box reads off, not failed" {
  export LR_PAGE_OS_CHANNEL=auto LR_PAGE_OSASCRIPT_BIN="$BATS_TEST_TMPDIR/absent-osascript"
  run bash "$PAGE" "x"
  [ "$status" -eq 1 ]
  [ "$output" = "lr-page: verdict=failed os=off phone=skipped" ]
}

@test "runs under /bin/bash 3.2, which launchd uses" {
  [ -x /bin/bash ] || skip "no /bin/bash"
  run /bin/bash "$PAGE" --title t "x"
  [ "$status" -eq 0 ]
  [ "$output" = "lr-page: verdict=posted os=posted phone=skipped" ]
}
