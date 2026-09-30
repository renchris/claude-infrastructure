#!/usr/bin/env bats
# bin/cc-mission `add` (DESIGN §3 C7): the one verb that creates a board row outside cmd_seed.
# Hermetic: HOME is a temp dir, so the store and the rendered rules file are fixtures.

setup() {
  CM="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/bin/cc-mission"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset CC_MISSION_COMPACT
  ROWS="$HOME/.claude/autonomy/customer/rows"
}

@test "add creates a row that next/show/touch then see, and renders the board" {
  run "$CM" add fixturetenant.room.floor-plan --lead "Fixture Lead" --venue "Fixture Room" \
    --artifact floor-plan --tenant fixturetenant --next "trace the room" --path data/room.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"cc-mission:fixturetenant.room.floor-plan"* ]]
  [ "$(jq -r '.state, .owner, .paths[0]' "$ROWS/fixturetenant.room.floor-plan.json" | paste -sd' ' -)" = "lead agent data/room.json" ]
  [ -s "$HOME/.claude/rules/00-mission-board.md" ]    # the board re-rendered (it lists only STALE rows)
  run "$CM" touch fixturetenant.room.floor-plan --state drafted
  [ "$status" -eq 0 ]
}

@test "add never overwrites, refuses operator-only states and missing required fields" {
  "$CM" add a.b.c --lead L --venue V --artifact bottle-menu >/dev/null
  run "$CM" add a.b.c --lead L2 --venue V --artifact bottle-menu
  [ "$status" -eq 2 ]; [[ "$output" == *"row exists"* ]]
  [ "$(jq -r .lead "$ROWS/a.b.c.json")" = L ]
  run "$CM" add a.b.d --lead L --venue V --artifact x --state signed
  [ "$status" -eq 3 ]; [ ! -e "$ROWS/a.b.d.json" ]
  run "$CM" add a.b.e --lead L --artifact x
  [ "$status" -eq 2 ]; [[ "$output" == *"--venue"* ]]
  run "$CM" add 'Bad Id' --lead L --venue V --artifact x
  [ "$status" -eq 2 ]
}
