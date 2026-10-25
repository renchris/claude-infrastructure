#!/usr/bin/env bats
# lr-page.sh — the liveness-free operator page (FLEET_V2 W6 resolution 13, D6.3). Every leg is a stub:
# no test posts a real notification or reaches Pushover.

load helpers/cc-stub

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
printf '%s %s\n' "${PUSHOVER_TOKEN:-}" "${PUSHOVER_USER:-}" >"$BATS_TEST_TMPDIR/push.creds"
exit "${PUSH_RC:-0}"
EOF
  chmod +x "$STUB/osascript" "$STUB/push-send.sh"
  export LR_PAGE_OSASCRIPT_BIN="$STUB/osascript" LR_PAGE_PUSH_BIN="$STUB/push-send.sh"
  export LR_PAGE_CREDS="$BATS_TEST_TMPDIR/pushover.env"
}

creds() { # $1=mode — a credentials file the way the operator would write it
  printf 'export PUSHOVER_TOKEN="tok-from-file"\nPUSHOVER_USER=usr-from-file\n' >"$LR_PAGE_CREDS"
  chmod "$1" "$LR_PAGE_CREDS"
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

@test "a launchd caller with no env reads the 0600 credentials file" {
  creds 600
  run bash "$PAGE" "held draft"
  [ "$status" -eq 0 ]
  [ "$output" = "lr-page: verdict=posted os=posted phone=sent" ]
  [ "$(cat "$BATS_TEST_TMPDIR/push.creds")" = "tok-from-file usr-from-file" ]
  # the caller's own environment is not modified by the read
  run bash -c "source '$PAGE'; lr_page x >/dev/null; echo \"[\${PUSHOVER_TOKEN:-}]\""
  [ "$output" = "[]" ]
}

@test "a group- or world-readable credentials file is refused, and the refusal is counted" {
  for mode in 640 604; do
    creds "$mode"
    rm -f "$BATS_TEST_TMPDIR/push.argv"
    run bash "$PAGE" "x"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "lr-page: refusing $LR_PAGE_CREDS — mode $mode, it must be yours and 0600" ]
    [ "${lines[1]}" = "lr-page: verdict=posted os=posted phone=refused" ]
    [ ! -e "$BATS_TEST_TMPDIR/push.argv" ]
  done
  run bash "$PAGE" --failures
  [ "$output" = "2" ]
}

@test "the environment wins over the file, and the file is never executed" {
  printf 'touch "%s/pwned"\nPUSHOVER_TOKEN=f\nPUSHOVER_USER=f\n' "$BATS_TEST_TMPDIR" >"$LR_PAGE_CREDS"
  chmod 600 "$LR_PAGE_CREDS"
  run bash "$PAGE" "x"
  [ "$output" = "lr-page: verdict=posted os=posted phone=sent" ]
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
  PUSHOVER_TOKEN=e PUSHOVER_USER=e run bash "$PAGE" "x"
  [ "$(cat "$BATS_TEST_TMPDIR/push.creds")" = "e e" ]
}

# agent-secrets stub: injects the keys named in SEC_KEYS into its child, as `agent-secrets run -- cmd`
# does, and records that it was asked. The real store is never read.
secrets_stub() {
  cc_stub "$STUB" agent-secrets - <<'EOF'
#!/bin/bash
echo "$1" >"$BATS_TEST_TMPDIR/secrets.called"
[ "$1" = run ] && [ "$2" = -- ] || exit 2
shift 2
if [ -n "${SEC_KEYS:-}" ]; then export PUSHOVER_TOKEN=tok-from-store PUSHOVER_USER=usr-from-store; fi
exec "$@"
EOF
  export LR_PAGE_SECRETS_BIN="$STUB/agent-secrets"
}

@test "no env and no file: the keys come from agent-secrets, into push-send's process only" {
  secrets_stub
  # push-send's INERT contract: keys unset ⇒ exit 3
  cc_stub "$STUB" push-send.sh - <<'EOF'
#!/bin/bash
[ -n "${PUSHOVER_TOKEN:-}" ] || exit 3
printf '%s %s\n' "$PUSHOVER_TOKEN" "$PUSHOVER_USER" >"$BATS_TEST_TMPDIR/push.creds"
EOF
  SEC_KEYS=1 run bash "$PAGE" "held draft"
  [ "$status" -eq 0 ]
  [ "$output" = "lr-page: verdict=posted os=posted phone=sent" ]
  [ "$(cat "$BATS_TEST_TMPDIR/push.creds")" = "tok-from-store usr-from-store" ]
  # a store without the two names reads skipped, as no credentials always has — not failed
  rm -f "$BATS_TEST_TMPDIR/push.creds"
  run bash "$PAGE" "x"
  [ "$output" = "lr-page: verdict=posted os=posted phone=skipped" ]
  [ ! -e "$BATS_TEST_TMPDIR/push.creds" ]
  run bash "$PAGE" --failures
  [ "$output" = "0" ]
}

@test "the file and the env outrank agent-secrets, which is then never asked" {
  secrets_stub
  creds 600
  SEC_KEYS=1 run bash "$PAGE" "x"
  [ "$(cat "$BATS_TEST_TMPDIR/push.creds")" = "tok-from-file usr-from-file" ]
  [ ! -e "$BATS_TEST_TMPDIR/secrets.called" ]
}

@test "a refusing push through agent-secrets reads failed and is counted" {
  secrets_stub
  export LR_PAGE_OS_CHANNEL=off PUSH_RC=1
  SEC_KEYS=1 run bash "$PAGE" "x"
  [ "$status" -eq 1 ]
  [ "$output" = "lr-page: verdict=failed os=off phone=failed" ]
}
