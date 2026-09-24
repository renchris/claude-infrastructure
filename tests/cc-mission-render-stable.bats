#!/usr/bin/env bats
# cc-mission-render-stable — the mission board is rewritten only when its bytes change.
#
# WHY. ~/.claude/rules/00-mission-board.md is a memory file every live session has loaded, and
# Claude Code injects a diff of it (an `edited_text_file` attachment) into each of them whenever
# its bytes change. hooks/session-start.sh re-renders it at every session start; with a minute
# stamp and an unconditional tmp+mv, each start re-notified every live session: 546 injections /
# 3.79M chars over 14 days (docs/research/token-efficiency-2026-09-23/), each then re-read on
# every later request of the session that received it. The render is now date-stamped and skips
# the write when the bytes are unchanged.
#
# Hermetic: HOME is a scratch dir, and the one fixture row is a blocked-operator row with no
# source, paths or signoff, so evaluate() never shells out to git.

setup() {
  unset CC_BATS_ACTIVE
  export HOME="$BATS_TEST_TMPDIR/home"
  ROWS="$HOME/.claude/autonomy/customer/rows"
  BOARD="$HOME/.claude/rules/00-mission-board.md"
  CC_MISSION="$BATS_TEST_DIRNAME/../bin/cc-mission"
  mkdir -p "$ROWS"
  local now; now="$(date +%s)"
  printf '{"id":"t1","lead":"Test lead","venue":"Room","artifact":"floor-plan","state":"blocked-operator","blocked_since":%s,"budget_days":1,"next":"do the thing"}\n' \
    "$((now - 5 * 86400))" > "$ROWS/t1.json"
}

inode_of() { stat -f '%i' "$1" 2>/dev/null || stat -c '%i' "$1"; }

@test "an unchanged board is not rewritten: same inode, same bytes" {
  run "$CC_MISSION" render
  [ "$status" -eq 0 ]
  [ -f "$BOARD" ]
  grep -q 'do the thing' "$BOARD"
  local ino sum
  ino="$(inode_of "$BOARD")"
  sum="$(shasum "$BOARD")"
  run "$CC_MISSION" render
  [ "$status" -eq 0 ]
  [ "$(inode_of "$BOARD")" = "$ino" ]
  [ "$(shasum "$BOARD")" = "$sum" ]
}

@test "the render stamp has date resolution, not minutes" {
  run "$CC_MISSION" render
  [ "$status" -eq 0 ]
  grep -q "rendered $(date +%Y-%m-%d)" "$BOARD"
  run grep -Eq 'rendered [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}' "$BOARD"
  [ "$status" -ne 0 ]
}

@test "a changed row still rewrites the board" {
  run "$CC_MISSION" render
  [ "$status" -eq 0 ]
  perl -pi -e 's/do the thing/do the other thing/' "$ROWS/t1.json"
  run "$CC_MISSION" render
  [ "$status" -eq 0 ]
  grep -q 'do the other thing' "$BOARD"
}

@test "control: with the unchanged-bytes skip removed, the second render replaces the file" {
  # Proves the first test has power: the pre-fix unconditional tmp+mv gives the board a new
  # inode on every render even when the bytes are identical.
  local mut="$BATS_TEST_TMPDIR/cc-mission-mutant"
  python3 - "$CC_MISSION" "$mut" <<'EOF'
import sys
src = open(sys.argv[1]).read()
anchor = "        if path.read_text() == text:\n            return"
assert anchor in src, "anchor moved: re-anchor this control on the skip"
open(sys.argv[2], "w").write(src.replace(anchor, "        if False:\n            return"))
EOF
  chmod +x "$mut"
  run "$mut" render
  [ "$status" -eq 0 ]
  local ino; ino="$(inode_of "$BOARD")"
  run "$mut" render
  [ "$status" -eq 0 ]
  [ "$(inode_of "$BOARD")" != "$ino" ]
}

@test "slim arm: with ~/.claude/rules.slim present, it gets a compact board and the shared board stays full" {
  mkdir -p "$HOME/.claude/rules.slim"
  run env -u CC_MISSION_COMPACT "$CC_MISSION" render
  [ "$status" -eq 0 ]
  local slim="$HOME/.claude/rules.slim/00-mission-board.md"
  [ -f "$slim" ]
  grep -q '`t1`' "$slim"                      # compact rows carry the row id
  grep -q 'do the thing' "$BOARD"
  run grep -q '`t1`' "$BOARD"                   # the shared board is still the full render
  [ "$status" -ne 0 ]
  local ino; ino="$(inode_of "$slim")"
  run env -u CC_MISSION_COMPACT "$CC_MISSION" render
  [ "$(inode_of "$slim")" = "$ino" ]           # and the slim board obeys the same byte-compare skip
}

@test "no rules.slim dir: nothing is written there" {
  run env -u CC_MISSION_COMPACT "$CC_MISSION" render
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.claude/rules.slim" ]
}
