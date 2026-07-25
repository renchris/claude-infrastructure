#!/usr/bin/env bats
# worktree-gc — the janitor hooks/git-worktree-guard.sh:40,57 and hooks/live-session-registry.sh:2
# have always advertised. Every gate is red-proofed with a DISCRIMINATOR PAIR: the same fixture
# worktree must be KEPT with the gate tripped and REMOVED with it clear — a suite that only asserts
# the KEEP half would pass against a script that never removes anything.
#
# Liveness oracles are shimmed (CC_WTGC_CC_NOTIFY / _LSOF / _PGREP / _REGISTRY_DIR) so the suite
# never reads the host's real sessions, and idle is driven by a BACKDATED COMMITTER DATE — a
# durable git product, not a file mtime (the audit's §8-B lesson, re-asserted by test 7).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  GC="$REPO/scripts/worktree-gc.sh"
  R="$BATS_TEST_TMPDIR/main"
  OLD="$(( $(date +%s) - 7200 ))"          # 2 h ago — comfortably past the 30 min idle floor

  git init -q -b main "$R"
  git -C "$R" config user.email t@t
  git -C "$R" config user.name t
  echo a > "$R/f"
  git -C "$R" add f
  GIT_AUTHOR_DATE="$OLD +0000" GIT_COMMITTER_DATE="$OLD +0000" git -C "$R" commit -qm c1
  git -C "$R" update-ref refs/remotes/origin/main HEAD

  # Oracle shims. cc-notify replays a file so a test can flip what it reports mid-suite.
  SHIMOUT="$BATS_TEST_TMPDIR/notify.json"; echo '[]' > "$SHIMOUT"
  SHIM="$BATS_TEST_TMPDIR/cc-notify"
  printf '#!/usr/bin/env bash\ncat %s\n' "$SHIMOUT" > "$SHIM"; chmod +x "$SHIM"
  STUB="$BATS_TEST_TMPDIR/nullbin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB"; chmod +x "$STUB"
  REG="$BATS_TEST_TMPDIR/registry"; mkdir -p "$REG"
  LOCK="$BATS_TEST_TMPDIR/gc.lock"
}

# wt <name> <branch> — a clean, landed, idle worktree (the baseline REMOVE candidate).
wt() {
  git -C "$R" worktree add -q -b "$2" "$BATS_TEST_TMPDIR/$1" HEAD 2>/dev/null
  echo "$BATS_TEST_TMPDIR/$1"
}

run_gc() {
  run env CC_WTGC_REPO="$R" CC_WTGC_CC_NOTIFY="$SHIM" CC_WTGC_LSOF="$STUB" \
      CC_WTGC_PGREP="$STUB" CC_WTGC_REGISTRY_DIR="$REG" CC_WTGC_LOCK="$LOCK" \
      CC_WTGC_EXCLUDE="${EXCLUDE:-}" bash "$GC" "$@"
}

has_wt() { git -C "$R" worktree list --porcelain | grep -qF "worktree $1"; }
has_br() { git -C "$R" rev-parse --verify --quiet "refs/heads/$1" >/dev/null; }

@test "clean + idle + landed → worktree removed, branch PRESERVED (default keeps branches)" {
  p="$(wt wt-landed feat/landed)"
  run_gc
  [ "$status" -eq 0 ]
  [ ! -d "$p" ]
  ! has_wt "$p"
  has_br feat/landed          # the janitor never deletes a branch without --prune-branches
}

@test "dirty tree → KEPT (removal would need --force ⇒ data loss)" {
  p="$(wt wt-dirty feat/dirty)"
  echo dirt >> "$p/f"
  run_gc
  [ -d "$p" ]
  echo "$output" | grep -q "KEEP.*wt-dirty.*dirty tree"
}

@test "live cc-notify cwd → KEPT" {
  p="$(wt wt-live feat/live)"
  printf '[{"cwd":"%s"}]\n' "$p" > "$SHIMOUT"
  run_gc
  [ -d "$p" ]
  echo "$output" | grep -q "KEEP.*wt-live.*LIVE"
}

@test "RED-PROOF of the live gate: same worktree IS removed once cc-notify reports no session" {
  # Without this half, a script that simply never removes anything would pass the KEEP test above.
  p="$(wt wt-live feat/live)"
  printf '[{"cwd":"%s"}]\n' "$p" > "$SHIMOUT"
  run_gc
  [ -d "$p" ]
  echo '[]' > "$SHIMOUT"
  run_gc
  [ ! -d "$p" ]
}

@test "live-session-registry PID alive → KEPT (the registry finally has a consumer)" {
  p="$(wt wt-reg feat/reg)"
  printf '%s\t%s\t%s\n' "$$" "sid-1" "$p" > "$REG/wt-reg"
  run_gc
  [ -d "$p" ]
  echo "$output" | grep -q "KEEP.*wt-reg.*registry"
  # Discriminator: a DEAD registry pid must not hold the worktree hostage.
  printf '%s\t%s\t%s\n' "999999" "sid-1" "$p" > "$REG/wt-reg"
  run_gc
  [ ! -d "$p" ]
}

