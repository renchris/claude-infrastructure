#!/usr/bin/env bats
# cc-backlog done --kind/--pointer (BACKLOG_MASTER W0 ledger-retraction.10): a bulk close names WHAT
# closed each row, as one of seven kinds with a pointer the tool checks. A single close without a
# kind behaves exactly as before.

setup() {
  export CC_BACKLOG_PROJECT_WARN=off CC_BACKLOG_KICK=off CC_BACKLOG_COVERAGE_WARN=off CC_BACKLOG_PREMISE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"; mkdir -p "$CC_DECISIONS_DIR"
  unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID CC_BACKLOG_CLOSE_REPO
  cd "$BATS_TEST_TMPDIR" || return 1
}

add() { bash "$CB" add --title "$1" --project closekind; }
kind_of() { bash "$CB" list --all --json | jq -r --arg i "$1" '.[]|select(.id==$i)|[.status,.closeKind,.closePointer]|join(" ")'; }

@test "close kind: a single close with no kind behaves as before" {
  a="$(add one)"
  run bash "$CB" "done" "$a" --evidence "plain"
  [ "$status" -eq 0 ]
  [ "$(kind_of "$a")" = "done  " ]
}

@test "close kind: landed needs a sha that is an ancestor of origin/main" {
  git init -q --bare "$BATS_TEST_TMPDIR/origin.git"
  git init -q "$BATS_TEST_TMPDIR/wc"
  git -C "$BATS_TEST_TMPDIR/wc" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one
  git -C "$BATS_TEST_TMPDIR/wc" remote add origin "$BATS_TEST_TMPDIR/origin.git"
  git -C "$BATS_TEST_TMPDIR/wc" push -q origin HEAD:main && git -C "$BATS_TEST_TMPDIR/wc" fetch -q origin
  on="$(git -C "$BATS_TEST_TMPDIR/wc" rev-parse HEAD)"
  git -C "$BATS_TEST_TMPDIR/wc" -c user.email=t@t -c user.name=t commit -q --allow-empty -m two
  off="$(git -C "$BATS_TEST_TMPDIR/wc" rev-parse HEAD)"
  export CC_BACKLOG_CLOSE_REPO="$BATS_TEST_TMPDIR/wc"
  a="$(add l1)"; b="$(add l2)"
  run bash "$CB" "done" "$a" --kind landed --pointer "$off" --evidence x
  [ "$status" -eq 2 ]
  run bash "$CB" "done" "$a" --kind landed --pointer "$on" --evidence x
  [ "$status" -eq 0 ]
  [ "$(kind_of "$a")" = "done landed $on" ]
}

@test "close kind: moved needs a dl ref that dl show resolves" {
  printf '#!/bin/bash\n[ "$1" = show ] && [ "$2" = subs.real ]\n' > "$BATS_TEST_TMPDIR/dl"; chmod +x "$BATS_TEST_TMPDIR/dl"
  export CC_BACKLOG_DL_BIN="$BATS_TEST_TMPDIR/dl"
  a="$(add m1)"
  run bash "$CB" "done" "$a" --kind moved --pointer subs.ghost
  [ "$status" -eq 2 ]
  run bash "$CB" "done" "$a" --kind moved --pointer subs.real --evidence "moved to dl"
  [ "$status" -eq 0 ]
}

@test "close kind: ruled needs a decision packet that is no longer open" {
  printf '{"id":"d1","status":"open"}' > "$CC_DECISIONS_DIR/d1.json"
  printf '{"id":"d2","status":"actioned"}' > "$CC_DECISIONS_DIR/d2.json"
  a="$(add r1)"
  run bash "$CB" "done" "$a" --kind ruled --pointer d1
  [ "$status" -eq 2 ]
  run bash "$CB" "done" "$a" --kind ruled --pointer d2 --evidence ruled
  [ "$status" -eq 0 ]
}

@test "close kind: falsified runs the probe (or the row's stored one) and needs exit 0" {
  a="$(bash "$CB" add --title f1 --project closekind --falsifier "test -e $BATS_TEST_TMPDIR/gone")"
  run bash "$CB" "done" "$a" --kind falsified --pointer stored
  [ "$status" -eq 2 ]
  : > "$BATS_TEST_TMPDIR/gone"
  run bash "$CB" "done" "$a" --kind falsified --pointer stored --evidence "probe passed"
  [ "$status" -eq 0 ]
}

@test "close kind: superseded, duplicate and stale check their pointers" {
  a="$(add s1)"; b="$(add s2)"; c="$(add s3)"; d="$(add s4)"
  run bash "$CB" "done" "$b" --kind duplicate --pointer "$b"
  [ "$status" -eq 2 ]
  run bash "$CB" "done" "$b" --kind duplicate --pointer "$a" --evidence dup
  [ "$status" -eq 0 ]
  run bash "$CB" "done" "$c" --kind superseded --pointer "$a" --evidence sup
  [ "$status" -eq 0 ]
  run bash "$CB" "done" "$d" --kind stale --pointer "$BATS_TEST_TMPDIR/nope.md"
  [ "$status" -eq 2 ]
  : > "$BATS_TEST_TMPDIR/receipt.md"
  run bash "$CB" "done" "$d" --kind stale --pointer "$BATS_TEST_TMPDIR/receipt.md" --evidence stale
  [ "$status" -eq 0 ]
}

@test "close kind: a bulk close with no kind or pointer is refused row by row" {
  a="$(add b1)"; b="$(add b2)"
  run bash "$CB" "done" "$a" "$b" --evidence "disproved one number"
  [ "$status" -eq 4 ]
  [ "$(kind_of "$a")" = "open  " ]
  printf '%s\tduplicate\t\tno pointer\n%s\tduplicate\t%s\tok\n' "$a" "$b" "$a" > rows.tsv
  run bash "$CB" "done" --from-file rows.tsv
  [ "$status" -eq 4 ]
  [[ "$output" == *"needs a --pointer"* ]] || false
  [ "$(kind_of "$a")" = "open  " ]
  [ "$(kind_of "$b")" = "done duplicate $a" ]
}
