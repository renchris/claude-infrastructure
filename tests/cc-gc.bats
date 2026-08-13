#!/usr/bin/env bats
# cc-gc.bats — the GC franchise driver.
#
# Every reaping test is a DISCRIMINATOR PAIR: two fixtures identical except for the one predicate
# under test, asserting the reaper separates them. A test that only proves "the aged thing was
# deleted" cannot fail when the predicate degrades to "delete everything old" — which is exactly
# the regression this repo has already paid for twice (live operator conversations reaped, 2026-07-24;
# `kill -0` as an identity oracle defeated by pid reuse).

setup() {
  GC="${BATS_TEST_DIRNAME}/../scripts/cc-gc.sh"
  # ⚠️ $HOME FIRST, and here it is the load-bearing line rather than boilerplate. cc-gc.sh computes
  # EVERY store path at start-up as `${CC_<X>_DIR:-$HOME/.claude/<store>}`, so an unexported seam
  # does not fail — it silently resolves to the operator's LIVE tree, and this suite's subject is a
  # REAPER. The exports below do cover all of today's stores, which is precisely why the guard is
  # needed: the next store added to cc-gc.sh would default to live ~/ and this suite would reap it,
  # green. Not hypothetical — an unexported CC_TEARDOWN_RECORDS_DIR let a test run delete 6 real
  # ~/.claude/cc-teardown records on 2026-07-25, and tests/autonomy-sweep.bats carries the same
  # warning over the same class of subject. Fixturing $HOME makes the DEFAULT safe, so coverage no
  # longer depends on the export list staying exhaustive.
  # (Caught by the land gate's test-hermeticity ratchet; this suite was written before it existed.)
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # BATS_TEST_TMPDIR, not `mktemp -d`: bats owns its lifetime, so a killed run cannot leak the tree.
  TMP="$BATS_TEST_TMPDIR/gc"; mkdir -p "$TMP"
  export CC_MAILBOX_DIR="$TMP/mailbox"
  export CC_WATCHDOG_DIR="$TMP/watchdog"
  export CC_REGISTRY_DIR="$TMP/registry"
  export CC_ROLES_DIR="$TMP/roles"
  export CC_PAGES_DIR="$TMP/pages"
  export CC_COMMS_ALARM_DIR="$TMP/alarms"
  export CC_PUSH_RECORDS_DIR="$TMP/push"
  export CC_GC_CONFIG_ROOTS="$TMP/root1"
  export CC_GC_SESSION_INDEX_STAMP="$TMP/si.last"
  export CC_IDL="$TMP/idl.jsonl"
  # delegates are exercised by their own suites; stub them so this one tests the driver
  export CC_GC_SCRATCHPAD_BIN="$TMP/stub-scratchpad"
  export CC_GC_WORKTREE_BIN="$TMP/stub-worktree"
  printf '#!/bin/sh\necho "stub-scratchpad $*"\n' > "$TMP/stub-scratchpad"
  printf '#!/bin/sh\necho "stub-worktree $*"\n' > "$TMP/stub-worktree"
  chmod +x "$TMP/stub-scratchpad" "$TMP/stub-worktree"
  mkdir -p "$CC_MAILBOX_DIR" "$CC_WATCHDOG_DIR" "$CC_REGISTRY_DIR" "$CC_ROLES_DIR" \
           "$CC_PAGES_DIR" "$CC_COMMS_ALARM_DIR" "$CC_PUSH_RECORDS_DIR" "$TMP/root1/projects"
  date +%s > "$CC_GC_SESSION_INDEX_STAMP"
  PIDS=""
}

teardown() {
  for p in $PIDS; do kill "$p" 2>/dev/null || true; done
  rm -rf "$TMP"
}

# a live registry row for <paneUUID>/<sid> pinned to a real running pid
live_row() { # <paneUUID> <sid> <pid>
  printf '{"paneUUID":"%s","session_id":"%s","pid":%s}\n' "$1" "$2" "$3" > "$CC_REGISTRY_DIR/$1.json"
}
# Sets SPAWNED. NOT `p=$(spawn)`: a background job started inside a command substitution keeps
# the substitution's stdout open, so `$(...)` would block for the child's full lifetime.
spawn() { sleep 300 >/dev/null 2>&1 & SPAWNED=$!; PIDS="$PIDS $SPAWNED"; }
# backdate a file N days
age_days() { touch -t "$(date -v-"$2"d +%Y%m%d%H%M 2>/dev/null || date -d "-$2 days" +%Y%m%d%H%M)" "$1"; }

