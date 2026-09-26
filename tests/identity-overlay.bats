#!/usr/bin/env bats
# identity-overlay.bats — the shared resolver for the personal-identity overlay
# (hooks/lib/identity.{py,sh}). Every consumer's failure direction rests on these contracts.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FIX="$REPO/tests/fixtures/identity.fixture.json"
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  mkdir -p "$HOME/.claude"
  unset CC_IDENTITY_FILE CLAUDE_ACCOUNTS_JSON
}

teardown() { rm -rf "$TMP"; }

py() { python3 -c "import sys; sys.path.insert(0, '$REPO/hooks/lib'); import identity as i; $1"; }

@test "resolution: CC_IDENTITY_FILE wins, else \$HOME/.claude/identity.local.json" {
  run py 'print(i.identity_path())'
  [ "$output" = "$HOME/.claude/identity.local.json" ]
  CC_IDENTITY_FILE=/x/y run py 'print(i.identity_path())'
  [ "$output" = "/x/y" ]
  . "$REPO/hooks/lib/identity.sh"
  [ "$(cc_identity_path)" = "$HOME/.claude/identity.local.json" ]
  [ "$(CC_IDENTITY_FILE=/x/y cc_identity_path)" = "/x/y" ]
}

@test "missing or corrupt overlay: python returns {}, bash returns rc 1 — never raises" {
  run py 'print(i.load_identity())'
  [ "$status" -eq 0 ]; [ "$output" = "{}" ]
  echo '{not json' > "$HOME/.claude/identity.local.json"
  run py 'print(i.load_identity())'
  [ "$output" = "{}" ]
  . "$REPO/hooks/lib/identity.sh"
  run cc_identity_get '.git_identity.email'
  [ "$status" -eq 1 ]; [ -z "$output" ]
}

@test "get: dotted lookup in both twins agrees" {
  export CC_IDENTITY_FILE="$FIX"
  run py 'print(i.get("git_identity.email"))'
  [ "$output" = "owner@example.com" ]
  . "$REPO/hooks/lib/identity.sh"
  [ "$(cc_identity_get '.git_identity.email')" = "owner@example.com" ]
  run cc_identity_get '.no.such.key'
  [ "$status" -eq 1 ]
  run python3 "$REPO/hooks/lib/identity.py" git_identity.github_owner
  [ "$output" = "owner" ]
}

@test "merge_accounts fills only MISSING fields — an inline value always wins" {
  export CC_IDENTITY_FILE="$FIX"
  run py '
cfg={"accounts":[{"name":"next"},{"name":"next2","email":"inline@example.com"},{"name":"ghost"}]}
i.merge_accounts(cfg)
r=cfg["accounts"]
print(r[0]["email"], r[0]["dia_profile"], r[1]["email"], r[1]["mailbox"], "email" in r[2], cfg["keychain_account"])'
  [ "$output" = "op1+claude@example.com ProfileA inline@example.com op2@example.com False fixtureuser" ]
}

@test "merge_accounts never overwrites an existing keychain_account, and is a no-op with no overlay" {
  run py '
cfg={"keychain_account":"kept","accounts":[{"name":"next"}]}
i.merge_accounts(cfg, {})
print(cfg)'
  [ "$output" = "{'keychain_account': 'kept', 'accounts': [{'name': 'next'}]}" ]
}

@test "overlay_suppressed: a per-tool SSOT override without CC_IDENTITY_FILE keeps a fixture hermetic" {
  CLAUDE_ACCOUNTS_JSON=/tmp/x run py 'print(i.overlay_suppressed("CLAUDE_ACCOUNTS_JSON"))'
  [ "$output" = "True" ]
  CLAUDE_ACCOUNTS_JSON=/tmp/x CC_IDENTITY_FILE="$FIX" run py 'print(i.overlay_suppressed("CLAUDE_ACCOUNTS_JSON"))'
  [ "$output" = "False" ]
  run py 'print(i.overlay_suppressed("CLAUDE_ACCOUNTS_JSON"))'
  [ "$output" = "False" ]
}

@test "the tracked template and fixture carry example domains only" {
  run grep -hoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$REPO/identity.example.json" "$FIX"
  [ "$status" -eq 0 ]
  run bash -c "grep -hoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' '$REPO/identity.example.json' '$FIX' | grep -vE '@example\.(com|org|net)$'"
  [ "$status" -eq 1 ]
}
