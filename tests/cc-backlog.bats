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

# ── blocked-on-operator (parks an item OUT of the dispatch wave) ────────────────
@test "block sets status blocked + carries needs; unblock returns to open" {
  id=$(bash "$CB" add --project /r --title T --source S)
  bash "$CB" block "$id" --needs "run claude-kimi set-key" >/dev/null
  run bash "$CB" list --all --json
  echo "$output" | jq -e --arg i "$id" '.[]|select(.id==$i)|.status=="blocked"'
  echo "$output" | jq -e --arg i "$id" '.[]|select(.id==$i)|.needs=="run claude-kimi set-key"'
  bash "$CB" unblock "$id" >/dev/null
  run bash "$CB" list --all --json
  echo "$output" | jq -e --arg i "$id" '.[]|select(.id==$i)|.status=="open"'
}

@test "block WITHOUT --needs fails loud (the operator step IS the payload)" {
  id=$(bash "$CB" add --project /r --title T --source S)
  run bash "$CB" block "$id"
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi 'needs'
}

@test "a blocked item still shows in --open (desk sees it) but reads 'blocked', not 'open'" {
  id=$(bash "$CB" add --project /r --title Parked --source S)
  bash "$CB" block "$id" --needs "operator: launchctl bootout" >/dev/null
  run bash "$CB" list --open
  echo "$output" | grep -q "$id"                 # desk still sees it
  echo "$output" | grep -q 'blocked'             # …as blocked, NOT open
  echo "$output" | grep -q 'launchctl bootout'   # the pending operator step is surfaced
}

@test "list --blocked filters to ONLY blocked items and carries needs in --json" {
  a=$(bash "$CB" add --project /r --title Aye --source A)
  b=$(bash "$CB" add --project /r --title Bee --source B)
  bash "$CB" block "$b" --needs "operator: set the API key" >/dev/null
  run bash "$CB" list --blocked
  echo "$output" | grep -q "$b"
  ! echo "$output" | grep -q "$a"                # open item excluded
  run bash "$CB" list --blocked --json
  echo "$output" | jq -e --arg i "$b" 'length==1 and (.[0].id==$i) and (.[0].needs=="operator: set the API key")'
}

