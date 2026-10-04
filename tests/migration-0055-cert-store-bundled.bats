#!/usr/bin/env bats
# shellcheck disable=SC2016  # the stub binary's body is literal shell text, expanded when the stub runs
# Migration 0055 — adds env.CLAUDE_CODE_CERT_STORE=bundled to the ONE shared settings.json.
#
# Pinned: --dry-run/--check write nothing; --confirm adds exactly that key and changes no other
# byte of meaning (every other env key included), keeps every account a symlink and reads back
# through --verify; a second run is a no-op; a FORKED account and a DIFFERENT value already at the
# key are each refused rc 3 with nothing written (the second also reads as --conflict); usage
# errors are rc 2; and --probe maps PASS 0 / FAIL 1 / BLIND 3, running BEFORE the write so a FAIL
# or BLIND leaves the file untouched.
#
# Hermetic: scratch HOME, the repo's own bin/cc-settings-parity via CC_SETTINGS_PARITY_BIN. The
# probe launches a STUB binary (CERT_STORE_PROBE_BIN) that answers the way Claude Code 2.1.284
# was measured to on 2026-10-04: `bundled` logs `CA certs: stores=bundled, …`; any other source
# logs the `unrecognized` WARN and falls back to `stores=bundled,system`.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIG="$REPO/migrations/0055-cert-store-bundled.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_SETTINGS_PARITY_BIN="$REPO/bin/cc-settings-parity"
  mkdir -p "$HOME/.claude"
  printf '{"accounts":[{"name":"next","config_dir":"~/.claude-next"},{"name":"next2","config_dir":"~/.claude-secondary"},{"name":"next3","config_dir":"~/.claude-tertiary"},{"name":"next4","config_dir":"~/.claude-quaternary"}]}\n' \
    > "$HOME/.claude/accounts.json"
  jq -n '{
    env: {MCP_TIMEOUT: "30000", CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1"},
    hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "~/.claude/hooks/validate-bash.sh"}]}]},
    permissions: {allow: ["Bash(git add:*)"], ask: ["Bash(git push:*)"], defaultMode: "auto"}
  }' > "$HOME/.claude/settings.json"
  for a in next secondary tertiary quaternary; do
    mkdir -p "$HOME/.claude-$a"; ln -s "$HOME/.claude/settings.json" "$HOME/.claude-$a/settings.json"
  done
  F="$HOME/.claude/settings.json"

  # The stub: finds --debug-file, reads the store value from its config dir's settings.json, and
  # records whether the variable leaked in from the shell (the probe must launch with it absent).
  STUB="$BATS_TEST_TMPDIR/claude-stub"
  cat > "$STUB" <<'EOF'
#!/bin/bash
log=""; while [ $# -gt 0 ]; do [ "$1" = "--debug-file" ] && { log="$2"; shift; }; shift; done
printf '%s\n' "${CLAUDE_CODE_CERT_STORE-ABSENT}" > "$STUB_SEEN"
[ "${STUB_SILENT:-0}" = 1 ] && exit 1
v="$(jq -r '.env.CLAUDE_CODE_CERT_STORE' "$CLAUDE_CONFIG_DIR/settings.json")"
if [ "$v" = bundled ]; then
  printf '[DEBUG] CA certs: stores=bundled, extraCertsPath=undefined\n' > "$log"
else
  printf "[WARN] CA certs: unrecognized CLAUDE_CODE_CERT_STORE source '%s', ignoring\n[DEBUG] CA certs: stores=bundled,system, extraCertsPath=undefined\n" "$v" > "$log"
fi
exit 1
EOF
  chmod +x "$STUB"
  export CERT_STORE_PROBE_BIN="$STUB" STUB_SEEN="$BATS_TEST_TMPDIR/stub-seen"
}

mig() { bash "$MIG" "$@"; }
all_linked() { for a in next secondary tertiary quaternary; do [ -L "$HOME/.claude-$a/settings.json" ] || return 1; done; }

@test "0055: --dry-run and --check write nothing; --verify reads NOT live (rc 1) before apply" {
  local before; before="$(shasum "$F")"
  for m in --dry-run --check; do
    run mig "$m"
    [ "$status" -eq 0 ] || { echo "$m: $output"; false; }
  done
  [ "$(shasum "$F")" = "$before" ]
  run mig --verify
  [ "$status" -eq 1 ]
  run mig --conflict
  [ "$status" -eq 1 ]
}

