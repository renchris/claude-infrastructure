#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
# cc-url-open — the kitty link handler that routes claude.ai/* into the Dia Space of the
# account owning the clicked pane. Hermetic: every input the handler reads (kitty's window
# list, the pane registry, accounts.json, Dia's Local State) is a fixture under
# BATS_TEST_TMPDIR, and `open` is a stub on PATH — nothing here touches the operator's live
# Dia, live registry, or real browser.
#
# WHAT THESE TESTS ARE FOR. The handler sits in the click path, so its ONLY unacceptable
# failure is swallowing a link. Every unhappy path below therefore asserts the same thing:
# the URL still reaches `open -b company.thebrowser.dia`. A routing miss is a cosmetic
# regression; a lost click is a broken browser. The CDP leg is deliberately NOT exercised
# (it needs a live consent-approved Dia); it is pinned by CC_URL_OPEN_NO_CDP, which is the
# same branch a down port takes in production. The AppleScript leg (tried first since
# 2026-09-23) IS exercised, through an `osascript` stub on PATH that every case inherits.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  C="$REPO/bin/cc-url-open"
  D="$BATS_TEST_TMPDIR"

  # `open` stub — records argv so a test can prove the fallback fired with the real URL.
  mkdir -p "$D/bin"
  cat >"$D/bin/open" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$OPEN_LOG"
EOF
  chmod +x "$D/bin/open"
  export OPEN_LOG="$D/open.log"; : >"$OPEN_LOG"

  # `osascript` stub — the AppleScript leg's seam. Sits on PATH in EVERY case, so no test can
  # reach the operator's live Dia even if it forgets to configure it; defaults to failing, which
  # is the branch a Dia without the dictionary takes. argv: -e <script> <url> <profile> <mode>.
  cat >"$D/bin/osascript" <<'EOF'
#!/bin/bash
printf '%s\n' "$3|$4|$5" >> "$OSA_LOG"
printf '%s\n' "$2" > "$OSA_SCRIPT"
case "${OSA_MODE:-fail}" in
  ok)    [ "$5" = probe ] && echo ok || echo routed ;;
  wrong) echo "something else" ;;
  hang)  exec sleep 5 ;;
  *)     echo "execution error: Dia got an error (-1719)" >&2; exit 1 ;;
esac
EOF
  chmod +x "$D/bin/osascript"
  export OSA_LOG="$D/osa.log" OSA_SCRIPT="$D/osa-script.txt"; : >"$OSA_LOG"
  export PATH="$D/bin:$PATH"

  # kitty @ ls fixture: os-window focused, tab focused, window 362 focused.
  cat >"$D/kitty-ls.json" <<'EOF'
[{"is_focused": true, "tabs": [{"is_focused": true, "windows": [
  {"id": 361, "is_focused": false},
  {"id": 362, "is_focused": true}]}]}]
EOF
  export CC_URL_OPEN_KITTY_LS="$D/kitty-ls.json"

  # pane registry: window 362 belongs to account 3.
  mkdir -p "$D/registry"
  echo '{"paneUUID":"362","account":"claude-tertiary"}' >"$D/registry/362.json"
  export CC_URL_OPEN_REGISTRY="$D/registry"

  cat >"$D/accounts.json" <<'EOF'
{"accounts":[
 {"name":"next","config_dir":"~/.claude-next","dia_profile":"Personaly"},
 {"name":"next3","config_dir":"~/.claude-tertiary","dia_profile":"Claude3"}]}
EOF
  export CC_URL_OPEN_ACCOUNTS="$D/accounts.json"

  mkdir -p "$D/userdata"
  cat >"$D/userdata/Local State" <<'EOF'
{"profile":{"info_cache":{"Default":{"name":"Personaly"},"Profile 15":{"name":"Claude3"}}}}
EOF
  export CC_URL_OPEN_USER_DATA="$D/userdata"
  export CC_URL_OPEN_CACHE="$D/ctx-cache.json"
  export CC_URL_OPEN_NO_CDP=1
  ART="https://claude.ai/code/artifact/abc123"
}

