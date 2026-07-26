#!/usr/bin/env bats
# cc-config-slot — Phase-5 (Variant A token de-sharing) config-dir resolver, INERT BY DEFAULT.
# The load-bearing property under test is the OFF path: with no flag file (the shipped state) the
# resolver must return the account's canonical config dir EXACTLY, so landing this file cannot
# change how any session launches. Hermetic: a temp accounts.json + temp flag file via env —
# never the real ~/.claude, never a real credential.

setup() {
  # HERMETIC $HOME (scripts/test-hermeticity-lint.sh — the ratchet that binds every NEW suite):
  # the subject resolves its own state under ~, so unfixtured this suite reads/writes the
  # operator's LIVE layer. Everything this suite asserts is already redirected elsewhere.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # never resolve ~ to the operator's tree
  C="$REPO/bin/cc-config-slot"
  D="$BATS_TEST_TMPDIR"

  cat > "$D/accounts.json" <<'JSON'
{
  "accounts": [
    {"name": "next",  "config_dir": "~/.claude-next"},
    {"name": "next2", "config_dir": "~/.claude-secondary"},
    {"name": "next3", "config_dir": "~/.claude-tertiary"},
    {"name": "next4", "config_dir": "~/.claude-quaternary"}
  ]
}
JSON
  export CC_CONFIG_SLOT_ACCOUNTS_JSON="$D/accounts.json"
  export CC_CONFIG_SLOT_FLAG_FILE="$D/desharing.json"   # deliberately absent by default
}

enable_desharing() { echo '{"enabled": true}' > "$CC_CONFIG_SLOT_FLAG_FILE"; }

# ── the default (shipped) state: a provable no-op ───────────────────────────────

@test "OFF by default: no flag file → canonical config dir, byte-identical" {
  run "$C" next
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.claude-next" ]
}

@test "OFF by default: every account resolves to its own canonical dir" {
  for pair in "next:.claude-next" "next2:.claude-secondary" "next3:.claude-tertiary" "next4:.claude-quaternary"; do
    run "$C" "${pair%%:*}"
    [ "$status" -eq 0 ]
    [ "$output" = "$HOME/${pair##*:}" ]
  done
}

@test "OFF by default: the session class cannot change the answer" {
  run "$C" next --class agent-teams
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.claude-next" ]
  run "$C" next --class research
  [ "$output" = "$HOME/.claude-next" ]
}

@test "OFF by default: --json reports enabled=false and a null slot" {
  run "$C" next --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.enabled')" = "false" ]
  [ "$(echo "$output" | jq -r '.slot')" = "null" ]
  [ "$(echo "$output" | jq -r '.config_dir')" = "$(echo "$output" | jq -r '.canonical_config_dir')" ]
}

# ── fail-closed: an ambiguous flag must never silently re-point a session ───────

@test "fail-closed: malformed flag file → DISABLED, canonical dir" {
  echo 'not json at all {{{' > "$CC_CONFIG_SLOT_FLAG_FILE"
  run "$C" next
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.claude-next" ]
}

@test "fail-closed: flag file present but enabled=false → canonical dir" {
  echo '{"enabled": false}' > "$CC_CONFIG_SLOT_FLAG_FILE"
  run "$C" next
  [ "$output" = "$HOME/.claude-next" ]
}

@test "fail-closed: enabled must be literal true, not a truthy string" {
  echo '{"enabled": "yes"}' > "$CC_CONFIG_SLOT_FLAG_FILE"
  run "$C" next
  [ "$output" = "$HOME/.claude-next" ]
}

@test "fail-closed: a JSON array (wrong shape) → DISABLED" {
  echo '[1,2,3]' > "$CC_CONFIG_SLOT_FLAG_FILE"
  run "$C" next
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.claude-next" ]
}

# ── the ON path (Variant A), exercised only with the flag explicitly set ────────

@test "ON: slot 0 keeps the canonical dir so the working credential is never orphaned" {
  enable_desharing
  canonical="$HOME/.claude-next"
  found_canonical=0
  for cls in default agent-teams research build desk probe; do
    run "$C" next --class "$cls"
    [ "$status" -eq 0 ]
    if [ "$output" = "$canonical" ]; then found_canonical=1; fi
  done
  [ "$found_canonical" -eq 1 ]
}

@test "ON: a class is stable — same class resolves to the same dir every time" {
  enable_desharing
  run "$C" next --class agent-teams
  first="$output"
  run "$C" next --class agent-teams
  [ "$output" = "$first" ]
  run "$C" next --class agent-teams
  [ "$output" = "$first" ]
}

@test "ON: at most 3 distinct dirs per account (bounded stores, bounded re-auths)" {
  enable_desharing
  for cls in a b c d e f g h i j k l m n o p; do
    "$C" next --class "$cls"
  done > "$BATS_TEST_TMPDIR/dirs"
  n="$(sort -u "$BATS_TEST_TMPDIR/dirs" | wc -l | tr -d ' ')"
  [ "$n" -le 3 ]
  [ "$n" -ge 1 ]
}

@test "ON: slot dirs stay under the account's own canonical prefix (no cross-account bleed)" {
  enable_desharing
  for cls in a b c d e f g h; do
    run "$C" next3 --class "$cls"
    [ "$status" -eq 0 ]
    case "$output" in "$HOME/.claude-tertiary"*) ;; *) return 1 ;; esac
  done
}

@test "ON: an unrecognised class still resolves deterministically, never errors" {
  enable_desharing
  run "$C" next --class 'weird/class name with spaces'
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

# ── argument handling ──────────────────────────────────────────────────────────

@test "unknown account → exit 2, names the known accounts" {
  run "$C" nope
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'unknown account'
  echo "$output" | grep -q 'next2'
}

@test "--class without a value → exit 2" {
  run "$C" next --class
  [ "$status" -eq 2 ]
}

@test "no args → usage, exit 2" {
  run "$C"
  [ "$status" -eq 2 ]
}

@test "--help → doc, exit 0" {
  run "$C" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'INERT BY DEFAULT'
}

@test "--status reports DISABLED by default and names the gating decision" {
  run "$C" --status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'DISABLED'
  echo "$output" | grep -qi 'E1'
}

@test "--status --json carries the flag path and slot arithmetic" {
  run "$C" --status --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.enabled')" = "false" ]
  [ "$(echo "$output" | jq -r '.slots_per_account')" = "3" ]
  [ "$(echo "$output" | jq -r '.renewals_per_month_if_enabled')" = "12" ]
}

@test "--status reflects an enabled flag" {
  enable_desharing
  run "$C" --status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'ENABLED'
}
