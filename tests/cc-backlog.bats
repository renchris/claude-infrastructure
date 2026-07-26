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

# NEGATIVE assertions must NOT be written `! cmd`: bash exempts a `!`-inverted command from set -e, so
# such a line only ever fails the test when it is the LAST line of the body — 4 of this file's were
# silently vacuous (audited 2026-07-25). These return non-zero directly, so errexit catches them anywhere.
refute_match()   { [ "$(printf '%s' "$1" | grep -c "$2")"  -eq 0 ]; }
refute_imatch()  { [ "$(printf '%s' "$1" | grep -ci "$2")" -eq 0 ]; }
refute_in_file() { [ "$(grep -c "$1" "$2")" -eq 0 ]; }

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
  refute_match "$output" "$id"
  run bash "$CB" list --all
  echo "$output" | grep -q "$id"
  echo "$output" | grep -q 'done'
}

# ── reopen guards: done-terminal + live-claim (incident 2026-07-20, a60d62a215f1 → 6488617) ─────
# `reopen` was the one transition with NO status check: it would resurrect a terminal item and it
# would yank an item out from under a still-running worker. Both land the item back on status
# "open" — cc-dispatch's exact fire predicate — so the next tick claimed + spawned a SECOND peer
# onto work that was already in progress / already landed. Two guards, both `--force`-overridable.
# Liveness is stubbed to an EMPTY registry so a session-shaped claimer is never accidentally live;
# host-pid liveness uses REAL kill -0 (dead = 2147483647, live = the test's own $$).
guard_env() {
  printf '#!/bin/bash\necho "[]"\n' > "$BATS_TEST_TMPDIR/nosess"; chmod +x "$BATS_TEST_TMPDIR/nosess"
  export CC_BACKLOG_SESSIONS_BIN="$BATS_TEST_TMPDIR/nosess"
  HOST="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo localhost)"
}
st_of() { bash "$CB" list --all --json | jq -r --arg i "$1" '.[]|select(.id==$i)|.status'; }

@test "reopen of a DONE item is REFUSED (rc 4), appends NOTHING, stays done" {
  guard_env
  id=$(bash "$CB" add --project /r --title T --source S)
  bash "$CB" done "$id" --evidence "6488617 the fix" >/dev/null
  before="$(wc -l < "$CC_BACKLOG_FILE" | tr -d ' ')"
  run bash "$CB" reopen "$id"
  [ "$status" -eq 4 ]
  echo "$output" | grep -qi 'terminal'
  echo "$output" | grep -q '6488617'          # the refusal SHOWS what already landed
  echo "$output" | grep -q -- '--force'       # …and names the deliberate override
  [ "$(wc -l < "$CC_BACKLOG_FILE" | tr -d ' ')" -eq "$before" ]   # append-only ledger untouched
  [ "$(st_of "$id")" = done ]
}

@test "reopen --force DOES return a done item to open and records force:true" {
  guard_env
  id=$(bash "$CB" add --project /r --title T --source S)
  bash "$CB" done "$id" --evidence ref:1 >/dev/null
  run bash "$CB" reopen "$id" --force
  [ "$status" -eq 0 ]
  [ "$(st_of "$id")" = open ]
  run bash "$CB" list --open
  echo "$output" | grep -q "$id"
  tail -1 "$CC_BACKLOG_FILE" | jq -e '.event=="reopen" and .force==true'   # the override is auditable
}

@test "wasDone latches on done and is cleared ONLY by a forced reopen" {
  guard_env
  id=$(bash "$CB" add --project /r --title T --source S)
  bash "$CB" list --all --json | jq -e --arg i "$id" '.[]|select(.id==$i)|.wasDone==false'
  bash "$CB" done "$id" --evidence ref:1 >/dev/null
  bash "$CB" list --all --json | jq -e --arg i "$id" '.[]|select(.id==$i)|.wasDone==true'
  # a hand-appended UNFORCED reopen (bypassing the CLI guard) re-opens the status but must NOT
  # clear the latch — that is what keeps cc-dispatch from re-firing landed work.
  printf '{"id":"%s","ts":"2026-07-20T09:00:00Z","event":"reopen"}\n' "$id" >> "$CC_BACKLOG_FILE"
  bash "$CB" list --all --json | jq -e --arg i "$id" '.[]|select(.id==$i)|.status=="open" and .wasDone==true'
  bash "$CB" reopen "$id" --force >/dev/null
  bash "$CB" list --all --json | jq -e --arg i "$id" '.[]|select(.id==$i)|.wasDone==false'
}