@test "resolves the clicked pane to its account's Dia profile directory" {
  run "$C" --explain "$ART"
  [ "$status" -eq 0 ]
  [[ "$output" == *"window=362"* ]] || false
  [[ "$output" == *"account=claude-tertiary"* ]] || false
  [[ "$output" == *"profile_dir=Profile 15"* ]]
}

@test "a different pane resolves to a different profile — the whole point" {
  echo '{"paneUUID":"362","account":"claude-next"}' >"$D/registry/362.json"
  run "$C" --explain "$ART"
  [[ "$output" == *"profile_dir=Default"* ]]
}

@test "non-claude.ai URLs are never routed — they take today's path untouched" {
  run "$C" --explain "https://github.com/anthropics/claude-code"
  [[ "$output" == *"routed=False"* ]] || false
  [[ "$output" != *"account="* ]]
}

@test "no registry row for the pane → fallback, no crash" {
  rm -f "$D/registry/362.json"
  run "$C" "$ART"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Traceback"* ]] || false
  grep -qF -- "$ART" "$OPEN_LOG"
}

@test "account absent from accounts.json → fallback, no crash" {
  echo '{"paneUUID":"362","account":"claude-nonexistent"}' >"$D/registry/362.json"
  run "$C" --explain "$ART"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile_dir=None"* ]] || false
  [[ "$output" != *"Traceback"* ]]
}

@test "dia_profile naming no on-disk directory → fallback, no crash" {
  echo '{"profile":{"info_cache":{"Default":{"name":"Personaly"}}}}' >"$D/userdata/Local State"
  run "$C" --explain "$ART"
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile_dir=None"* ]]
}

@test "unreadable Local State → fallback, no crash" {
  echo 'not json' >"$D/userdata/Local State"
  run "$C" "$ART"
  [ "$status" -eq 0 ]
  grep -qF -- "$ART" "$OPEN_LOG"
}

@test "kitty unreachable (no window list) → fallback, no crash" {
  echo 'not json' >"$D/kitty-ls.json"
  run "$C" "$ART"
  [ "$status" -eq 0 ]
  grep -qF -- "$ART" "$OPEN_LOG"
}

@test "no focused window in the list → fallback, no crash" {
  echo '[{"is_focused": true, "tabs": [{"is_focused": true, "windows": [{"id": 361, "is_focused": false}]}]}]' >"$D/kitty-ls.json"
  run "$C" --explain "$ART"
  [ "$status" -eq 0 ]
  [[ "$output" == *"window=None"* ]]
}

@test "kitty not frontmost (nothing is_focused) still resolves via is_active" {
  # The live shape when any other app holds focus — including the Dia window this handler
  # itself raises. A resolver that only reads is_focused returns None here and the link
  # quietly stops being routed, which is invisible: it just opens in the wrong Space again.
  cat >"$D/kitty-ls.json" <<'EOF'
[{"is_focused": false, "is_active": true, "tabs": [{"is_focused": false, "is_active": true,
  "windows": [{"id": 361, "is_focused": false, "is_active": false},
              {"id": 362, "is_focused": false, "is_active": true}]}]},
 {"is_focused": false, "is_active": false, "tabs": [{"is_focused": false, "is_active": true,
  "windows": [{"id": 999, "is_focused": false, "is_active": true}]}]}]
EOF
  run "$C" --explain "$ART"
  [[ "$output" == *"window=362"* ]] || false
  [[ "$output" == *"account=claude-tertiary"* ]]
}

@test "is_focused WINS over is_active when both are present" {
  # Ordering matters: at a real click the focused pane is the one clicked in, and it is not
  # always the active pane of the active tab (a click can focus a different window first).
  cat >"$D/kitty-ls.json" <<'EOF'
[{"is_focused": true, "is_active": true, "tabs": [{"is_focused": true, "is_active": true,
  "windows": [{"id": 362, "is_focused": true, "is_active": false},
              {"id": 999, "is_focused": false, "is_active": true}]}]}]
EOF
  run "$C" --explain "$ART"
  [[ "$output" == *"window=362"* ]]
}

@test "several URLs in one invocation each reach open" {
  run "$C" "$ART" "https://example.com/x"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$OPEN_LOG")" -eq 2 ]
}

@test "no argument is a usage error, not a silent success" {
  run "$C"
  [ "$status" -eq 2 ]
}

