#!/usr/bin/env bats
# ship-backup-reap.sh — the ship flow's rollback-ref GC. Scratch bare "origin" + working clone in
# BATS_TEST_TMPDIR; NEVER touches a real origin or a real ref.
#
# Harness laws: L1 every test drives the REAL script through a REAL land (commit → sibling advances
# the trunk → rebase → push), because the whole defect is about what a REBASE does to a ref's
# patch-ids — a hand-built ref pair could not reproduce it. L2 every assertion is failure-distinct:
# the reap tests assert the ref EXISTED first (so "always deletes" and "never deletes" both die),
# and the keep tests use a fixture where a name-blind or content-blind reaper WOULD delete. L3
# `[ ]` / `grep -q` only — a non-final `[[ ]]` is errexit-exempt, i.e. a dead assertion. L4 both
# directions are controlled: a positive (the ref really goes) AND four independent negatives
# (revised content, dropped path, wrong namespace, no verifier).

setup() {
  # HERMETICITY (run_gate's blocking test-hermeticity ratchet): fixture $HOME FIRST, before
  # anything else, so every test inherits it rather than reading the operator's real ~/.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  REAP="$REPO/scripts/ship-backup-reap.sh"

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK"
  cd "$WORK" || return 1   # an unchecked cd here would run every git command below in the wrong repo
  git config user.email tester@example.com
  git config user.name tester
  git checkout -q -b main
  echo base > base.txt
  git add base.txt
  git commit -q -m base
  git push -q -u origin main
  # Point the bare repo's HEAD at the branch that actually exists. `git init --bare` leaves it on
  # `master`, and a clone of a repo whose HEAD names a nonexistent ref silently checks out NOTHING:
  # the peer below then commits on an unborn branch, producing a PARENTLESS root commit whose push
  # is a non-fast-forward. That is a fixture defect that fails as a `sibling_lands` error rather
  # than a wrong verdict, but it kept the reaper from being exercised at all.
  git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main

  unset SHIP_BACKUP_REAP SHIP_BACKUP_REAP_LAND_VERIFY 2>/dev/null || true
}

# ── fixture: the three moves of a real land ────────────────────────────────────────────────────

# commit a change on a session branch and snapshot the PRE-rebase rollback ref exactly as
# ship-land.sh's preflight does (`git branch -f ship/backup-<short> HEAD`).
start_change() { # <file> <content>
  git checkout -q -b feat
  printf '%s\n' "$2" > "$1"
  git add "$1"
  git commit -q -m "feat $1"
  BACKUP="ship/backup-$(git rev-parse --short HEAD)"
  git branch -f "$BACKUP" HEAD
}

# a PEER lands first, so our rebase has to replay and the landed sha differs from the backup's.
sibling_lands() { # <file> <content>
  local d="$BATS_TEST_TMPDIR/peer"
  rm -rf "$d"
  git clone -q -b main "$ORIGIN" "$d"    # -b explicitly: never depend on the origin's HEAD symref
  git -C "$d" config user.email peer@example.com
  git -C "$d" config user.name peer
  printf '%s\n' "$2" > "$d/$1"
  git -C "$d" add "$1"
  git -C "$d" commit -q -m "peer $1"
  git -C "$d" push -q origin HEAD:main
  git fetch -q origin main
}

land() { # rebase onto the fetched trunk, push, and record what landed
  git rebase -q origin/main
  git push -q origin HEAD:main
  git fetch -q origin main
  LANDED="$(git rev-parse HEAD)"
}

# ── the positive control ───────────────────────────────────────────────────────────────────────
@test "reaps the backup ref after a clean rebase-land" {
  start_change a.txt alpha
  sibling_lands other.txt peer-content
  land
  # controls: the ref exists, and the rebase really did move us off it (so this is the patch-id
  # case that no dedupe can collapse — not a trivially-identical ref).
  [ -n "$(git branch --list "$BACKUP")" ]
  [ "$(git rev-parse "$BACKUP")" != "$LANDED" ]

  run "$REAP" reap "$BACKUP" "$LANDED"
  [ "$status" -eq 0 ]
  [ -z "$(git branch --list "$BACKUP")" ]
  echo "$output" | grep -q "reaped"
}