@test ".teammate-busy marker → KEPT" {
  p="$(wt wt-busy feat/busy)"
  touch "$p/.teammate-busy"
  run_gc
  [ -d "$p" ]
  echo "$output" | grep -q "KEEP.*wt-busy.*teammate-busy"
}

@test "unlanded branch → KEPT (patch-equivalence, not ancestry, is the landed test)" {
  p="$(wt wt-unlanded feat/unlanded)"
  echo new > "$p/g"
  git -C "$p" add g
  GIT_AUTHOR_DATE="$OLD +0000" GIT_COMMITTER_DATE="$OLD +0000" git -C "$p" commit -qm orphan
  run_gc
  [ -d "$p" ]
  echo "$output" | grep -q "KEEP.*wt-unlanded.*not on origin/main"
}

@test "branch tip younger than the idle floor → KEPT" {
  p="$(wt wt-fresh feat/fresh)"
  git -C "$p" commit -q --amend --no-edit --date=now   # same patch-id (still landed), fresh tip
  run_gc
  [ -d "$p" ]
  echo "$output" | grep -q "KEEP.*wt-fresh.*idle floor"
}

@test "idle is measured by BRANCH TIP, not directory mtime (audit §8-B)" {
  # A `git status` sweep rewrites .git/worktrees/<n>/index, so admin-dir mtime reads fresh for
  # every worktree. A janitor gating on mtime would KEEP this one forever; it must still remove it.
  p="$(wt wt-touched feat/touched)"
  touch "$p/f" "$p"
  run_gc
  [ ! -d "$p" ]
}

@test "CC_WTGC_EXCLUDE hard-excludes a path that otherwise passes every gate" {
  p="$(wt wt-excl feat/excl)"
  EXCLUDE="$p" run_gc
  [ -d "$p" ]
  echo "$output" | grep -q "KEEP.*wt-excl.*hard-excluded"
}

@test "--dry-run mutates nothing" {
  p="$(wt wt-dry feat/dry)"
  run_gc --dry-run --prune-branches
  [ "$status" -eq 0 ]
  [ -d "$p" ]
  has_br feat/dry
  echo "$output" | grep -q "would remove"
}

@test "--prune-branches deletes a landed, worktree-less branch with -d" {
  p="$(wt wt-pb feat/pb)"
  run_gc --prune-branches
  [ ! -d "$p" ]
  ! has_br feat/pb
}

@test "--prune-branches NEVER touches protected refs (backup/recovery classes + main)" {
  git -C "$R" branch ship/backup-abc123
  git -C "$R" branch backup/daemon-window
  git -C "$R" branch agent-a324-prerebase-backup
  run_gc --prune-branches
  has_br ship/backup-abc123
  has_br backup/daemon-window
  has_br agent-a324-prerebase-backup
  has_br main
}

@test "--prune-branches never deletes an unlanded branch" {
  p="$(wt wt-ub feat/ub)"
  echo new > "$p/g"; git -C "$p" add g
  GIT_AUTHOR_DATE="$OLD +0000" GIT_COMMITTER_DATE="$OLD +0000" git -C "$p" commit -qm orphan
  run_gc --prune-branches
  [ -d "$p" ]
  has_br feat/ub
}

@test "broken admin record (directory vanished) is pruned; its branch survives" {
  p="$(wt wt-broken feat/broken)"
  rm -rf "$p"
  run_gc
  ! has_wt "$p"
  has_br feat/broken
}

@test "a held lock serializes the pass — nothing is removed" {
  p="$(wt wt-lock feat/lock)"
  mkdir -p "$LOCK"
  run_gc
  [ "$status" -eq 0 ]
  [ -d "$p" ]
  echo "$output" | grep -q "another pass holds"
}

@test "no liveness oracle at all → refuse to remove (exit 3), never a blind reap" {
  p="$(wt wt-nooracle feat/nooracle)"
  run env CC_WTGC_REPO="$R" CC_WTGC_CC_NOTIFY=/nonexistent/cc-notify \
      CC_WTGC_LSOF=/nonexistent/lsof CC_WTGC_PGREP=/nonexistent/pgrep \
      CC_WTGC_REGISTRY_DIR="$REG" CC_WTGC_LOCK="$LOCK" bash "$GC"
  [ "$status" -eq 3 ]
  [ -d "$p" ]
}

@test "--prune (the invocation git-worktree-guard.sh prints) is accepted; junk flags exit 2" {
  p="$(wt wt-alias feat/alias)"
  run_gc --prune
  [ "$status" -eq 0 ]
  [ ! -d "$p" ]
  run_gc --bogus
  [ "$status" -eq 2 ]
}

@test "the no-force / no-D discipline is in the source, not just the docs" {
  # Audit §8-H: `git worktree remove` and `git branch -d` refusing is the LAST net under our
  # evidence. Substituting --force / -D discards it, so the suite guards the source itself.
  body="$(sed 's/#.*$//' "$GC")"          # comments explain the ban; only real commands can break it
  ! printf '%s\n' "$body" | grep -qE 'worktree[[:space:]]+remove[^;]*--force'
  ! printf '%s\n' "$body" | grep -qE 'branch[[:space:]]+(-D|-d[[:space:]]+-f|--delete[[:space:]]+--force)'
}
