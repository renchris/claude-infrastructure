#!/usr/bin/env bats
# cc-mission compact render (flagged). Hermetic: HOME is a temp dir and every row is
# blocked-operator, so evaluate() never shells out to git.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  ROWS="$HOME/.claude/autonomy/customer/rows"
  BOARD="$HOME/.claude/rules/00-mission-board.md"
  CCM="$BATS_TEST_DIRNAME/../bin/cc-mission"
  mkdir -p "$ROWS"
  python3 - "$ROWS" <<'PY'
import json, sys, time
for i in (1, 2):
    json.dump({"id": f"t.row{i}", "lead": "L", "venue": f"V{i}", "artifact": "a",
               "repo": "", "state": "blocked-operator", "budget_days": 1,
               "blocked_since": time.time() - 5 * 86400, "next": "word " * 400},
              open(f"{sys.argv[1]}/t.row{i}.json", "w"))
PY
}

@test "flag off: the full render carries every row's whole next text" {
  run env -u CC_MISSION_COMPACT python3 "$CCM" render
  [ "$status" -eq 0 ]
  grep -q 'What to do with this' "$BOARD"
  [ "$(wc -c < "$BOARD" | tr -d ' ')" -gt 4000 ]
}

@test "flag file on: one line per row, next cut to the headline bound, id shown" {
  touch "$HOME/.claude/autonomy/customer/render-compact"
  run env -u CC_MISSION_COMPACT python3 "$CCM" render
  [ "$status" -eq 0 ]
  [ "$(grep -c '^- ' "$BOARD")" -eq 2 ]
  grep -q '… `t.row1`$' "$BOARD"
  [ "$(wc -c < "$BOARD" | tr -d ' ')" -lt 1500 ]
}

@test "CC_MISSION_COMPACT=0 overrides the flag file" {
  touch "$HOME/.claude/autonomy/customer/render-compact"
  run env CC_MISSION_COMPACT=0 python3 "$CCM" render
  [ "$status" -eq 0 ]
  grep -q 'What to do with this' "$BOARD"
}

@test "touch --headline: over 200 chars is refused; a set headline is what renders" {
  run python3 "$CCM" touch t.row1 --headline "$(printf 'x%.0s' $(seq 201))"
  [ "$status" -eq 2 ]
  run env CC_MISSION_COMPACT=1 python3 "$CCM" touch t.row1 --headline "call the venue"
  [ "$status" -eq 0 ]
  grep -q 'call the venue `t.row1`$' "$BOARD"
}

@test "show prints one row in full; an unknown id exits 2" {
  run python3 "$CCM" show t.row2
  [ "$status" -eq 0 ]
  [ "${#output}" -gt 2000 ]
  run python3 "$CCM" show t.nope
  [ "$status" -eq 2 ]
}
