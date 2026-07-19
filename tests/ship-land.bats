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

@test "deleted files: git-rm of a tracked .sh/.py lands GREEN (b452/1bc4 regression) → exit 0" {
  # run_gate builds shellfiles/pyfiles by extension/shebang; before the fix it did NOT drop paths
  # removed at HEAD, so shellcheck / py_compile ran on the now-absent path → gate RED (exit 6),
  # making ANY file-removal commit unlandable. Regression: a commit that git-rm's a tracked .sh
  # AND .py must land green.
  # Seed both files STRAIGHT onto trunk (no ship-land seed) so the single delete-land is the unit
  # under test — a seed *via ship-land* would py_compile doomed.py and leave __pycache__ litter that
  # this scratch repo, unlike the real one (.gitignore: __pycache__/), does not ignore → a false
  # dirty-tree exit 2 on the next land that would mask the gate behaviour we are asserting.
  git checkout -q -b seed main
  printf '#!/usr/bin/env bash\necho "doomed"\n' > doomed.sh
  printf 'x = 1\n' > doomed.py
  git add doomed.sh doomed.py && git commit -q -m "seed doomed files"
  git push -q origin seed:main
  git fetch -q origin main

  git checkout -q -b chore/rm-doomed origin/main
  git rm -q doomed.sh doomed.py && git commit -q -m "chore: remove doomed files"
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "LANDED"
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- doomed.sh)" ]         # deletion landed on trunk
  [ -z "$(git ls-tree origin/main -- doomed.py)" ]
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

@test "verify-fail: PERSISTENT concurrent drop → bounded auto-retry exhausts → exit 8, clean rollback" {
  # post-update hook resets main back to base AFTER EVERY push — the 2026-07-11 incident, but persistent:
  # our push 'succeeds' yet a concurrent rebase-land drops our commit from the trunk, every single time.
  # T-P9-7: ship-land auto-retries (bounded by SHIP_LAND_VERIFY_RETRIES=2) and, on exhaustion, leaves a
  # CLEAN committed tree (never a wedged rebase) with the ship/backup-* ref intact for manual recovery.
  base_sha="$(git -C "$ORIGIN" rev-parse main)"
  printf '#!/bin/sh\ngit update-ref refs/heads/main %s\n' "$base_sha" > "$ORIGIN/hooks/post-update"
  chmod +x "$ORIGIN/hooks/post-update"

  on_branch_with feat/dropme dropped.txt payload

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 8 ]
  echo "$output" | grep -qi "VERIFY FAILED"
  echo "$output" | grep -qi "auto-retry"                 # it DID retry before giving up (bounded)
  grep -q '"verify":"FAIL"' "$LAND_LOG"
  grep -q '"exit":8' "$LAND_LOG"
  # rollback guarantee: no rebase left in progress, working tree clean, backup ref intact
  [ ! -d "$WORK/.git/rebase-merge" ]
  [ ! -d "$WORK/.git/rebase-apply" ]
  [ -z "$(git status --porcelain)" ]
  [ -n "$(git branch --list 'ship/backup-*')" ]
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

@test "P0-1 gate-green producer: green gate writes gate-green==HEAD; red gate does not" {
  # boundary-handoff.sh:122 fires its advisory only when gate-green == HEAD on a clean tree.
  # Before P0-1, the only gate-green writers were test fixtures, so boundary abstained 100% in prod.
  gc="$(git rev-parse --git-common-dir)"
  rm -f "$gc/gate-green"

  # green gate via --dry-run (runs the gate, no push) → producer stamps gate-green with HEAD
  git checkout -q -b feat/gg main
  printf '#!/usr/bin/env bash\necho ok\n' > gg.sh
  git add gg.sh && git commit -q -m "feat: gg"
  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -eq 0 ]
  [ -f "$gc/gate-green" ]
  [ "$(cat "$gc/gate-green")" = "$(git rev-parse HEAD)" ]   # producer wrote the proven-green HEAD

  # red gate → the red HEAD must NEVER be marked green (gate-green must not advance to it)
  git checkout -q -b feat/gg-red main
  printf '#!/usr/bin/env bash\ncd /tmp/nope\necho ok\n' > bad-gg.sh   # SC2164 → shellcheck RED
  git add bad-gg.sh && git commit -q -m "feat: bad-gg"
  redhead="$(git rev-parse HEAD)"
  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -eq 6 ]
  [ "$(cat "$gc/gate-green" 2>/dev/null || echo none)" != "$redhead" ]   # unproven tree never green
}

