#!/usr/bin/env bats
# ship-land.sh — the fail-closed landing pipeline. Scratch bare "origin" + working clone
# in BATS_TEST_TMPDIR. NEVER pushes to a real origin. land-lock/land.log/decisions all
# redirected under BATS_TEST_TMPDIR so no real machine state is touched.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SHIPLAND="$REPO/scripts/ship-land.sh"

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK"
  cd "$WORK"
  git config user.email tester@example.com
  git config user.name tester
  git checkout -q -b main
  echo base > base.txt
  git add base.txt
  git commit -q -m base
  git push -q -u origin main

  export LAND_LOG="$BATS_TEST_TMPDIR/land.log"
  export LAND_LOCK_DIR="$BATS_TEST_TMPDIR/lock"
  export LAND_LOCK_WAIT=10
  export SHIP_LAND_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export SHIP_LAND_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/nope"   # never matches the work repo
  export CLAUDE_CODE_SESSION_ID="test-sid-123"
}

on_branch_with() {  # $1=branch $2=file $3=content  → commit a change on a fresh branch
  git checkout -q -b "$1" main
  printf '%s\n' "$3" > "$2"
  git add "$2"
  git commit -q -m "feat: $2"
}

@test "green: land end-to-end → exit 0, content on trunk, land.log verify:ok" {
  git checkout -q -b feat/green main
  printf '#!/usr/bin/env bash\necho "hello"\n' > hello.sh
  git add hello.sh && git commit -q -m "feat: hello"

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "LANDED"

  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- hello.sh)" ]         # content actually on trunk
  grep -q '"verify":"ok"' "$LAND_LOG"                     # self-attesting log
  grep -q '"sid":"test-sid-123"' "$LAND_LOG"
}

@test "red gate: shellcheck-dirty shell blocks the land → exit 6, trunk unchanged" {
  git checkout -q -b feat/badgate main
  printf '#!/usr/bin/env bash\ncd /tmp/nope\necho ok\n' > bad.sh   # SC2164 → shellcheck RED
  git add bad.sh && git commit -q -m "feat: bad"

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- bad.sh)" ]           # NOT pushed
}

@test "gate: extensionless python (shebang) syntax error blocks → exit 6" {
  git checkout -q -b feat/pytool main
  printf '#!/usr/bin/env python3\nx = = 1\n' > pytool       # no .py — caught via shebang scan
  git add pytool && git commit -q -m "feat: pytool"

  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -eq 6 ]
}

@test "push non-ff: rejected push → exit 7, loud" {
  # server-side hook rejects the main update (simulated non-fast-forward)
  printf '#!/bin/sh\n[ "$1" = "refs/heads/main" ] && { echo "simulated non-ff" >&2; exit 1; }\nexit 0\n' > "$ORIGIN/hooks/update"
  chmod +x "$ORIGIN/hooks/update"

  on_branch_with feat/nonff f3.txt hello

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 7 ]
  echo "$output" | grep -qi "reject"
}

@test "verify-fail: concurrent drop after push → exit 8, land.log verify:FAIL" {
  # post-update hook resets main back to base AFTER our push — the 2026-07-11 incident:
  # our push 'succeeds' but a concurrent rebase-land drops our commit from the trunk.
  base_sha="$(git -C "$ORIGIN" rev-parse main)"
  printf '#!/bin/sh\ngit update-ref refs/heads/main %s\n' "$base_sha" > "$ORIGIN/hooks/post-update"
  chmod +x "$ORIGIN/hooks/post-update"

  on_branch_with feat/dropme dropped.txt payload

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 8 ]
  echo "$output" | grep -qi "VERIFY FAILED"
  grep -q '"verify":"FAIL"' "$LAND_LOG"
  grep -q '"exit":8' "$LAND_LOG"
}

@test "esc-scan: DROP TABLE in the range → exit 3, decision packet parked, trunk unchanged" {
  git checkout -q -b feat/esc main
  printf 'DROP TABLE users;\n' > migration.sql
  git add migration.sql && git commit -q -m "feat: migration"

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 3 ]
  echo "$output" | grep -qi "PARKED"
  # a class-B decision packet was written
  pkt="$(ls "$SHIP_LAND_DECISIONS_DIR"/*.json 2>/dev/null | head -1)"
  [ -n "$pkt" ]
  grep -q '"class": "B"' "$pkt"
  grep -q '"staged": true' "$pkt"
  # never pushed
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- migration.sql)" ]
}

@test "dry-run: reconcile + gate, no push → exit 0, trunk unchanged" {
  on_branch_with feat/dry dry.txt content

  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "dry-run"
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- dry.txt)" ]          # NOT pushed
}

@test "shared-checkout: non-session branch on the shared checkout → exit 4" {
  on_branch_with randombranch s.txt wip

  run env SHIP_LAND_SHARED_CHECKOUT="$WORK" bash "$SHIPLAND" --trunk main
  [ "$status" -eq 4 ]
  echo "$output" | grep -qi "REFUSING"
}

@test "dirty tree: uncommitted changes → exit 2" {
  on_branch_with feat/dirty tracked.txt clean
  echo dirty >> tracked.txt                                # uncommitted modification

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 2 ]
}

@test "nothing to land: HEAD already on trunk → exit 0" {
  # on main, nothing ahead of origin/main
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "nothing to land"
}