@test "the reap is idempotent — an absent backup ref is a silent no-op, not an error" {
  start_change a.txt alpha
  land
  git branch -D "$BACKUP"
  run "$REAP" reap "$BACKUP" "$LANDED"
  [ "$status" -eq 0 ]
}

# ── the design regression: immunity to a trunk that drifts after our push ───────────────────────
# The predicate compares the ref against the head WE landed, never against origin/<trunk>. Against
# a moving trunk it decays to unusable (437 of 739 live refs read as "content differs"), and this
# repo's trunk moves inside the seconds between a push and this reap.
@test "reaps even when a sibling advances the trunk over OUR path after we landed" {
  start_change a.txt alpha
  land
  sibling_lands a.txt alpha-peer-edit
  # control: the drift is real and it touches the very path we landed, so an origin/main-based
  # predicate would refuse this ref forever.
  [ -n "$(git diff --name-only "$LANDED" origin/main -- a.txt)" ]

  run "$REAP" reap "$BACKUP" "$LANDED"
  [ "$status" -eq 0 ]
  [ -z "$(git branch --list "$BACKUP")" ]
}

# ── the negatives: every way a ref may still hold the only copy ─────────────────────────────────
@test "KEEPS a backup ref whose content the land revised away" {
  start_change a.txt alpha
  # the author amends during the land — the trunk gets alpha-revised, the backup still holds alpha.
  printf 'alpha-revised\n' > a.txt
  git add a.txt
  git commit -q --amend -m "feat a.txt revised"
  land

  run "$REAP" reap "$BACKUP" "$LANDED"
  [ "$status" -ne 0 ]
  [ -n "$(git branch --list "$BACKUP")" ]
  echo "$output" | grep -q "KEEPING"
  echo "$output" | grep -q "a.txt"
}

@test "KEEPS a backup ref holding a path absent from the landed head" {
  start_change a.txt alpha
  # a second commit adds a file, the ref captures it, and the land then proceeds WITHOUT it —
  # the mixed add+edit drop (land-verify's G-P9-7 case) where the sibling edits all landed fine.
  printf 'only\n' > only-on-backup.txt
  git add only-on-backup.txt
  git commit -q -m extra
  git branch -f "$BACKUP" HEAD
  git reset -q --hard HEAD~1
  land

  run "$REAP" reap "$BACKUP" "$LANDED"
  [ "$status" -ne 0 ]
  [ -n "$(git branch --list "$BACKUP")" ]
  echo "$output" | grep -q "only-on-backup.txt"
}

@test "REFUSES any ref outside the ship/backup- namespace, even a content-identical one" {
  start_change a.txt alpha
  land
  # This branch IS the landed head, so the content predicate alone would clear it for deletion.
  # Only the namespace guard stands between a bad argument and a session branch.
  git branch -f keep/my-session-work "$LANDED"

  run "$REAP" reap keep/my-session-work "$LANDED"
  [ "$status" -eq 3 ]
  [ -n "$(git branch --list keep/my-session-work)" ]
  echo "$output" | grep -q "only ever deletes"
}

@test "KEEPS the ref when land-verify is unavailable — the reap is only ever authorised by a proof" {
  start_change a.txt alpha
  land
  export SHIP_BACKUP_REAP_LAND_VERIFY="$BATS_TEST_TMPDIR/no-such-verifier.sh"

  run "$REAP" reap "$BACKUP" "$LANDED"
  [ "$status" -ne 0 ]
  [ -n "$(git branch --list "$BACKUP")" ]
  echo "$output" | grep -q "fail-closed"
}

@test "KEEPS the ref when the landed head cannot be resolved" {
  start_change a.txt alpha
  land
  run "$REAP" reap "$BACKUP" 0000000000000000000000000000000000000000
  [ "$status" -ne 0 ]
  [ -n "$(git branch --list "$BACKUP")" ]
  echo "$output" | grep -q "fail-closed"
}

