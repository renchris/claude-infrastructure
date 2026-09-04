#!/usr/bin/env bats
# scripts/drain-pick.sh — the ranked worklist a drain link reads instead of composing a query.
#
# THE FIXTURE LEDGER IS WRITTEN BY THE REAL bin/cc-backlog (memory
# `sibling-auditors-must-share-the-state-model`): the subject reads `cc-backlog list` for status and
# the raw store for claims and falsifiers, so a hand-rolled ledger would pin this suite's idea of
# the events rather than cc-backlog's.

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUBJECT="$REPO/scripts/drain-pick.sh"
  CB="$REPO/bin/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  export CC_DISPATCH_PROJECTS="$BATS_TEST_TMPDIR/projects.conf"
  printf 'claude-infrastructure  repo=x\nreso-management-app  repo=y\nagent-secrets  skip=no\n' > "$CC_DISPATCH_PROJECTS"
}

add() { bash "$CB" add --project "${2:-claude-infrastructure}" --title "$1" --source fx ${3:+--dod-ref "$3"}; }
ids() { bash "$SUBJECT" "$@" --json | jq -r '.[].id'; }

@test "only OPEN rows of the asked project are ranked; blocked, claimed and other projects are not" {
  o=$(add "an open row")
  b=$(add "a blocked row"); bash "$CB" block "$b" --needs "sudo something" >/dev/null 2>&1
  c=$(add "a claimed row"); bash "$CB" claim "$c" --by "$(hostname -s)-$$" >/dev/null 2>&1
  r=$(add "a reso row" reso-management-app)
  got="$(ids --project claude-infrastructure)"
  [ "$got" = "$o" ]
  [ -n "$b" ] && [ -n "$c" ] && [ -n "$r" ]
}

@test "cheapest adjudication first: falsifier, then dodRef, then plain, umbrellas last; oldest within a tier" {
  u=$(add "advance MASTER: fire gate — an umbrella")
  p=$(add "a plain row, oldest")
  sleep 1
  d=$(add "a row with a dodRef" claude-infrastructure docs/plans/X.md)
  f=$(add "a row with a falsifier")
  # A probe that exits non-zero is the only kind the store accepts on a live row.
  bash "$CB" falsify "$f" --probe 'false' >/dev/null 2>&1
  got="$(ids --project claude-infrastructure | paste -sd' ' -)"
  [ "$got" = "$f $d $p $u" ]
}

# THE THRASH CLASS IS HELD BACK, NOT RE-CLAIMED. DRAIN_CIRCUIT_2026-09-01 §1.3 measured 17 ids
# re-claimed 8–23 times with one ever reaching done; the 24th claimer is not a drain.
@test "rows claimed at or past --max-claims are held back and listed, not ranked" {
  t=$(add "a thrashed row")
  o=$(add "an ordinary row")
  for i in 1 2 3 4 5; do
    bash "$CB" claim "$t" --by "$(hostname -s)-$$" --force >/dev/null 2>&1
    bash "$CB" reopen "$t" --by "$(hostname -s)-$$" --force >/dev/null 2>&1
  done
  got="$(ids --project claude-infrastructure)"
  [ "$got" = "$o" ]
  run bash "$SUBJECT" --project claude-infrastructure
  [ "$(printf '%s' "$output" | grep -c "held: $t claims=5")" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'thrash_held=1')" -eq 1 ]
  # …and the ceiling is the flag, not the number.
  got6="$(ids --project claude-infrastructure --max-claims 6 | paste -sd' ' -)"
  [ "$got6" = "$t $o" ]
}

@test "--project all reads the non-skip projects from dispatch-projects.conf" {
  i=$(add "infra row")
  r=$(add "reso row" reso-management-app)
  s=$(add "secrets row" agent-secrets)
  got="$(ids --project all | sort | paste -sd' ' -)"
  want="$(printf '%s\n%s\n' "$i" "$r" | sort | paste -sd' ' -)"
  [ "$got" = "$want" ]
  [ -n "$s" ]
}

@test "--top bounds the table and the footer states how many were eligible" {
  for i in 1 2 3 4; do add "row $i" >/dev/null; done
  run bash "$SUBJECT" --project claude-infrastructure --top 2
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'eligible=4 shown=2 thrash_held=0')" -eq 1 ]
}

@test "an empty pile is an empty table with a zero footer, not an error" {
  d=$(add "a row already closed"); bash "$CB" "done" "$d" --evidence "landed abc1234" >/dev/null 2>&1
  run bash "$SUBJECT" --project claude-infrastructure
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'eligible=0 shown=0')" -eq 1 ]
}

# A MISSING STORE IS NOT AN EMPTY PILE (memory `lookup-miss-is-not-absence`): it refuses, loudly.
@test "an absent ledger refuses rather than rendering a clean zero" {
  run bash "$SUBJECT" --project claude-infrastructure
  [ "$status" -eq 4 ]
  [ "$(printf '%s' "$output" | grep -c 'no readable ledger')" -eq 1 ]
}
