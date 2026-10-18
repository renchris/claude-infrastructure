#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
#   Structurally false under bats: every @test body is its own subshell.
#
# bin/it2-kitty — two lr-wake incident fixes (2026-10-18, REPORT §4 Wave D) at the shim's one kitty
# chokepoint, kt():
#   1. NO TABS. `kitty @ launch --type=tab` is refused with rc 2 unless CC_ALLOW_TAB=1 (a restore
#      replaying a recorded layout). No verb builds a tab today, so the refusal is pinned on the
#      primitive itself, extracted from the file exactly as written, plus an end-to-end CONTROL that
#      the split verb still launches.
#   2. KEYSTROKE PROVENANCE. Every send-text writes {ts, pane, caller, sid, sha256, head40, …} to
#      ~/.claude/logs/pane-keys.jsonl. Overnight four sessions recorded an `/exit` their own
#      foreground never sent, and nothing could say who typed it.
#
# RED on origin/main: kt() has no refusal (case 1 reaches kitty, rc 0) and nothing writes the log.
# Hermetic: fake socket + fake kitty binary, HOME per test.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  K="$REPO/bin/it2-kitty"
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/sock"
  export CC_TERM_KITTY="$BATS_TEST_TMPDIR/fake-kitty"
  export CC_PANE_CMD_DIR="$BATS_TEST_TMPDIR/cmd"; mkdir -p "$CC_PANE_CMD_DIR"
  export CC_FIRE_CAPACITY_GATE=off
  unset CC_PANE_CMD CC_PANE_CMD_INTERACTIVE CC_ALLOW_TAB CC_PANE_KEYS_LOG CC_SPAWN_CHAIN
  export KLOG="$BATS_TEST_TMPDIR/kitty.log"; : > "$KLOG"
  export CLAUDE_CODE_SESSION_ID=5a6b8a40-0000-4000-8000-00000000d00d
  KEYS="$HOME/.claude/logs/pane-keys.jsonl"
  cat > "$CC_TERM_KITTY" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$KLOG"
verb=""
for a in "$@"; do case "$a" in @|--to|unix:*) continue ;; *) verb="$a"; break ;; esac; done
case "$verb" in
  ls) echo '[{"id":1,"tabs":[{"id":1,"windows":[{"id":42,"title":"t","cwd":"/tmp","pid":9,"in_alternate_screen":true}]}]}]' ;;
  launch) echo 77 ;;
esac
exit 0
SH
  chmod +x "$CC_TERM_KITTY"
}

# kt() and the helpers it calls, extracted from the shipped file (never re-typed here)
load_kt() {
  err(){ printf 'it2-kitty: %s\n' "$*" >&2; }
  local fn
  for fn in _argv_has_tab _pane_keys_row _pane_keys_log kt; do
    eval "$(awk -v n="$fn" '$0 ~ "^" n "\\(\\) *\\{" {p = 1} p {print} p && /^}/ {exit}' "$K")"
    declare -F "$fn" >/dev/null || { echo "could not extract $fn from $K"; return 1; }
  done
  # shellcheck disable=SC2034  # globals the kt() extracted from the shipped file reads
  KITTY_BIN="$CC_TERM_KITTY" TIMEOUT_BIN="" TIMEOUT_S=15 verb="test"
}

@test "kt refuses \`launch --type=tab\` with rc 2 and never reaches kitty" {
  load_kt
  run kt launch --type=tab --keep-focus --match id:42 /bin/zsh
  [ "$status" -eq 2 ]
  [[ "$output" == *"kitty tabs are retired"* ]] || { echo "$output"; false; }
  [ ! -s "$KLOG" ]
}

@test "kt refuses the two-token spelling \`--type tab\` too" {
  load_kt
  run kt launch --type tab /bin/zsh
  [ "$status" -eq 2 ]
  [ ! -s "$KLOG" ]
}

@test "CC_ALLOW_TAB=1 (a recorded-layout restore) lets the tab through" {
  load_kt
  CC_ALLOW_TAB=1 run kt launch --type=tab --match id:42 /bin/zsh
  [ "$status" -eq 0 ]
  grep -qF -- 'launch --type=tab --match id:42' "$KLOG"
}

@test "CONTROL: a window launch passes, and --type=tab AFTER -- (program text) is not an option" {
  load_kt
  run kt launch --type=window --location=vsplit /bin/echo hi
  [ "$status" -eq 0 ]
  run kt launch --type=os-window -- /bin/echo --type=tab
  [ "$status" -eq 0 ]
  [ "$(grep -c ' launch ' "$KLOG")" -eq 2 ]
}

@test "CONTROL end-to-end: \`session split\` still launches a window, and never a tab" {
  run "$K" session split -v -s 42
  [ "$status" -eq 0 ]
  grep -qF -- 'launch --type=window --location=vsplit' "$KLOG"
  ! grep -q -- '--type=tab' "$KLOG" || false
}

@test "session send writes one pane-keys row: pane, sending sid, sha256 and head40 of the bytes" {
  run "$K" session send -s 42 "/exit"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$KEYS" | tr -d ' ')" -eq 1 ]
  want="$(printf '%s' /exit | shasum -a 256 | cut -d' ' -f1)"
  run jq -r '[.pane, .sid, .sha256, .head40, .verb, (.rc|tostring)] | join(" ")' "$KEYS"
  [ "$output" = "42 $CLAUDE_CODE_SESSION_ID $want /exit send 0" ] || { echo "$output"; false; }
  [ -n "$(jq -r .caller "$KEYS")" ]
  [ -n "$(jq -r .ts "$KEYS")" ]
}

@test "the caller is the exported spawn chain when there is one; head40 is cut at 40 characters" {
  long="$(printf 'x%.0s' $(seq 60))"
  # handoff-fire exports its chain; the shim joins it (scripts/lib/pane-spawn-log.sh pushes at source time)
  CC_SPAWN_CHAIN="handoff-fire.sh" run "$K" session type -s 42 "$long"
  [ "$status" -eq 0 ]
  [ "$(jq -r .caller "$KEYS")" = "handoff-fire.sh>it2-kitty" ]
  [ "$(jq -r '.head40 | length' "$KEYS")" -eq 40 ]
  [ "$(jq -r .verb "$KEYS")" = type ]
}

@test "CC_PANE_KEYS_LOG=off writes nothing, and the send still goes through" {
  CC_PANE_KEYS_LOG=off run "$K" session send -s 42 "hello"
  [ "$status" -eq 0 ]
  [ ! -e "$KEYS" ]
  grep -qF -- 'send-text --match id:42 -- hello' "$KLOG"
}

@test "a read (get-text) is not a keystroke and writes no row" {
  run "$K" session read -s 42
  [ "$status" -eq 0 ]
  [ ! -e "$KEYS" ]
}