@test "SHIP_BACKUP_REAP=off is a kill switch that keeps the ref without failing" {
  start_change a.txt alpha
  land
  export SHIP_BACKUP_REAP=off

  run "$REAP" reap "$BACKUP" "$LANDED"
  [ "$status" -eq 0 ]
  [ -n "$(git branch --list "$BACKUP")" ]
  echo "$output" | grep -q "SKIPPED"
}

@test "an unknown mode is refused loudly rather than treated as a reap" {
  run "$REAP" frobnicate
  [ "$status" -eq 3 ]
  echo "$output" | grep -q "unknown mode"
}

# ── sweep: the accumulated population (backlog d88c1640550f) ───────────────────────────────────
# The refs that SURVIVE today are the ones whose land did not succeed — a stuck fire tip, whose
# branch is still parked at the very commit the rollback ref names. `start_change` already builds
# exactly that shape, so these tests differ from the ones above mainly in what they DON'T call:
# `land`. Harness laws as above; the sweep's negatives are chosen so that a carrier-set bug, a
# namespace bug, and a content-predicate relapse each go red on a DIFFERENT test.

stuck_fire() { # <branch> <file> <content> — a land that never succeeded; sets BACKUP
  git checkout -q -b "$1" main
  printf '%s\n' "$3" > "$2"
  git add "$2"
  git commit -q -m "wip $2"
  BACKUP="ship/backup-$(git rev-parse --short HEAD)"
  git branch -f "$BACKUP" HEAD
  git checkout -q main
}

@test "sweep --apply reaps a stuck fire's rollback ref and leaves the fire branch itself alone" {
  stuck_fire fire-a a.txt alpha
  # controls: the ref exists, and it is NOT on the trunk — so patch-id landedness and any
  # trunk-content predicate both refuse it, which is exactly why this population accumulated.
  [ -n "$(git branch --list "$BACKUP")" ]
  run git merge-base --is-ancestor "$BACKUP" origin/main
  [ "$status" -ne 0 ]

  run "$REAP" sweep --apply
  [ "$status" -eq 0 ]
  [ -z "$(git branch --list "$BACKUP")" ]
  [ -n "$(git branch --list fire-a)" ]
  echo "$output" | grep -q "contained in fire-a"
}

@test "KEEPS a rollback ref whose fire branch is gone — on this disk it is the sole holder" {
  stuck_fire fire-b b.txt beta
  git branch -D fire-b            # the branch was cleaned up; only the rollback ref holds the work
  run "$REAP" sweep --apply
  [ "$status" -eq 0 ]
  [ -n "$(git branch --list "$BACKUP")" ]
  echo "$output" | grep -q "SOLE holder"
}

@test "sweep without --apply is a DRY RUN — it reports the reap and deletes nothing" {
  stuck_fire fire-c c.txt gamma
  run "$REAP" sweep
  [ "$status" -eq 0 ]
  [ -n "$(git branch --list "$BACKUP")" ]
  echo "$output" | grep -q "DRY-RUN"
  echo "$output" | grep -q "would reap"
}

# The carrier-set invariant. Two rollback refs can stand in an ancestor relation; if the namespace
# were allowed into the carrier set, one sweep would delete BOTH — the carrier last, by which point
# its own authority is already destroyed and the commits are on no ref at all.
@test "a backup ref may NEVER vouch for another — an ancestor chain with no live carrier keeps BOTH" {
  git checkout -q -b fire-d main
  printf 'one\n' > d.txt; git add d.txt; git commit -q -m d1
  B1="ship/backup-$(git rev-parse --short HEAD)"; git branch -f "$B1" HEAD
  printf 'two\n' >> d.txt; git add d.txt; git commit -q -m d2
  B2="ship/backup-$(git rev-parse --short HEAD)"; git branch -f "$B2" HEAD
  git checkout -q main
  git branch -D fire-d            # the only non-backup carrier is gone
  # control: the chain is real, so a namespace-blind carrier set WOULD delete both.
  run git merge-base --is-ancestor "$B1" "$B2"
  [ "$status" -eq 0 ]

  run "$REAP" sweep --apply
  [ "$status" -eq 0 ]
  [ -n "$(git branch --list "$B1")" ]
  [ -n "$(git branch --list "$B2")" ]
}