@test "T-P9-7 recover: TRANSIENT concurrent drop → auto-retry re-lands → exit 0, content on trunk" {
  # post-update drops main to base only on the FIRST push (one-time marker); the auto-retry's re-push
  # then sticks and content-verify passes. Proves the bounded retry HEALS a transient drop instead of
  # stranding on the old manual exit-8 recovery. (base_sha + $ORIGIN expand at write time; \$marker is
  # literal for the hook's runtime.)
  base_sha="$(git -C "$ORIGIN" rev-parse main)"
  cat > "$ORIGIN/hooks/post-update" <<EOF
#!/bin/sh
marker="$ORIGIN/dropped-once"
if [ ! -f "\$marker" ]; then
  : > "\$marker"
  git update-ref refs/heads/main $base_sha
fi
EOF
  chmod +x "$ORIGIN/hooks/post-update"

  on_branch_with feat/heal heal.txt payload

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "auto-retry"                 # it reconciled + re-pushed
  echo "$output" | grep -q "LANDED"
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- heal.txt)" ]        # content really reached the trunk on retry
  grep -q '"verify":"ok"' "$LAND_LOG"
}

@test "T-P9-7 kill-switch: SHIP_LAND_VERIFY_RETRIES=0 → single-shot exit 8, no auto-retry" {
  # =0 restores the pre-T-P9-7 behavior: one push, one verify, no retry. Persistent drop → immediate exit 8.
  base_sha="$(git -C "$ORIGIN" rev-parse main)"
  printf '#!/bin/sh\ngit update-ref refs/heads/main %s\n' "$base_sha" > "$ORIGIN/hooks/post-update"
  chmod +x "$ORIGIN/hooks/post-update"

  on_branch_with feat/noretry nr.txt payload

  run env SHIP_LAND_VERIFY_RETRIES=0 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 8 ]
  ! echo "$output" | grep -qi "auto-retry"               # zero retries attempted (single-shot)
  grep -q '"exit":8' "$LAND_LOG"
}

@test "T-P9-7 rollback: auto-retry rebase CONFLICT → rolled back clean, exit 5" {
  # A sibling commit on origin edits base.txt divergently; the one-time hook resets main to it after our
  # first push. The auto-retry then rebases onto the sibling and CONFLICTS on base.txt → ship-land must
  # roll the rebase back (git rebase --abort → clean tree) and exit 5, never leave a wedged mid-conflict tree.
  git checkout -q -b sibling main
  printf 'theirs\n' > base.txt
  git commit -q -am "sibling: base.txt"
  git push -q origin sibling
  sib_sha="$(git -C "$ORIGIN" rev-parse sibling)"
  git checkout -q main

  cat > "$ORIGIN/hooks/post-update" <<EOF
#!/bin/sh
marker="$ORIGIN/reset-once"
if [ ! -f "\$marker" ]; then
  : > "\$marker"
  git update-ref refs/heads/main $sib_sha
fi
EOF
  chmod +x "$ORIGIN/hooks/post-update"

  git checkout -q -b feat/conflict main
  printf 'ours\n' > base.txt                              # same line as the sibling → guaranteed conflict
  git commit -q -am "feat: base.txt ours"

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 5 ]
  echo "$output" | grep -qi "rolled back"
  # rollback guarantee: no rebase left in progress, working tree clean
  [ ! -d "$WORK/.git/rebase-merge" ]
  [ ! -d "$WORK/.git/rebase-apply" ]
  [ -z "$(git status --porcelain)" ]
}