@test "0055: --confirm adds exactly the one env key, changes nothing else, keeps links, verifies, idempotent" {
  local orig; orig="$(cat "$F")"
  run mig --confirm settings.json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -L "$F" ]
  all_linked
  jq -e '.env == {MCP_TIMEOUT: "30000", CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1", CLAUDE_CODE_CERT_STORE: "bundled"}' "$F" >/dev/null
  jq -en --argjson a "$orig" --slurpfile b "$F" '($a | del(.env)) == ($b[0] | del(.env))' >/dev/null
  [ ! -e "$STUB_SEEN" ]                       # no --probe asked ⇒ no launch
  run mig --verify
  [ "$status" -eq 0 ]
  run mig --conflict
  [ "$status" -eq 1 ]
  local after; after="$(shasum "$F")"
  run mig --confirm settings.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"already applied"* ]] || false
  [ "$(shasum "$F")" = "$after" ]
}

@test "0055: a settings.json with no env object at all gains one holding only the key" {
  jq 'del(.env)' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
  run mig --confirm settings.json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.env == {CLAUDE_CODE_CERT_STORE: "bundled"}' "$F" >/dev/null
}

@test "0055: a FORKED account ⇒ rc 3, nothing written anywhere" {
  rm "$HOME/.claude-next/settings.json"; cp "$F" "$HOME/.claude-next/settings.json"
  local b1 b2; b1="$(shasum "$F")"; b2="$(shasum "$HOME/.claude-next/settings.json")"
  run mig --confirm settings.json
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ "$(shasum "$F")" = "$b1" ]
  [ "$(shasum "$HOME/.claude-next/settings.json")" = "$b2" ]
}

@test "0055: a DIFFERENT value already set is refused rc 3, never overwritten, and reads as --conflict" {
  jq '.env.CLAUDE_CODE_CERT_STORE = "bundled,system"' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
  local before; before="$(shasum "$F")"
  run mig --confirm settings.json
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"bundled,system"* ]] || false
  [ "$(shasum "$F")" = "$before" ]
  run mig --conflict
  [ "$status" -eq 0 ]
  run mig --verify
  [ "$status" -eq 1 ]
}

@test "0055: usage — bare outside the converger, an unnamed --confirm, a stray trailing arg ⇒ rc 2, nothing written" {
  local before; before="$(shasum "$F")"
  run mig
  [ "$status" -eq 2 ]
  run mig --confirm
  [ "$status" -eq 2 ]
  run mig --confirm settings.json --force
  [ "$status" -eq 2 ]
  [ "$(shasum "$F")" = "$before" ]
}

@test "0055: --probe PASS writes, and launches the binary with the variable ABSENT from the shell" {
  CLAUDE_CODE_CERT_STORE=system run mig --confirm settings.json --probe
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"probe PASS"*"stores=bundled,"* ]] || false
  [ "$(cat "$STUB_SEEN")" = ABSENT ]          # the settings route is what was proved, not the shell
  run mig --verify
  [ "$status" -eq 0 ]
}

@test "0055: a misspelled value FAILS the probe (rc 1) and nothing is written — the typo control" {
  local t="$BATS_TEST_TMPDIR/tree" before; before="$(shasum "$F")"
  mkdir -p "$t"
  sed 's/^VAL=bundled$/VAL=bundeld/' "$MIG" > "$t/0055.sh"
  grep -qx 'VAL=bundeld' "$t/0055.sh"         # the mutation took, so the control is not vacuous
  run bash "$t/0055.sh" --confirm settings.json --probe
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"probe FAIL"*"unrecognized CLAUDE_CODE_CERT_STORE"* ]] || false
  [ "$(shasum "$F")" = "$before" ]
}

@test "0055: a probe that yields no CA line, or finds no binary, is BLIND (rc 3) and nothing is written" {
  local before; before="$(shasum "$F")"
  STUB_SILENT=1 run mig --confirm settings.json --probe
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"probe BLIND"* ]] || false
  CERT_STORE_PROBE_BIN="$BATS_TEST_TMPDIR/absent" run mig --confirm settings.json --probe
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ "$(shasum "$F")" = "$before" ]
}

@test "0055: the template mirrors the key, and its env comment names the NODE_EXTRA_CA_CERTS caveat" {
  local T="$REPO/settings-templates/settings.example.json"
  jq -e '.env.CLAUDE_CODE_CERT_STORE == "bundled"' "$T" >/dev/null
  jq -e '._comment_env | test("NODE_EXTRA_CA_CERTS=<root.pem>")' "$T" >/dev/null
}
