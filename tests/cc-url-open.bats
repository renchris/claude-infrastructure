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
# same branch a down port takes in production.

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

@test "CDP unavailable still opens the link (fallback, not a swallowed click)" {
  run "$C" "$ART"
  [ "$status" -eq 0 ]
  grep -qF -- "-b company.thebrowser.dia $ART" "$OPEN_LOG"
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
