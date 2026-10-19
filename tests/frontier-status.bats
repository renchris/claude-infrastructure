#!/usr/bin/env bats
# hooks/frontier-status.sh — the SessionStart frontier line is silent unless a hole is OPEN
# (startup-hooks README §2 #12, A4-R4): with 0 holes it repeated CLAUDE.md on every start, and its
# "agent auto-escalates" contradicted CLAUDE.md ("it is not automatic").

setup() {
  HOOK="$BATS_TEST_DIRNAME/../hooks/frontier-status.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  PROJ="$BATS_TEST_TMPDIR/proj"; mkdir -p "$PROJ/docs/research"
  mk_cfg 2099-12-31
}

mk_cfg() {  # $1 = window end date
  printf 'roles:\n  lead_default: claude-opus-5-5\nfrontier_access:\n  active: true\n  model: claude-fable-5-1\n  end: "%s"\nother:\n  x: 1\n' \
    "$1" > "$HOME/.claude/model-config.yaml"
}
mk_holes() {  # $1 = OPEN count, plus one CLOSED hole that must not count
  local i=1; : > "$PROJ/docs/research/FRONTIER_HOLES.md"
  # a counted loop, not `seq 1 "$1"`: BSD seq counts DOWN, so `seq 1 0` prints 1 and 0
  while [ "$i" -le "$1" ]; do
    printf '### H-%s — something OPEN\n' "$i" >> "$PROJ/docs/research/FRONTIER_HOLES.md"; i=$((i + 1))
  done
  printf '### H-99 — old one CLOSED\n' >> "$PROJ/docs/research/FRONTIER_HOLES.md"
}
run_hook() { run bash -c "cd '$PROJ' && bash '$HOOK' </dev/null"; }

@test "window open, 0 OPEN holes ⇒ silent" {
  mk_holes 0
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "window open, no ledger at all ⇒ silent" {
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "window open, 2 OPEN holes ⇒ one line naming them, and it does not claim auto-escalation" {
  mk_holes 2
  run_hook
  [ "$status" -eq 0 ] || false
  [ "${#lines[@]}" -eq 1 ] || false
  [[ "$output" == "Frontier: 2 OPEN hole(s) in docs/research/FRONTIER_HOLES.md · claude-fable-5-1 window open→2099-12-31"* ]] || false
  [[ "$output" == *"not automatic"* ]] || false
  [[ "$output" != *"auto-escalates"* ]]
}

@test "window closed: OPEN holes ⇒ the parked line; none ⇒ silent" {
  mk_cfg 2020-01-01
  mk_holes 1
  run_hook
  [[ "$output" == "Frontier: window closed · 1 OPEN hole(s) parked"* ]] || false
  mk_holes 0
  run_hook
  [ -z "$output" ]
}