U_DEAD=aaaaaaaa-1111-2222-3333-444444444444
U_LIVE=bbbbbbbb-1111-2222-3333-444444444444

mkbox() { # <key> <lines> <acked>
  local i=1
  : > "$CC_MAILBOX_DIR/$1.md"
  while [ "$i" -le "$2" ]; do echo "2026-01-01T00:00:00Z [x] msg$i" >> "$CC_MAILBOX_DIR/$1.md"; i=$((i + 1)); done
  [ -n "${3:-}" ] && echo "$3" > "$CC_MAILBOX_DIR/$1.acked"
  return 0
}

# ── driver surface ────────────────────────────────────────────────────────────────────────────

@test "--list names all seven franchise stores" {
  run bash "$GC" --list
  [ "$status" -eq 0 ]
  for s in mailbox watchdog scratchpad worktrees events transcripts session-index; do
    echo "$output" | grep -qx "$s" || { echo "missing store: $s"; false; }
  done
}

@test "dry-run is the default and deletes nothing" {
  mkbox "$U_DEAD" 3 3; age_days "$CC_MAILBOX_DIR/$U_DEAD.md" 30
  run bash "$GC" --store mailbox
  [ "$status" -eq 0 ]
  [ -f "$CC_MAILBOX_DIR/$U_DEAD.md" ]          # still there
  echo "$output" | grep -q "deleted=1"          # but reported as reapable
}

@test "--store filters to just the named stores" {
  run bash "$GC" --store watchdog
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "watchdog"
  ! echo "$output" | grep -q "^  mailbox"
}

@test "--json emits one parseable object with every store row" {
  run bash "$GC" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.tool == "cc-gc" and (.stores | length) == 7' >/dev/null
}

@test "fail-closed: an unreadable registry reaps nothing and exits 3" {
  mkbox "$U_DEAD" 3 3; age_days "$CC_MAILBOX_DIR/$U_DEAD.md" 30
  export CC_REGISTRY_DIR="$TMP/does-not-exist"
  run bash "$GC" --apply
  [ "$status" -eq 3 ]
  [ -f "$CC_MAILBOX_DIR/$U_DEAD.md" ]
}

# ── mailbox adapter ───────────────────────────────────────────────────────────────────────────

@test "mailbox: dead + fully-acked + aged is deleted" {
  mkbox "$U_DEAD" 3 3; age_days "$CC_MAILBOX_DIR/$U_DEAD.md" 30
  run bash "$GC" --store mailbox --apply
  [ "$status" -eq 0 ]
  [ ! -f "$CC_MAILBOX_DIR/$U_DEAD.md" ]
}

@test "mailbox: LIVE key is KEPT though identical in age and ack state (liveness outranks age)" {
  spawn; local p="$SPAWNED"
  live_row "$U_LIVE" sid-live "$p"
  mkbox "$U_DEAD" 3 3; age_days "$CC_MAILBOX_DIR/$U_DEAD.md" 30
  mkbox "$U_LIVE" 3 3; age_days "$CC_MAILBOX_DIR/$U_LIVE.md" 30
  run bash "$GC" --store mailbox --apply
  [ "$status" -eq 0 ]
  [ ! -f "$CC_MAILBOX_DIR/$U_DEAD.md" ]   # the pair differs only by the registry row …
  [ -f "$CC_MAILBOX_DIR/$U_LIVE.md" ]     # … and only the dead one goes
}

@test "mailbox: a role-pointed box is KEPT even with no registry row" {
  echo "$U_LIVE" > "$CC_ROLES_DIR/desk"
  mkbox "$U_LIVE" 3 3; age_days "$CC_MAILBOX_DIR/$U_LIVE.md" 30
  run bash "$GC" --store mailbox --apply
  [ -f "$CC_MAILBOX_DIR/$U_LIVE.md" ]
}

@test "mailbox: a name-keyed box is never age-reaped" {
  mkbox deskC 3 3; age_days "$CC_MAILBOX_DIR/deskC.md" 90
  run bash "$GC" --store mailbox --apply
  [ -f "$CC_MAILBOX_DIR/deskC.md" ]
  echo "$output" | grep -q "named=1"
}