@test "append-only: add → block → unblock leaves 3 records; the trail is legible" {
  id=$(bash "$CB" add --project /r --title T --source S)
  bash "$CB" block "$id" --needs step >/dev/null
  bash "$CB" unblock "$id" >/dev/null
  [ "$(wc -l < "$CC_BACKLOG_FILE" | tr -d ' ')" -eq 3 ]
  run cat "$CC_BACKLOG_FILE"
  echo "$output" | sed -n '2p' | grep -q '"event":"block"'
  echo "$output" | sed -n '2p' | grep -q '"needs":"step"'
  echo "$output" | sed -n '3p' | grep -q '"event":"unblock"'
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

# ── reap: stale-claim maintenance (dead-worker timeout → reopen · thrash → block) ───────────────
# A claim whose worker DIED stays `claimed` forever (cc-dispatch fires only status=="open" ⇒ work
# STRANDS); a spawn-fail/land-conflict item THRASHES (claim→reopen→claim…). `reap` folds the trail
# and, append-only + idempotent: BLOCKS thrash (≥ MAX_THRASH fast claim→reopen cycles), REOPENS a
# dead-worker stale claim (idle > STALE_CLAIM_S, claimer not live), and BLOCKS (not reopens) once a
# still-stale claim passes MAX_ATTEMPTS. Clock is pinned via jq fromdateiso8601 so ages are exact;
# host-pid liveness uses REAL kill -0 (a dead PID = 2147483647, a live one = the test's own $$).
reap_env() {
  # "now" = 2026-01-01T02:00:00Z. A claim at 00:00:00Z ⇒ 7200s old (> 5400 stale); at 01:59:00Z ⇒ 60s.
  export CC_BACKLOG_NOW; CC_BACKLOG_NOW="$(jq -n '"2026-01-01T02:00:00Z"|fromdateiso8601')"
  export CC_BACKLOG_STALE_CLAIM_S=5400 CC_BACKLOG_MAX_THRASH=2 CC_BACKLOG_MAX_ATTEMPTS=3 CC_BACKLOG_THRASH_WINDOW_S=90
  # default liveness oracle: an EMPTY live registry ⇒ no session-shaped claimer is ever live.
  printf '#!/bin/bash\necho "[]"\n' > "$BATS_TEST_TMPDIR/nosess"; chmod +x "$BATS_TEST_TMPDIR/nosess"
  export CC_BACKLOG_SESSIONS_BIN="$BATS_TEST_TMPDIR/nosess"
  HOST="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo localhost)"
}
rec() { printf '%s\n' "$1" >> "$CC_BACKLOG_FILE"; }
status_of() { bash "$CB" list --all --json | jq -r --arg i "$1" '.[]|select(.id==$i)|.status'; }

@test "reap: persistent thrash (≥MAX_THRASH fast claim→reopen cycles) → blocked, needs names the cause" {
  reap_env
  rec '{"id":"thrashaaaa01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Thrash"}'
  rec '{"id":"thrashaaaa01","ts":"2026-01-01T00:00:10Z","event":"claim","by":"h-1"}'
  rec '{"id":"thrashaaaa01","ts":"2026-01-01T00:00:14Z","event":"reopen"}'   # cycle 1: 4s < window
  rec '{"id":"thrashaaaa01","ts":"2026-01-01T00:00:20Z","event":"claim","by":"h-2"}'
  rec '{"id":"thrashaaaa01","ts":"2026-01-01T00:00:24Z","event":"reopen"}'   # cycle 2: 4s < window
  run bash "$CB" reap
  [ "$status" -eq 0 ]
  [ "$(status_of thrashaaaa01)" = blocked ]
  bash "$CB" list --all --json | jq -e --arg i thrashaaaa01 '.[]|select(.id==$i)|.needs|test("thrash")'
}

@test "reap: ONE fast cycle (< MAX_THRASH) does NOT block — stays as it folded (open)" {
  reap_env
  rec '{"id":"onecyc00bb01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"One"}'
  rec '{"id":"onecyc00bb01","ts":"2026-01-01T00:00:10Z","event":"claim","by":"h-1"}'
  rec '{"id":"onecyc00bb01","ts":"2026-01-01T00:00:14Z","event":"reopen"}'   # only 1 cycle
  run bash "$CB" reap
  [ "$status" -eq 0 ]
  [ "$(status_of onecyc00bb01)" = open ]
}

@test "reap: a slow claim→reopen (gap > THRASH_WINDOW_S) is NOT a fast-fail cycle" {
  reap_env
  rec '{"id":"slowcyc0cc01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Slow"}'
  rec '{"id":"slowcyc0cc01","ts":"2026-01-01T00:00:00Z","event":"claim","by":"h-1"}'
  rec '{"id":"slowcyc0cc01","ts":"2026-01-01T00:10:00Z","event":"reopen"}'   # 600s gap ≫ 90s window
  rec '{"id":"slowcyc0cc01","ts":"2026-01-01T00:11:00Z","event":"claim","by":"h-2"}'
  rec '{"id":"slowcyc0cc01","ts":"2026-01-01T00:21:00Z","event":"reopen"}'   # 600s gap ≫ window
  run bash "$CB" reap
  [ "$status" -eq 0 ]
  [ "$(status_of slowcyc0cc01)" = open ]                # not thrash, not claimed ⇒ untouched
}

@test "reap: dead-worker stale claim (idle>STALE, claimer PID dead) → reopened, tagged by cc-backlog-reap" {
  reap_env
  rec '{"id":"stale000dd01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Stale"}'
  rec "{\"id\":\"stale000dd01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"  # 7200s old, dead pid
  run bash "$CB" reap
  [ "$status" -eq 0 ]
  [ "$(status_of stale000dd01)" = open ]
  # the reopen is auditable as the reaper's
  tail -1 "$CC_BACKLOG_FILE" | jq -e '.event=="reopen" and .by=="cc-backlog-reap"'
}

@test "reap: FRESH claim (age < STALE_CLAIM_S) is left alone (worker still within its window)" {
  reap_env
  rec '{"id":"fresh000ee01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Fresh"}'
  rec "{\"id\":\"fresh000ee01\",\"ts\":\"2026-01-01T01:59:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"  # 60s old
  run bash "$CB" reap
  [ "$status" -eq 0 ]
  [ "$(status_of fresh000ee01)" = claimed ]            # untouched
}

@test "reap: stale claim but claimer PID is LIVE → NOT reopened (never double-dispatch a live worker)" {
  reap_env
  rec '{"id":"livepid0ff01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Live"}'
  rec "{\"id\":\"livepid0ff01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-$$\"}"  # 7200s old, but $$ alive
  run bash "$CB" reap
  [ "$status" -eq 0 ]
  [ "$(status_of livepid0ff01)" = claimed ]            # kill -0 $$ succeeds ⇒ skipped
}

@test "reap: stale claim whose claimer is a LIVE registry session → NOT reopened" {
  reap_env
  printf '#!/bin/bash\necho %s\n' "'[{\"paneUUID\":\"PANE-LIVE-1\",\"name\":\"wkr\"}]'" > "$BATS_TEST_TMPDIR/livesess"
  chmod +x "$BATS_TEST_TMPDIR/livesess"; export CC_BACKLOG_SESSIONS_BIN="$BATS_TEST_TMPDIR/livesess"
  rec '{"id":"livereg0gg01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Reg"}'
  rec '{"id":"livereg0gg01","ts":"2026-01-01T00:00:00Z","event":"claim","by":"PANE-LIVE-1"}'   # 7200s old, session id
  run bash "$CB" reap
  [ "$status" -eq 0 ]
  [ "$(status_of livereg0gg01)" = claimed ]            # registry says PANE-LIVE-1 is live ⇒ skipped
}

@test "reap: bounded — a stale claim past MAX_ATTEMPTS is BLOCKED, not reopened (no slow-loop)" {
  reap_env
  rec '{"id":"bound000hh01","ts":"2025-12-31T21:00:00Z","event":"add","project":"/r","title":"Bound"}'
  rec '{"id":"bound000hh01","ts":"2025-12-31T22:00:00Z","event":"claim","by":"h-1"}'
  rec '{"id":"bound000hh01","ts":"2025-12-31T22:30:00Z","event":"reopen","by":"cc-backlog-reap"}'  # 1800s gap, not fast
  rec '{"id":"bound000hh01","ts":"2025-12-31T23:00:00Z","event":"claim","by":"h-2"}'
  rec '{"id":"bound000hh01","ts":"2025-12-31T23:30:00Z","event":"reopen","by":"cc-backlog-reap"}'  # not fast
  rec "{\"id\":\"bound000hh01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"  # 3rd claim, 7200s old, dead
  run bash "$CB" reap
  [ "$status" -eq 0 ]
  [ "$(status_of bound000hh01)" = blocked ]            # totalClaims≥3 ⇒ block instead of a 4th reopen
  bash "$CB" list --all --json | jq -e --arg i bound000hh01 '.[]|select(.id==$i)|.needs|test("dead-worker stall")'
}

@test "reap --dry-run: classifies but writes NOTHING (append-only file unchanged)" {
  reap_env
  rec '{"id":"dryrun00ii01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Dry"}'
  rec "{\"id\":\"dryrun00ii01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"
  before="$(wc -l < "$CC_BACKLOG_FILE" | tr -d ' ')"
  run bash "$CB" reap --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'WOULD-REOPEN'
  echo "$output" | grep -qi 'no writes'
  [ "$(wc -l < "$CC_BACKLOG_FILE" | tr -d ' ')" -eq "$before" ]   # nothing appended
  [ "$(status_of dryrun00ii01)" = claimed ]                       # still claimed
}

@test "reap: NEVER touches done or already-blocked items (terminal / parked)" {
  reap_env
  # a done item (even if it had a stale-looking claim in its trail)
  rec '{"id":"doneitm0jj01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Done"}'
  rec "{\"id\":\"doneitm0jj01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"
  rec '{"id":"doneitm0jj01","ts":"2026-01-01T00:05:00Z","event":"done","evidence":"sha:1"}'
  # an operator-blocked item
  id2=$(bash "$CB" add --project /r --title Parked --source S)
  bash "$CB" block "$id2" --needs "operator: set key" >/dev/null
  before="$(wc -l < "$CC_BACKLOG_FILE" | tr -d ' ')"
  run bash "$CB" reap
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CC_BACKLOG_FILE" | tr -d ' ')" -eq "$before" ]   # no new events for done/blocked
  [ "$(status_of doneitm0jj01)" = done ]
  [ "$(status_of "$id2")" = blocked ]
}