@test "reopen of a LIVE claim by a FOREIGN caller is REFUSED (rc 4) — the double-dispatch bug" {
  guard_env
  id=$(bash "$CB" add --project /r --title T --source S)
  bash "$CB" claim "$id" --by "$HOST-$$" >/dev/null       # $$ is alive
  before="$(wc -l < "$CC_BACKLOG_FILE" | tr -d ' ')"
  run bash "$CB" reopen "$id"                              # no --by ⇒ foreign
  [ "$status" -eq 4 ]
  echo "$output" | grep -qi 'live'
  [ "$(wc -l < "$CC_BACKLOG_FILE" | tr -d ' ')" -eq "$before" ]
  [ "$(st_of "$id")" = claimed ]                           # worker keeps its item
}

@test "the claimer may release its OWN live claim (--by <claimer>) — cc-dispatch's rollback" {
  guard_env
  id=$(bash "$CB" add --project /r --title T --source S)
  bash "$CB" claim "$id" --by "$HOST-$$" >/dev/null
  run bash "$CB" reopen "$id" --by "$HOST-$$"
  [ "$status" -eq 0 ]
  [ "$(st_of "$id")" = open ]
}

@test "reopen of a DEAD claim needs no --force (reap's path / normal recovery)" {
  guard_env
  id=$(bash "$CB" add --project /r --title T --source S)
  bash "$CB" claim "$id" --by "$HOST-2147483647" >/dev/null   # dead pid
  run bash "$CB" reopen "$id"
  [ "$status" -eq 0 ]
  [ "$(st_of "$id")" = open ]
}

@test "reopen of an UNATTRIBUTABLE claim (no --by) is allowed — not provably live" {
  guard_env
  id=$(bash "$CB" add --project /r --title T --source S)
  bash "$CB" claim "$id" >/dev/null                        # bare claim, no --by
  run bash "$CB" reopen "$id"
  [ "$status" -eq 0 ]                                       # stranding the work is the worse failure
  [ "$(st_of "$id")" = open ]
}

@test "reopen of an OPEN or BLOCKED item is unaffected by the guards" {
  guard_env
  id=$(bash "$CB" add --project /r --title T --source S)
  run bash "$CB" reopen "$id"
  [ "$status" -eq 0 ]
  id2=$(bash "$CB" add --project /r --title U --source S)
  bash "$CB" block "$id2" --needs "operator: set key" >/dev/null
  run bash "$CB" reopen "$id2"
  [ "$status" -eq 0 ]
  [ "$(st_of "$id2")" = open ]
}

@test "--force is rejected on any event other than reopen (never silently ignored)" {
  guard_env
  id=$(bash "$CB" add --project /r --title T --source S)
  run bash "$CB" done "$id" --evidence ref:1 --force
  [ "$status" -eq 2 ]
  echo "$output" | grep -q -- '--force'
}

@test "add on a DONE event-key WARNS loud but still echoes the id with rc 0 (cc-discover contract)" {
  guard_env
  id=$(bash "$CB" add --project /r --title T --source S)
  bash "$CB" done "$id" --evidence "6488617 the fix" >/dev/null
  before="$(wc -l < "$CC_BACKLOG_FILE" | tr -d ' ')"
  run bash -c "bash '$CB' add --project /r --title T --source S 2>&1"
  [ "$status" -eq 0 ]                       # rc 0: callers branch on it (cc-discover:121)
  echo "$output" | grep -q "$id"            # the id is still echoed (idempotency contract)
  echo "$output" | grep -qi 'already done'
  echo "$output" | grep -q '6488617'        # the prior evidence is surfaced
  [ "$(wc -l < "$CC_BACKLOG_FILE" | tr -d ' ')" -eq "$before" ]   # NOT re-opened, no new record
  [ "$(st_of "$id")" = done ]
}

@test "add on a non-done event-key stays silent (no warning noise on ordinary dedup)" {
  guard_env
  bash "$CB" add --project /r --title T --source S >/dev/null
  run bash -c "bash '$CB' add --project /r --title T --source S 2>&1"
  [ "$status" -eq 0 ]
  refute_imatch "$output" 'already done'
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
  refute_match "$output" "$a"                     # open item excluded
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
  refute_match "$output" 'Bee'
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
  refute_in_file 'aaaaaaaaaaaa' "$CC_BACKLOG_FILE"  # aged terminal dropped
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
  # HERMETIC worktree root: the owned-wait oracle resolves $CC_BACKLOG_WT_ROOT/wt-<id>. Pointing it
  # at an empty tmpdir keeps every pre-existing reap test off the REAL ~/Development/.worktrees (a
  # live dispatch worktree there must never decide a unit test's verdict) and makes "no worktree ⇒ no
  # owned wait" the default, so the dead-worker cases stay genuine NEGATIVE controls for the oracle.
  export CC_BACKLOG_WT_ROOT="$BATS_TEST_TMPDIR/wtroot"; mkdir -p "$CC_BACKLOG_WT_ROOT"
  HOST="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo localhost)"
}

