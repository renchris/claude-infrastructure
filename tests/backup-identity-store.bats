#!/usr/bin/env bats
# backup-identity-store — a backup of an IDENTITY-class file must never land in the SHARED store
# (backlog 2bcc6b4d8468).
#
# ~/.claude/backups is a real dir every other config dir reaches through a symlink, so a backup
# written there by ANY account is readable by all four. Five `.claude.json.backup.*` carrying
# `oauthAccount` for three DIFFERENT accounts were found there — the exact inverse of the defect
# ACCOUNT_AGNOSTIC_AGENT_STATE.md repaired, since `.claude.json` is isolated at the config-dir root
# and the same bytes then walked into the shared layer under a path no isolate entry covered.
#
# Harness laws, matching tests/backup-prune-identity.bats: L1 drive the REAL hook with the literal
# PreToolUse payload — the destination contract comes from the producer, never from a hand-built
# path; L2 assert on the STORE the bytes landed in, which is the failure-distinct axis; L3 `[ ]`
# and `grep` only; L4 carry a NEGATIVE that goes red if the fix over-reaches and banishes ordinary
# work files, plus a control proving the shared store is still writable at all.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/backup-before-write.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CLAUDE_CONFIG_DIR="$HOME/.claude-secondary"
  mkdir -p "$HOME/.claude" "$CLAUDE_CONFIG_DIR"
  SHARED="$HOME/.claude/backups"
  PRIVATE="$CLAUDE_CONFIG_DIR/backups-identity"
}

payload() { # <file>
  jq -nc --arg f "$1" \
    '{session_id:"sid-bi",hook_event_name:"PreToolUse",tool_name:"Write",
      tool_input:{file_path:$f,content:"x"}}'
}

# drive the real hook once against a file seeded with <content>
drive() { # <path> <content>
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" > "$1"
  printf '%s' "$(payload "$1")" | bash "$HOOK" >/dev/null
}

# Count surviving .bak files in <dir> whose sidecar names <file>.
# `find`, not a glob: an identity backup is named after its source, so `.claude.json__<stamp>.path`
# LEADS WITH A DOT and `"$dir"/*.path` silently skips every one of them — a counter that reads 0
# over a store that is full, which is exactly the false negative this suite exists to catch.
baks_in() { # <dir> <file>
  local p c=0
  [ -d "$1" ] || { printf '0'; return 0; }
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ "$(cat "$p")" = "$2" ] || continue
    [ -f "${p%.path}.bak" ] && c=$((c + 1))
  done < <(find "$1" -maxdepth 1 -name '*.path' 2>/dev/null)
  printf '%s' "$c"
}

@test "an identity file (.claude.json) is backed up OUTSIDE the shared store" {
  F="$BATS_TEST_TMPDIR/acct/.claude.json"
  drive "$F" '{"oauthAccount":{"emailAddress":"leak@example.com"}}'
  [ "$(baks_in "$SHARED" "$F")" -eq 0 ]
  [ "$(baks_in "$PRIVATE" "$F")" -eq 1 ]
}

@test "the identity family is matched by NAME, not by one spelling (.claude.json.backup)" {
  F="$BATS_TEST_TMPDIR/acct/.claude.json.backup"
  drive "$F" '{"oauthAccount":{"emailAddress":"leak2@example.com"}}'
  [ "$(baks_in "$SHARED" "$F")" -eq 0 ]
  [ "$(baks_in "$PRIVATE" "$F")" -eq 1 ]
}

@test "credentials are identity too" {
  F="$BATS_TEST_TMPDIR/acct/.credentials.json"
  drive "$F" '{"token":"t"}'
  [ "$(baks_in "$SHARED" "$F")" -eq 0 ]
  [ "$(baks_in "$PRIVATE" "$F")" -eq 1 ]
}

# NEGATIVE — the fix must not banish ordinary work files. A remedy that routed EVERYTHING to the
# private store would split 145 repo-file backups four ways, which is the mis-classification
# lib/config-mirror.zsh's `tasks` note already measured and reverted once.
@test "an ordinary work file still lands in the SHARED store" {
  F="$BATS_TEST_TMPDIR/repo/CLAUDE.md"
  drive "$F" 'alpha'
  [ "$(baks_in "$SHARED" "$F")" -eq 1 ]
  [ "$(baks_in "$PRIVATE" "$F")" -eq 0 ]
}

# CONTROL — a file whose name merely CONTAINS the identity token is not identity. This is what
# stops the guard from being widened into a substring match later.
@test "a work file named like an identity file is NOT diverted" {
  F="$BATS_TEST_TMPDIR/repo/docs-.claude.json-notes.md"
  drive "$F" 'notes'
  [ "$(baks_in "$SHARED" "$F")" -eq 1 ]
  [ "$(baks_in "$PRIVATE" "$F")" -eq 0 ]
}

@test "the mirror isolates backups-identity in EVERY config dir it knows, and by default" {
  run grep -c "backups-identity" "$REPO/lib/config-mirror.zsh"
  [ "$status" -eq 0 ]
  # 4 named isolate sets + the unknown-dir fallback
  [ "$output" -ge 5 ]
  grep -q "_CC_ISOLATE\[\$HOME/.claude-quaternary\]='.claude.json .claude.json.backup backups-identity" "$REPO/lib/config-mirror.zsh"
}