@test "mailbox: UNACKED dead box is archived, not deleted — and only past the strand horizon" {
  mkbox "$U_DEAD" 5 2                                   # 3 lines never consumed
  age_days "$CC_MAILBOX_DIR/$U_DEAD.md" 10              # past MBX_DAYS(7), inside STRAND(30)
  run bash "$GC" --store mailbox --apply
  [ -f "$CC_MAILBOX_DIR/$U_DEAD.md" ]                   # unacked mail survives the short horizon
  echo "$output" | grep -q "unacked=1"

  age_days "$CC_MAILBOX_DIR/$U_DEAD.md" 40              # now past the strand horizon
  run bash "$GC" --store mailbox --apply
  [ ! -f "$CC_MAILBOX_DIR/$U_DEAD.md" ]
  [ -f "$CC_MAILBOX_DIR/archive/$U_DEAD.md" ]           # evidence preserved, never destroyed
  grep -q "msg5" "$CC_MAILBOX_DIR/archive/$U_DEAD.md"
}

@test "mailbox: the .forward tombstone survives its box being reaped" {
  mkbox "$U_DEAD" 3 3; age_days "$CC_MAILBOX_DIR/$U_DEAD.md" 30
  echo "$U_LIVE" > "$CC_MAILBOX_DIR/$U_DEAD.forward"
  run bash "$GC" --store mailbox --apply
  [ ! -f "$CC_MAILBOX_DIR/$U_DEAD.md" ]
  [ -f "$CC_MAILBOX_DIR/$U_DEAD.forward" ]              # chain stays resolvable
}

@test "mailbox: an abandoned lock dir is reaped, a fresh one is not" {
  mkdir -p "$CC_MAILBOX_DIR/.old.lock" "$CC_MAILBOX_DIR/.new.lock"
  age_days "$CC_MAILBOX_DIR/.old.lock" 1
  run bash "$GC" --store mailbox --apply
  [ ! -d "$CC_MAILBOX_DIR/.old.lock" ]
  [ -d "$CC_MAILBOX_DIR/.new.lock" ]
}

# ── watchdog adapter — the identity pin ───────────────────────────────────────────────────────

@test "watchdog: a dead pid's pair is reaped once aged" {
  spawn; local p="$SPAWNED"; kill "$p" 2>/dev/null || true; sleep 0.2
  echo "$p" > "$CC_WATCHDOG_DIR/sid-dead.pid"; echo sid-dead > "$CC_WATCHDOG_DIR/sid-dead.id"
  age_days "$CC_WATCHDOG_DIR/sid-dead.pid" 5
  run bash "$GC" --store watchdog --apply
  [ "$status" -eq 0 ]
  [ ! -f "$CC_WATCHDOG_DIR/sid-dead.pid" ]
  [ ! -f "$CC_WATCHDOG_DIR/sid-dead.id" ]
  echo "$output" | grep -q "dead=1"
}

@test "watchdog: RECYCLED pid is reaped, identity-consistent pid is KEPT (kill -0 says live for both)" {
  # Both fixtures point at a LIVE pid, so `kill -0` — and a comm=claude check — call both alive.
  # They differ ONLY in whether the process could have written its own pidfile.
  local recycled consistent
  spawn; recycled="$SPAWNED"
  echo "$recycled" > "$CC_WATCHDOG_DIR/sid-recycled.pid"
  echo sid-recycled > "$CC_WATCHDOG_DIR/sid-recycled.id"
  age_days "$CC_WATCHDOG_DIR/sid-recycled.pid" 5        # pidfile predates the process ⇒ recycled

  spawn; consistent="$SPAWNED"; sleep 1
  echo "$consistent" > "$CC_WATCHDOG_DIR/sid-ok.pid"    # pidfile written AFTER the process started
  echo sid-ok > "$CC_WATCHDOG_DIR/sid-ok.id"

  kill -0 "$recycled" && kill -0 "$consistent"          # premise: the naive oracle cannot separate them
  CC_GC_WATCHDOG_AGE_S=0 run bash "$GC" --store watchdog --apply
  [ "$status" -eq 0 ]
  [ ! -f "$CC_WATCHDOG_DIR/sid-recycled.pid" ]
  [ -f "$CC_WATCHDOG_DIR/sid-ok.pid" ]
  echo "$output" | grep -q "recycled=1"
}

