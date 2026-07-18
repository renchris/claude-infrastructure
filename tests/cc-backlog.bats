#!/usr/bin/env bats
# cc-backlog — durable, append-only work-ledger (JSONL). The desk's "what work
# exists / is claimed / is done" evidence store.
#   add    --project --title --dod-ref --source   (event-keyed id; idempotent re-add)
#   list   [--open|--all|--project <p>]
#   claim  <id> --by <sid>     done <id> --evidence <ref>     reopen <id>
#   compact [--older-than-days N]   (rewrite ONLY by age on terminal items)
# Status transitions are append-only records; current status = fold of the trail.
# Malformed lines are reported, never silently dropped.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
}

@test "add creates an open item; list --open shows it; id echoed" {
  run bash "$CB" add --project /repo/a --title "wire the thing" --source p14
  [ "$status" -eq 0 ]
  id="$output"
  [ -n "$id" ]
  run bash "$CB" list --open
  echo "$output" | grep -q "$id"
  echo "$output" | grep -q "wire the thing"
}

@test "id is deterministic — same project+title+source ⇒ same id" {
  a=$(bash "$CB" add --project /r --title T --source S)
  rm -f "$CC_BACKLOG_FILE"
  b=$(bash "$CB" add --project /r --title T --source S)
  [ "$a" = "$b" ]
}

@test "add is idempotent — re-add appends NO second add record" {
  bash "$CB" add --project /r --title T --source S >/dev/null
  bash "$CB" add --project /r --title T --source S >/dev/null
  n=$(grep -c '"event":"add"' "$CC_BACKLOG_FILE")
  [ "$n" -eq 1 ]
}

@test "append-only trail: add → claim → done leaves 3 records in order" {
  id=$(bash "$CB" add --project /r --title T --source S)
  bash "$CB" claim "$id" --by sid-123 >/dev/null
  bash "$CB" done "$id" --evidence commit:abc123 >/dev/null
  [ "$(wc -l < "$CC_BACKLOG_FILE" | tr -d ' ')" -eq 3 ]
  run cat "$CC_BACKLOG_FILE"
  echo "$output" | sed -n '1p' | grep -q '"event":"add"'
  echo "$output" | sed -n '2p' | grep -q '"event":"claim"'
  echo "$output" | sed -n '3p' | grep -q '"event":"done"'
}

@test "claim sets status claimed; done sets done (excluded from --open, shown in --all)" {
  id=$(bash "$CB" add --project /r --title T --source S)
  bash "$CB" claim "$id" --by sid-9 >/dev/null
  run bash "$CB" list --open
  echo "$output" | grep -q 'claimed'
  bash "$CB" done "$id" --evidence ref:1 >/dev/null
  run bash "$CB" list --open
  ! echo "$output" | grep -q "$id"
  run bash "$CB" list --all
  echo "$output" | grep -q "$id"
  echo "$output" | grep -q 'done'
}

@test "reopen returns a done item to open" {
  id=$(bash "$CB" add --project /r --title T --source S)
  bash "$CB" done "$id" --evidence ref:1 >/dev/null
  bash "$CB" reopen "$id" >/dev/null
  run bash "$CB" list --open
  echo "$output" | grep -q "$id"
  echo "$output" | grep -q 'open'
}

@test "list --project filters to one project" {
  bash "$CB" add --project /r/a --title Aye --source S >/dev/null
  bash "$CB" add --project /r/b --title Bee --source S >/dev/null
  run bash "$CB" list --project /r/a
  echo "$output" | grep -q 'Aye'
  ! echo "$output" | grep -q 'Bee'
}

@test "claim/done/reopen on an unknown id fail loud (non-zero + stderr)" {
  run bash "$CB" claim deadbeef00 --by x
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'unknown id'
}

@test "malformed line is reported to stderr and skipped, valid items still listed" {
  id=$(bash "$CB" add --project /r --title Good --source S)
  printf 'this is not json\n' >> "$CC_BACKLOG_FILE"
  run bash -c "bash '$CB' list --all 2>&1"
  echo "$output" | grep -qi 'malformed'
  echo "$output" | grep -q 'Good'          # valid item survives
}

@test "compact drops aged terminal items, keeps open + recent-terminal, preserves append-only" {
  # item1: added + done long ago (aged terminal ⇒ dropped)
  printf '{"id":"aaaaaaaaaaaa","ts":"2000-01-01T00:00:00Z","event":"add","project":"/r","title":"OldDone","source":"S"}\n' >> "$CC_BACKLOG_FILE"
  printf '{"id":"aaaaaaaaaaaa","ts":"2000-01-02T00:00:00Z","event":"done","evidence":"ref"}\n'                             >> "$CC_BACKLOG_FILE"
  # item2: open (kept regardless of age)
  printf '{"id":"bbbbbbbbbbbb","ts":"2000-01-01T00:00:00Z","event":"add","project":"/r","title":"StillOpen","source":"S"}\n' >> "$CC_BACKLOG_FILE"
  # item3: done in the far future (recent terminal ⇒ kept, both records)
  printf '{"id":"cccccccccccc","ts":"2099-01-01T00:00:00Z","event":"add","project":"/r","title":"RecentDone","source":"S"}\n' >> "$CC_BACKLOG_FILE"
  printf '{"id":"cccccccccccc","ts":"2099-01-02T00:00:00Z","event":"done","evidence":"ref"}\n'                                >> "$CC_BACKLOG_FILE"
  run bash "$CB" compact --older-than-days 30
  [ "$status" -eq 0 ]
  ! grep -q 'aaaaaaaaaaaa' "$CC_BACKLOG_FILE"     # aged terminal dropped
  grep -q 'bbbbbbbbbbbb' "$CC_BACKLOG_FILE"       # open kept
  [ "$(grep -c 'cccccccccccc' "$CC_BACKLOG_FILE")" -eq 2 ]   # recent terminal: both records kept
}

@test "compact never drops an OPEN item even if ancient (age-only on terminal)" {
  printf '{"id":"dddddddddddd","ts":"1999-01-01T00:00:00Z","event":"add","project":"/r","title":"Ancient","source":"S"}\n' >> "$CC_BACKLOG_FILE"
  run bash "$CB" compact --older-than-days 1
  [ "$status" -eq 0 ]
  grep -q 'dddddddddddd' "$CC_BACKLOG_FILE"
}

@test "compact preserves malformed lines (never silent-drop)" {
  printf 'garbage-not-json\n' >> "$CC_BACKLOG_FILE"
  printf '{"id":"eeeeeeeeeeee","ts":"2099-01-01T00:00:00Z","event":"add","project":"/r","title":"Keep","source":"S"}\n' >> "$CC_BACKLOG_FILE"
  run bash "$CB" compact --older-than-days 30
  grep -q 'garbage-not-json' "$CC_BACKLOG_FILE"
}