@test "reap: clean backlog (no stale/thrash) → 0 reopened, 0 blocked, exit 0 (no field-align error)" {
  reap_env
  bash "$CB" add --project /r --title Open1 --source S >/dev/null   # a plain open item (empty claimBy)
  run bash "$CB" reap
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '0 reopened, 0 blocked'
  ! echo "$output" | grep -qi 'integer expression'   # empty claimBy must not shift columns
}

@test "reap: a claimless open item (empty claimBy) does NOT misalign later columns" {
  # Regression: a US-delimited row is used precisely because bash `read` COALESCES adjacent TABS
  # (whitespace IFS) — an empty claimBy would drop the field and shift `fast`→empty→a spurious
  # 'integer expression' error, masking real work. Proven by mixing a claimless open item with a
  # genuine dead-worker stale claim: the stale one must STILL reopen (columns stayed aligned).
  reap_env
  bash "$CB" add --project /r --title OpenNoClaim --source S >/dev/null            # open, claimBy=""
  rec '{"id":"mixstale0z01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Stale"}'
  rec "{\"id\":\"mixstale0z01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"
  run bash "$CB" reap
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qi 'integer expression'   # no misalignment error on the empty field
  [ "$(status_of mixstale0z01)" = open ]             # the stale claim still reopened (columns aligned)
}

@test "reap is idempotent — a second immediate run is a no-op (already reopened/blocked)" {
  reap_env
  rec '{"id":"idem0000kk01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Idem"}'
  rec "{\"id\":\"idem0000kk01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"
  bash "$CB" reap >/dev/null                            # reopens it (now open)
  n1="$(wc -l < "$CC_BACKLOG_FILE" | tr -d ' ')"
  run bash "$CB" reap                                   # open + no fast cycles ⇒ nothing to do
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '0 reopened, 0 blocked'
  [ "$(wc -l < "$CC_BACKLOG_FILE" | tr -d ' ')" -eq "$n1" ]   # no further appends
}