@test "www.claude.ai is routed too — host match must not be exact-string-only" {
  run "$C" --explain "https://www.claude.ai/chat/x"
  [[ "$output" == *"account=claude-tertiary"* ]]
}

@test "a URL whose host merely CONTAINS claude.ai is NOT routed" {
  run "$C" --explain "https://claude.ai.evil.example/x"
  [[ "$output" != *"account="* ]] || false
  [[ "$output" == *"routed=False"* ]]
}

# ── the AppleScript leg (backlog e09a075539f5) ──────────────────────────────────────────────
# CDP re-popped Dia's consent modal per connection, so routing worked, then blocked, then
# worked. Dia's AppleScript `profile` is the Space and needs no port and no modal; these pin
# that it is tried FIRST, that success is never followed by a second open, and that every way
# it can fail still hands the link to `open`.

@test "AppleScript routes into the account's Space and the fallback does NOT also fire" {
  OSA_MODE=ok run "$C" "$ART"
  [ "$status" -eq 0 ]
  grep -qxF -- "$ART|Claude3|open" "$OSA_LOG" || false
  # A second open would put the link in the wrong Space too — the defect this file closes.
  [ ! -s "$OPEN_LOG" ] || { cat "$OPEN_LOG"; false; }
}

@test "AppleScript error → fallback still opens the link" {
  OSA_MODE=fail run "$C" "$ART"
  [ "$status" -eq 0 ]
  [ -s "$OSA_LOG" ] || false
  grep -qF -- "-b company.thebrowser.dia $ART" "$OPEN_LOG"
}

@test "rc 0 with an unexpected reply is NOT success — fallback opens the link" {
  OSA_MODE=wrong run "$C" "$ART"
  [ "$status" -eq 0 ]
  grep -qF -- "-b company.thebrowser.dia $ART" "$OPEN_LOG"
}

@test "a hung osascript is bounded by the deadline and falls back" {
  CC_URL_OPEN_DEADLINE=1 OSA_MODE=hang run "$C" "$ART"
  [ "$status" -eq 0 ]
  grep -qF -- "-b company.thebrowser.dia $ART" "$OPEN_LOG"
}

@test "--explain probes read-only (mode=probe) and opens nothing" {
  OSA_MODE=ok run "$C" --explain "$ART"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dia_profile=Claude3"* ]] || false
  [[ "$output" == *"applescript=ok"* ]] || false
  [[ "$output" == *"routed=True"* ]] || false
  grep -qxF -- "$ART|Claude3|probe" "$OSA_LOG" || false
  [ ! -s "$OPEN_LOG" ]
}

@test "AppleScript routes even when Local State cannot map the profile to a directory" {
  # The CDP leg needs the on-disk directory; the AppleScript leg needs only the display name.
  echo '{"profile":{"info_cache":{"Default":{"name":"Personaly"}}}}' >"$D/userdata/Local State"
  OSA_MODE=ok run "$C" "$ART"
  [ "$status" -eq 0 ]
  grep -qxF -- "$ART|Claude3|open" "$OSA_LOG" || false
  [ ! -s "$OPEN_LOG" ]
}

@test "the URL reaches osascript as argv, never spliced into the script source" {
  local evil='https://claude.ai/x?q="end tell'
  OSA_MODE=ok run "$C" "$evil"
  [ "$status" -eq 0 ]
  grep -qxF -- "$evil|Claude3|open" "$OSA_LOG" || false
  run grep -qF -- 'claude.ai/x' "$OSA_SCRIPT"
  [ "$status" -eq 1 ]
}

@test "CC_URL_OPEN_NO_APPLESCRIPT skips the leg entirely" {
  CC_URL_OPEN_NO_APPLESCRIPT=1 OSA_MODE=ok run "$C" "$ART"
  [ "$status" -eq 0 ]
  [ ! -s "$OSA_LOG" ] || false
  grep -qF -- "$ART" "$OPEN_LOG"
}

@test "non-claude.ai URLs never invoke osascript" {
  OSA_MODE=ok run "$C" "https://github.com/anthropics/claude-code"
  [ "$status" -eq 0 ]
  [ ! -s "$OSA_LOG" ] || false
  grep -qF -- "github.com" "$OPEN_LOG"
}