@test "watchdog: a young pair is KEPT regardless of pid state" {
  spawn; local p="$SPAWNED"; kill "$p" 2>/dev/null || true; sleep 0.2
  echo "$p" > "$CC_WATCHDOG_DIR/sid-young.pid"; echo sid-young > "$CC_WATCHDOG_DIR/sid-young.id"
  run bash "$GC" --store watchdog --apply
  [ -f "$CC_WATCHDOG_DIR/sid-young.pid" ]
}

@test "watchdog: a live registered session is KEPT even with an ancient pidfile" {
  spawn; local p="$SPAWNED"
  live_row "$U_LIVE" sid-registered "$p"
  echo 999999 > "$CC_WATCHDOG_DIR/sid-registered.pid"   # pid is nonsense; the registry row rules
  age_days "$CC_WATCHDOG_DIR/sid-registered.pid" 30
  run bash "$GC" --store watchdog --apply
  [ -f "$CC_WATCHDOG_DIR/sid-registered.pid" ]
}

@test "watchdog: an orphan .id with no .pid is reaped once aged" {
  echo sid-orphan > "$CC_WATCHDOG_DIR/sid-orphan.id"
  age_days "$CC_WATCHDOG_DIR/sid-orphan.id" 5
  run bash "$GC" --store watchdog --apply
  [ ! -f "$CC_WATCHDOG_DIR/sid-orphan.id" ]
  echo "$output" | grep -q "orphan-id=1"
}

# ── ASSERT adapters — proof the store's OWNER is running ──────────────────────────────────────

@test "events: residue past the owner's own horizon reports the owner inert" {
  touch "$CC_PAGES_DIR/p1.page"; age_days "$CC_PAGES_DIR/p1.page" 30
  run bash "$GC" --store events
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "inert"
  echo "$output" | grep -q "pages=1"
}

@test "events: --strict turns an inert owner into a non-zero exit" {
  touch "$CC_PAGES_DIR/p1.page"; age_days "$CC_PAGES_DIR/p1.page" 30
  run bash "$GC" --store events --strict
  [ "$status" -eq 1 ]
}

@test "events: a drained dir reports ok and --strict stays green" {
  touch "$CC_PAGES_DIR/fresh.page"
  run bash "$GC" --store events --strict
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ok"
}

@test "transcripts: the adapter NEVER deletes — it only reports an unowned root" {
  touch "$TMP/root1/projects/old.jsonl"; age_days "$TMP/root1/projects/old.jsonl" 90
  run bash "$GC" --store transcripts --apply
  [ "$status" -eq 0 ]
  [ -f "$TMP/root1/projects/old.jsonl" ]               # harness owns deletion; we never race it
  echo "$output" | grep -q "inert"
}

@test "transcripts: a root inside the harness horizon reports ok" {
  touch "$TMP/root1/projects/recent.jsonl"
  run bash "$GC" --store transcripts --strict
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ok"
}

@test "session-index: a missing or stale sweep stamp reports the owner inert" {
  rm -f "$CC_GC_SESSION_INDEX_STAMP"
  run bash "$GC" --store session-index --strict
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "never ran"

  touch "$CC_GC_SESSION_INDEX_STAMP"
  run bash "$GC" --store session-index --strict
  [ "$status" -eq 0 ]
}

# ── delegation + telemetry ────────────────────────────────────────────────────────────────────

@test "delegates receive --apply only on an apply run" {
  run bash "$GC" --store scratchpad
  echo "$output" | grep -q "stub-scratchpad"
  ! echo "$output" | grep -q -- "--apply" || false
  run bash "$GC" --store scratchpad --apply
  echo "$output" | grep -q -- "--apply"
}

@test "a missing delegate is reported, never silently skipped" {
  export CC_GC_WORKTREE_BIN="$TMP/nope"
  run bash "$GC" --store worktrees
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "missing"
}

@test "an idle dry-run writes no IDL line; a real reap does" {
  run bash "$GC" --store watchdog
  [ ! -s "$CC_IDL" ]
  mkbox "$U_DEAD" 3 3; age_days "$CC_MAILBOX_DIR/$U_DEAD.md" 30
  run bash "$GC" --store mailbox --apply
  grep -q '"tool":"cc-gc"' "$CC_IDL"
}