# owned_wait_fixture <id> — a fake dispatch worktree holding a LIVE process whose argv NAMES it: the
# shape the real producer emits (bats runs `bats-exec-test … <wt>/tests/x.bats`; ship-land re-execs
# `<wt>/scripts/land-lock.sh`; a task-output wait loop polls a `<wt>`-derived path). Sets OWNED_PID.
# (memory fixture-shape-parity-with-real-producer — a fixture is a contract claim about the producer.)
owned_wait_fixture() {
  local wt="$CC_BACKLOG_WT_ROOT/wt-$1" i
  mkdir -p "$wt/tests"
  printf '#!/bin/bash\nsleep 30\n' > "$wt/tests/gate.sh"; chmod +x "$wt/tests/gate.sh"
  bash "$wt/tests/gate.sh" &                       # argv carries the worktree path ⇒ pgrep -f sees it
  OWNED_PID=$!
  # Never return before pgrep can actually see it, or the assertion races the fork.
  for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "$wt" >/dev/null 2>&1 && return 0; sleep 0.2; done
  return 0
}
# cwd_wait_fixture <id> [subdir] — a fake dispatch worktree occupied by a LIVE process whose CWD is
# the worktree (or <subdir> below it) and whose ARGV DOES NOT NAME IT. That is the shape the real
# producer emits, and it is the whole point: cc-wave-plan fires
# `handoff-fire.sh --cwd $WTROOT/wt-<id>` (cc-wave-plan:287), the launcher carries the path in ITS
# argv and EXITS, and the surviving `claude` inherits only the cwd — so `pgrep -f <wt>` reads 0 while
# the worker is very much alive. Deliberately NOT the argv shape owned_wait_fixture builds: a fixture
# that named the path would be absolved by S1 and could never discriminate S1b
# (memory fixture-shape-parity-with-real-producer). Sets OWNED_PID.
cwd_wait_fixture() {
  local wt="$CC_BACKLOG_WT_ROOT/wt-$1" sub="${2:-}" dir i
  dir="$wt${sub:+/$sub}"; mkdir -p "$dir"
  ( cd "$dir" && exec sleep 30 ) &                 # argv is bare `sleep 30` — no worktree path in it
  OWNED_PID=$!
  # The fixture's own contract, asserted not assumed: argv must NOT name the worktree, or this test
  # would pass through S1 and certify nothing.
  pgrep -f "$wt" >/dev/null 2>&1 && { echo "fixture broken: argv names $wt" >&2; return 1; }
  # Never return before the cwd is actually observable, or the assertion races the fork. FAIL LOUD if
  # it never becomes observable: a fixture that returns 0 on timeout makes every downstream failure
  # ambiguous ("did the probe break, or did the worker never start?") and can certify nothing.
  for i in 1 2 3 4 5 6 7 8 9 10; do
    /usr/sbin/lsof -a -d cwd -w -t -- "$dir" 2>/dev/null | grep -q "^$OWNED_PID$" && return 0
    sleep 0.2
  done
  echo "fixture broken: pid $OWNED_PID never became observable with cwd $dir" >&2
  return 1
}
owned_wait_cleanup() {
  if [ -n "${OWNED_PID:-}" ]; then
    kill "$OWNED_PID" 2>/dev/null || true
    # A SIGTERM'd child reports 143; unguarded, `wait` propagates it and errexit fails the TEST in
    # its teardown — a green subject reported as red. Reap the child, never adopt its exit code.
    wait "$OWNED_PID" 2>/dev/null || true
  fi
  OWNED_PID=""; return 0
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

@test "reap: unblock resets the thrash window — the next reap does NOT re-block (dispatcher-starvation fix)" {
  # RED-proof for the reap→unblock→reap refold: pre-fix, reap folds fastFail over the WHOLE trail with
  # no awareness of a later `unblock`, so the very next sweep re-blocks anything the desk unblocks — the
  # dispatcher reads "backlog empty" while 21 rows sit blocked. The window must reset at the unblock.
  reap_env
  rec '{"id":"unblkreap001","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Unblock"}'
  rec '{"id":"unblkreap001","ts":"2026-01-01T00:00:10Z","event":"claim","by":"h-1"}'
  rec '{"id":"unblkreap001","ts":"2026-01-01T00:00:14Z","event":"reopen"}'   # cycle 1: 4s < window
  rec '{"id":"unblkreap001","ts":"2026-01-01T00:00:20Z","event":"claim","by":"h-2"}'
  rec '{"id":"unblkreap001","ts":"2026-01-01T00:00:24Z","event":"reopen"}'   # cycle 2: 4s < window ⇒ thrash
  run bash "$CB" reap                                   # persistent thrash → blocked
  [ "$status" -eq 0 ]
  [ "$(status_of unblkreap001)" = blocked ]
  bash "$CB" unblock unblkreap001 >/dev/null            # desk/operator unblocks after investigating
  [ "$(status_of unblkreap001)" = open ]
  run bash "$CB" reap                                   # the VERY NEXT sweep must respect the unblock
  [ "$status" -eq 0 ]
  [ "$(status_of unblkreap001)" = open ]                # pre-fix: pre-unblock history re-blocks ⇒ blocked (RED)
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

# ── reap Rule A re-verify: an OWNED WAIT is not a dead worker ────────────────────────────────────
# RED-proof for the false "dead-worker stall … not auto-completable" verdict (backlog 2d36e63d16a2,
# items 02ba4e52389a / 761a546f939c / 6cab0ab3cb2f — each blocked while its worktree ran a live
# gate). cc-dispatch claims with `--by <host>-$$` and then EXITS, so a dispatched claim's pid is
# ALWAYS dead past the stale gate and `claimer_live` cannot see the worker at all: Rule A degrades to
# a pure idle-time verdict. Pre-fix these two cases reopen/block (RED); post-fix reap re-verifies
# against the WORKTREE and keeps the claim. The paired no-process test is the positive control that
# proves the oracle can still say DEAD (an always-alive oracle would strand every real dead worker).

@test "reap: stale claim + dead claimer pid but a LIVE process tree in the item's worktree → KEEP (owned wait, not dead)" {
  reap_env
  owned_wait_fixture ownedwt0aa01
  rec '{"id":"ownedwt0aa01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Owned"}'
  rec "{\"id\":\"ownedwt0aa01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"  # 7200s, dispatcher pid dead
  run bash "$CB" reap
  owned_wait_cleanup
  [ "$status" -eq 0 ]
  [ "$(status_of ownedwt0aa01)" = claimed ]            # pre-fix: reopened ⇒ open (RED)
  echo "$output" | grep -q 'KEEP ownedwt0aa01'         # and it says so — a silent absolve == an inert oracle
  echo "$output" | grep -q 'owned wait'
}

@test "reap: SAME setup with NO live process in the worktree → still reopened (positive control: the oracle can say DEAD)" {
  reap_env
  mkdir -p "$CC_BACKLOG_WT_ROOT/wt-deadwt0bb01/tests"   # worktree EXISTS, nothing running in it
  rec '{"id":"deadwt0bb01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Dead"}'
  rec "{\"id\":\"deadwt0bb01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"
  run bash "$CB" reap
  [ "$status" -eq 0 ]
  [ "$(status_of deadwt0bb01)" = open ]                # a real dead worker must STILL be recovered
  echo "$output" | grep -q 'REOPEN deadwt0bb01'
}

@test "reap: a live worker whose CWD is the worktree but whose ARGV never names it → KEEP (S1b: the dispatched-worker shape)" {
  # THE regression. Pre-fix this reopened — `status=open` is cc-dispatch's fire predicate, so a false
  # dead verdict on a live worker spawns a DUPLICATE PEER into the worktree the first one is using.
  # Measured against a real dispatched session 2026-07-26 (backlog b1b7a425e169): `pgrep -f <wt>` → 0,
  # processes with cwd in <wt> → 6.
  reap_env
  cwd_wait_fixture cwdwt00aa01
  rec '{"id":"cwdwt00aa01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Cwd"}'
  rec "{\"id\":\"cwdwt00aa01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"
  run bash "$CB" reap
  owned_wait_cleanup
  [ "$status" -eq 0 ]
  [ "$(status_of cwdwt00aa01)" = claimed ]             # pre-fix: reopened ⇒ open (RED)
  echo "$output" | grep -q 'KEEP cwdwt00aa01'
  echo "$output" | grep -q 'live process cwd'          # via S1b specifically, not S1/S2
}

@test "reap: a live worker that has cd'd into a SUBDIRECTORY of the worktree is still owned (prefix, not equality)" {
  # An exact-path probe misses this: passing the path to lsof matches the cwd EXACTLY, so a worker
  # sitting in <wt>/bin reads as dead. Verified against the real producer — the same measurement that
  # found the argv gap also found a subdirectory process invisible to the path-argument form.
  reap_env
  cwd_wait_fixture subwt000aa01 bin
  rec '{"id":"subwt000aa01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Sub"}'
  rec "{\"id\":\"subwt000aa01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"
  run bash "$CB" reap
  owned_wait_cleanup
  [ "$status" -eq 0 ]
  [ "$(status_of subwt000aa01)" = claimed ]
  echo "$output" | grep -q 'live process cwd'
}

@test "reap: a live cwd worker in a SIBLING worktree does NOT absolve this item (prefix must not over-match)" {
  # The anti-over-match control. wt-<id> is a prefix of wt-<id>xyz as a STRING, so a naive substring
  # test would let any sibling worktree absolve this one — and an oracle that absolves everything is
  # exactly as broken as one that convicts everything, just silently.
  reap_env
  cwd_wait_fixture sibwt000aa01xyz
  mkdir -p "$CC_BACKLOG_WT_ROOT/wt-sibwt000aa01"       # THIS item's worktree: exists, unoccupied
  rec '{"id":"sibwt000aa01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Sib"}'
  rec "{\"id\":\"sibwt000aa01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"
  run bash "$CB" reap
  owned_wait_cleanup
  [ "$status" -eq 0 ]
  [ "$(status_of sibwt000aa01)" = open ]               # a genuinely empty worktree still reopens
  echo "$output" | grep -q 'REOPEN sibwt000aa01'
}

@test "reap: a SYMLINKED worktree root still sees the live worker (lsof reports cwd physically resolved)" {
  # RED-proof for a false-dead one level down inside the fix itself. lsof reports a process's cwd
  # PHYSICALLY RESOLVED — a worker in /var/… is reported under /private/var/… — so a prefix match
  # against the RAW worktree path finds NOTHING the moment any component of the root is a symlink:
  # the probe reads "no processes", every oracle abstains, and reap convicts a live worker. Measured
  # 2026-07-26: with the raw-path match, this exact shape reopened.
  # Held EXPLICITLY rather than relying on BATS_TEST_TMPDIR happening to live under the /var symlink
  # — incidental coverage evaporates the day the harness or platform changes tmpdir (memory:
  # effect-read-predicate-red-proof).
  reap_env
  real="$BATS_TEST_TMPDIR/realroot"; mkdir -p "$real"
  ln -s "$real" "$BATS_TEST_TMPDIR/linkroot"
  export CC_BACKLOG_WT_ROOT="$BATS_TEST_TMPDIR/linkroot"      # reap resolves wt-<id> THROUGH the symlink
  [ "$(cd "$CC_BACKLOG_WT_ROOT" && pwd -P)" != "$CC_BACKLOG_WT_ROOT" ] || false   # the fixture's own premise
  cwd_wait_fixture symwt000aa01
  rec '{"id":"symwt000aa01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Sym"}'
  rec "{\"id\":\"symwt000aa01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"
  run bash "$CB" reap
  owned_wait_cleanup
  [ "$status" -eq 0 ]
  [ "$(status_of symwt000aa01)" = claimed ]                   # pre-fix: reopened ⇒ open (RED)
  echo "$output" | grep -q 'live process cwd'
}

@test "reap: CC_BACKLOG_LSOF_BIN= genuinely disables S1b (the seam turns the probe OFF, and the oracle says so)" {
  # A seam that cannot turn a thing off is not a seam. This also pins WHICH signal did the absolving
  # in the test above: same fixture, probe disabled ⇒ the verdict flips to REOPEN.
  reap_env
  export CC_BACKLOG_LSOF_BIN=
  cwd_wait_fixture offwt000aa01
  rec '{"id":"offwt000aa01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Off"}'
  rec "{\"id\":\"offwt000aa01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"
  run bash "$CB" reap
  owned_wait_cleanup
  [ "$status" -eq 0 ]
  [ "$(status_of offwt000aa01)" = open ]
}

@test "reap: owned wait past OWNED_WAIT_MAX_S is a WEDGE — blocked (never reopened, worktree still occupied)" {
  # The anti-inversion bound: without a ceiling an orphaned watcher would pin an item as "alive"
  # forever. Past it the item leaves the wave, but as a WEDGE named for what it is — and it must not
  # reopen even below MAX_ATTEMPTS, because reopening fires a second worker into an occupied worktree.
  reap_env
  export CC_BACKLOG_OWNED_WAIT_MAX_S=60                # 60s ceiling ⇒ the 7200s claim is way past it
  owned_wait_fixture wedgewt0cc01
  rec '{"id":"wedgewt0cc01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Wedge"}'
  rec "{\"id\":\"wedgewt0cc01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"  # 1st claim only
  run bash "$CB" reap
  owned_wait_cleanup
  [ "$status" -eq 0 ]
  [ "$(status_of wedgewt0cc01)" = blocked ]            # not reopened, despite totalClaims(1) < MAX_ATTEMPTS
  bash "$CB" list --all --json | jq -e --arg i wedgewt0cc01 '.[]|select(.id==$i)|.needs|test("wedged owned wait")'
  bash "$CB" list --all --json | jq -e --arg i wedgewt0cc01 '.[]|select(.id==$i)|.needs|test("NOT dead")'
}

@test "reap: the land lock held for the item's branch by a live pid → KEEP (owned wait with no process in the worktree)" {
  # S2, and NOT redundant with S1: a land re-run from the shared checkout on branch wt-<id> names no
  # worktree path in its argv. Uses the REAL scripts/land-lock.sh via its documented --print-lock-dir
  # read + LAND_LOCK_DIR seam, so the lock-dir resolution under test is the producer's own.
  reap_env
  wt="$CC_BACKLOG_WT_ROOT/wt-locked0dd01"; mkdir -p "$wt/scripts"
  ln -s "$BATS_TEST_DIRNAME/../scripts/land-lock.sh" "$wt/scripts/land-lock.sh"
  export LAND_LOCK_DIR="$BATS_TEST_TMPDIR/lockparent"
  mkdir -p "$LAND_LOCK_DIR/lock.d"
  printf 'wt-locked0dd01\n' > "$LAND_LOCK_DIR/lock.d/branch"
  printf '%s\n' "$$" > "$LAND_LOCK_DIR/lock.d/pid"                    # OUR pid: provably live
  ps -o lstart= -p "$$" > "$LAND_LOCK_DIR/lock.d/lstart" 2>/dev/null || true
  rec '{"id":"locked0dd01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Locked"}'
  rec "{\"id\":\"locked0dd01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"
  run bash "$CB" reap
  [ "$status" -eq 0 ]
  [ "$(status_of locked0dd01)" = claimed ]             # actively landing ⇒ the most owned wait there is
  echo "$output" | grep -q 'land lock held for wt-locked0dd01'
}

@test "reap: land lock held for a DIFFERENT branch does NOT absolve this item (lock is machine-wide)" {
  # The lock is repo-keyed and machine-wide, so it is almost always held by SOMEONE. Only a hold on
  # THIS item's branch is evidence about THIS item — else one landing would absolve every stale claim.
  reap_env
  wt="$CC_BACKLOG_WT_ROOT/wt-otherbr0ee01"; mkdir -p "$wt/scripts"
  ln -s "$BATS_TEST_DIRNAME/../scripts/land-lock.sh" "$wt/scripts/land-lock.sh"
  export LAND_LOCK_DIR="$BATS_TEST_TMPDIR/lockparent2"
  mkdir -p "$LAND_LOCK_DIR/lock.d"
  printf 'wt-someoneelse01\n' > "$LAND_LOCK_DIR/lock.d/branch"        # a DIFFERENT branch holds it
  printf '%s\n' "$$" > "$LAND_LOCK_DIR/lock.d/pid"
  rec '{"id":"otherbr0ee01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Other"}'
  rec "{\"id\":\"otherbr0ee01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"
  run bash "$CB" reap
  [ "$status" -eq 0 ]
  [ "$(status_of otherbr0ee01)" = open ]               # no evidence for THIS item ⇒ dead-worker recovery
}

@test "reap: land lock held for the item's branch by a DEAD pid does NOT absolve (stale lock dir)" {
  reap_env
  wt="$CC_BACKLOG_WT_ROOT/wt-deadlck0ff01"; mkdir -p "$wt/scripts"
  ln -s "$BATS_TEST_DIRNAME/../scripts/land-lock.sh" "$wt/scripts/land-lock.sh"
  export LAND_LOCK_DIR="$BATS_TEST_TMPDIR/lockparent3"
  mkdir -p "$LAND_LOCK_DIR/lock.d"
  printf 'wt-deadlck0ff01\n' > "$LAND_LOCK_DIR/lock.d/branch"
  printf '2147483647\n' > "$LAND_LOCK_DIR/lock.d/pid"                 # holder is DEAD
  rec '{"id":"deadlck0ff01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"DeadLock"}'
  rec "{\"id\":\"deadlck0ff01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"
  run bash "$CB" reap
  [ "$status" -eq 0 ]
  [ "$(status_of deadlck0ff01)" = open ]               # a dead holder is a stale lock, not a live wait
}

@test "reap: a HUNG session-registry oracle is time-capped AND abstains — our own timeout must not forge the kill evidence" {
  # TWO properties, one fixture. (a) BOUND: cc-sessions resolves pane liveness via `it2 session list
  # --json` with no timeout of its own, so a wedged it2 API hangs `claimer_live` — and with it every
  # `cc-reaper --reap` sweep — forever. Pre-cap this test times out at the bats level.
  # (b) VERDICT: the cap makes the probe RETURN, it does not make it ANSWER. A timeout is a
  # non-verdict (rc 2), and it is OUR timeout — convicting on it is forging the kill evidence
  # (memory: gate-never-ran-vs-gate-red). The item therefore stays `claimed` and the abstention is
  # PRINTED. Previously this asserted `open`: the sweep reopened on a probe that never answered, and
  # `open` is cc-dispatch's fire predicate ⇒ a duplicate peer onto possibly-live work.
  reap_env
  export CC_BACKLOG_ORACLE_TIMEOUT_S=2
  printf '#!/bin/bash\nsleep 300\n' > "$BATS_TEST_TMPDIR/hungsess"; chmod +x "$BATS_TEST_TMPDIR/hungsess"
  export CC_BACKLOG_SESSIONS_BIN="$BATS_TEST_TMPDIR/hungsess"
  rec '{"id":"hungorc0ii01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Hung"}'
  rec '{"id":"hungorc0ii01","ts":"2026-01-01T00:00:00Z","event":"claim","by":"PANE-SHAPED-CLAIMER"}'  # session-shaped ⇒ registry path
  start="$(date +%s)"
  run timeout 30 bash "$CB" reap
  elapsed=$(( $(date +%s) - start ))
  [ "$status" -eq 0 ]                                  # pre-cap: 124 (bats-level timeout) ⇒ RED
  [ "$elapsed" -lt 25 ]                                # bounded by the cap, not by the hung fork
  [ "$(status_of hungorc0ii01)" = claimed ]            # pre-fix: reopened ⇒ open (RED)
  echo "$output" | grep -q 'KEEP hungorc0ii01'
  echo "$output" | grep -q 'claimer UNRESOLVED'        # and it says so — a silent abstain is an inert oracle
}

@test "reap: a registry that ANSWERS and does not list the claimer is a REAL verdict → reopen (not-live ≠ unresolved)" {
  # The control that keeps the abstention honest. Without it, "abstain when unresolved" could be
  # satisfied by an oracle that abstains on EVERYTHING — which strands every dead worker forever and
  # would still pass the hung-registry test above. Same session-shaped claimer, same registry path;
  # the ONLY difference is that the registry replies. A reply of "not in my list" is evidence.
  reap_env                                             # reap_env's stub answers `[]` — a real, empty answer
  rec '{"id":"answered0j01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Answered"}'
  rec '{"id":"answered0j01","ts":"2026-01-01T00:00:00Z","event":"claim","by":"PANE-SHAPED-CLAIMER"}'
  run bash "$CB" reap
  [ "$status" -eq 0 ]
  [ "$(status_of answered0j01)" = open ]
  echo "$output" | grep -q 'REOPEN answered0j01'
}

@test "reap: an UNRESOLVED claimer past UNRESOLVED_MAX_S is BLOCKED, never reopened (abstention is bounded, but never flips to death)" {
  # Abstention must not be permanent — a registry that is broken for good would otherwise pin every
  # session-shaped claim as undecidable forever (the same inversion the owned-wait ceiling bounds).
  # Past the ceiling the item leaves the wave, but as `blocked` (a human decides), NEVER as `open`:
  # no amount of elapsed time turns an unanswered probe into proof of death.
  # Second UNRESOLVED shape on purpose — here the registry REPLIES but with garbage jq cannot parse,
  # which must be read the same way as no reply at all.
  reap_env
  export CC_BACKLOG_UNRESOLVED_MAX_S=60                # claim is 7200s old ⇒ far past the ceiling
  printf '#!/bin/bash\necho "not json at all"\n' > "$BATS_TEST_TMPDIR/junksess"; chmod +x "$BATS_TEST_TMPDIR/junksess"
  export CC_BACKLOG_SESSIONS_BIN="$BATS_TEST_TMPDIR/junksess"
  rec '{"id":"unresolv0k01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"Unresolved"}'
  rec '{"id":"unresolv0k01","ts":"2026-01-01T00:00:00Z","event":"claim","by":"PANE-SHAPED-CLAIMER"}'  # 1st claim only
  run bash "$CB" reap
  [ "$status" -eq 0 ]
  [ "$(status_of unresolv0k01)" = blocked ]            # NOT open — and blocked on 1 attempt, under MAX_ATTEMPTS
  echo "$output" | grep -q 'BLOCK unresolv0k01'
  echo "$output" | grep -q 'unresolvable claimer'
  refute_match "$output" 'REOPEN unresolv0k01'
}

@test "reap: no worktree at all for the id ⇒ oracle abstains, dead-worker path unchanged" {
  # The oracle must never fail OPEN into "alive" when it simply has nothing to read (an item worked
  # in-place, or a worktree already torn down). Absence of evidence is not evidence of life.
  reap_env
  rec '{"id":"nowtree0gg01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"NoWt"}'
  rec "{\"id\":\"nowtree0gg01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"
  run bash "$CB" reap
  [ "$status" -eq 0 ]
  [ "$(status_of nowtree0gg01)" = open ]
}

@test "reap --dry-run: an owned wait writes NOTHING and reports the KEEP" {
  reap_env
  owned_wait_fixture drykeep0hh01
  rec '{"id":"drykeep0hh01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"DryKeep"}'
  rec "{\"id\":\"drykeep0hh01\",\"ts\":\"2026-01-01T00:00:00Z\",\"event\":\"claim\",\"by\":\"$HOST-2147483647\"}"
  before="$(wc -l < "$CC_BACKLOG_FILE" | tr -d ' ')"
  run bash "$CB" reap --dry-run
  owned_wait_cleanup
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'KEEP drykeep0hh01'
  # this file's own `refute_match` — NOT `grep -qv` (passes whenever ANY line fails to match, i.e.
  # always) and NOT a bare `! cmd` (errexit-exempt mid-body ⇒ vacuous; see the header note).
  refute_match "$output" 'WOULD-REOPEN drykeep0hh01'
  [ "$(wc -l < "$CC_BACKLOG_FILE" | tr -d ' ')" -eq "$before" ]
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
  refute_imatch "$output" 'integer expression'      # empty claimBy must not shift columns
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
  refute_imatch "$output" 'integer expression'      # no misalignment error on the empty field
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

# ── COST BOUNDING (2026-07-25) — valid_records forked one `jq` PER LEDGER RECORD, so at 1552 lines it
# cost ~9s of every `cc-reaper --reap` tick, and the ledger is APPEND-ONLY (it only ever grows). These
# pin the single-pass shape and the contract it has to keep. ────────────────────────────────────────

@test "P5: a 3000-record ledger is validated in one pass, not one fork per record" {
  # measured: the per-record loop spends 3002 jq forks on exactly this input; the single pass spends 3.
  # Counting forks, not seconds — a wall-clock bound is load-dependent, and 3000 records sat close
  # enough to any tolerable threshold to still pass with the per-record shape intact.
  local i=0
  while [ "$i" -lt 3000 ]; do
    printf '{"id":"bulk%04d0kk01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"T"}\n' "$i" >> "$CC_BACKLOG_FILE"
    i=$((i + 1))
  done
  local d="$BATS_TEST_TMPDIR/stub" rj; mkdir -p "$d"; rj="$(command -v jq)"
  printf '#!/bin/bash\nprintf x >> "%s/jqf"\nexec %s "$@"\n' "$BATS_TEST_TMPDIR" "$rj" > "$d/jq"; chmod +x "$d/jq"
  local old_path n; old_path="$PATH"; PATH="$d:$PATH"
  run bash "$CB" list --open
  n="$([ -f "$BATS_TEST_TMPDIR/jqf" ] && wc -c < "$BATS_TEST_TMPDIR/jqf" | tr -d ' ' || echo 0)"
  PATH="$old_path"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'bulk')" -eq 3000 ]   # every record still reported…
  [ "$n" -lt 50 ]                                              # …off a bounded number of processes
}

@test "P5: a BLANK ledger line is skipped silently, never reported as malformed" {
  rec '{"id":"blank000kk01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"T"}'
  printf '\n' >> "$CC_BACKLOG_FILE"
  run bash "$CB" list --open
  [ "$status" -eq 0 ]
  refute_match "$output" 'malformed'
  printf '%s' "$output" | grep -q 'blank000kk01'
}

@test "P5: malformed-line NUMBERS stay exact when the last line has no trailing newline" {
  # jq's own input_line_number counts newlines CONSUMED, so it would report the unterminated final
  # line as line 2 here, not 3 — off-by-one in the only pointer back to the offending record.
  printf '{"id":"numok000kk01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"T"}\n' > "$CC_BACKLOG_FILE"
  printf 'garbage-line-two\n' >> "$CC_BACKLOG_FILE"
  printf 'garbage-line-three-with-no-newline' >> "$CC_BACKLOG_FILE"
  run bash "$CB" list --open
  printf '%s' "$output" | grep -q 'malformed line 2 skipped'
  printf '%s' "$output" | grep -q 'malformed line 3 skipped'
}

@test "P5: a FAILED validation pass is loud, never a silently empty ledger" {
  # one jq now covers the whole file, so a jq failure would report "no records" — which reads as a
  # clean, empty backlog and makes reap a silent no-op. Per-record forking could not fail that way.
  rec '{"id":"loud0000kk01","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"T"}'
  mkdir -p "$BATS_TEST_TMPDIR/stub"
  printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/stub/jq"; chmod +x "$BATS_TEST_TMPDIR/stub/jq"
  PATH="$BATS_TEST_TMPDIR/stub:$PATH" run bash "$CB" list --open
  printf '%s' "$output" | grep -q 'record scan INCOMPLETE'
}