# Trunk is tried BEFORE local branches, so a landed ref is never attributed to some session branch
# that merely also contains it. `feat` is deliberately left in place as the competing carrier.
@test "a rollback ref contained in the trunk is reaped and attributed to the trunk, not to a branch" {
  start_change e.txt epsilon
  land
  git checkout -q main
  [ -n "$(git branch --list feat)" ]

  run "$REAP" sweep --apply
  [ "$status" -eq 0 ]
  [ -z "$(git branch --list "$BACKUP")" ]
  echo "$output" | grep -q "contained in origin/main"
}

@test "the sweep never touches a ref outside the backup namespace, however redundant" {
  git checkout -q -b fire-f main
  printf 'f\n' > f.txt; git add f.txt; git commit -q -m f
  git branch -f dup-of-fire-f HEAD    # a perfect duplicate — and NOT in the namespace
  git checkout -q main

  run "$REAP" sweep --apply
  [ "$status" -eq 0 ]
  [ -n "$(git branch --list dup-of-fire-f)" ]
  [ -n "$(git branch --list fire-f)" ]
}

@test "every sweep disposal writes a record naming the carrier that authorised it" {
  stuck_fire fire-g g.txt gamma
  LOG="$BATS_TEST_TMPDIR/disposals.jsonl"
  export CC_SHIP_BACKUP_DISPOSAL_LOG="$LOG"
  SHA="$(git rev-parse "$BACKUP")"

  run "$REAP" sweep --apply
  [ "$status" -eq 0 ]
  [ -f "$LOG" ]
  grep -q "\"ref\":\"$BACKUP\"" "$LOG"
  grep -q "\"sha\":\"$SHA\"" "$LOG"
  grep -q "\"authority\":\"fire-g\"" "$LOG"
  grep -q '"mode":"sweep"' "$LOG"
}

@test "the land-time reap records its disposal too — one deletion site, one record site" {
  start_change a.txt alpha
  sibling_lands other.txt peer-content
  land
  LOG="$BATS_TEST_TMPDIR/disposals.jsonl"
  export CC_SHIP_BACKUP_DISPOSAL_LOG="$LOG"

  run "$REAP" reap "$BACKUP" "$LANDED"
  [ "$status" -eq 0 ]
  grep -q '"mode":"reap"' "$LOG"
}

@test "SHIP_BACKUP_REAP=off is a kill switch for the sweep too, not just the land hook" {
  stuck_fire fire-h h.txt eta
  export SHIP_BACKUP_REAP=off

  run "$REAP" sweep --apply
  [ "$status" -eq 0 ]
  [ -n "$(git branch --list "$BACKUP")" ]
  echo "$output" | grep -q "SKIPPED"
}

# The relapse guard. If a future edit reached for land-verify here, this ref would be KEPT forever:
# the trunk has moved over the very path it touches, which is the decay that made a content-based
# sweep undecidable (437 of 739). Ancestry has no drift term, so it still decides.
@test "the sweep decides by ANCESTRY, not content — a ref the trunk has drifted over is still reaped" {
  stuck_fire fire-i i.txt iota
  sibling_lands i.txt trunk-version-of-i
  [ -n "$(git diff --name-only "$BACKUP" origin/main -- i.txt)" ]

  run "$REAP" sweep --apply
  [ "$status" -eq 0 ]
  [ -z "$(git branch --list "$BACKUP")" ]
  echo "$output" | grep -q "contained in fire-i"
}

@test "sweep refuses an unknown option rather than silently sweeping with defaults" {
  run "$REAP" sweep --frobnicate
  [ "$status" -eq 3 ]
  echo "$output" | grep -q "unknown option"
}
