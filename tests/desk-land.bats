#!/usr/bin/env bats
# desk-land.sh — the desk-local land helper (cc-backlog c06778fd13a7). Proves the fail-closed
# preflight guards AND that a valid land is handed to the ship rail verbatim (exit code passed
# through). Builds scratch repos (bare "origin" + a "shared checkout" clone) in BATS_TEST_TMPDIR
# with a STUB scripts/ship-land.sh that records its cwd+args and returns a controllable code — so
# no network, no real repo, and no real push is ever touched. Also proves the handoff-fire.sh
# `land` dispatch delegates here.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DL="$REPO_ROOT/scripts/desk-land.sh"
  HF="$REPO_ROOT/scripts/handoff-fire.sh"

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  MAIN="$BATS_TEST_TMPDIR/main"                 # stands in for the shared checkout on `main`
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$MAIN"
  (
    cd "$MAIN"
    git config user.email t@e.com; git config user.name tester
    git checkout -q -b main
    mkdir -p scripts
    cat > scripts/ship-land.sh <<'STUB'
#!/usr/bin/env bash
{ echo "CWD=$(pwd)"; echo "ARGS=$*"; } >> "${SHIP_LAND_STUB_LOG:?stub log unset}"
exit "${SHIP_LAND_STUB_RC:-0}"
STUB
    chmod +x scripts/ship-land.sh
    echo base > base.txt
    git add -A; git commit -q -m base
    git push -q -u origin main
  )

  # Point desk-land at the scratch repo; treat MAIN as the shared checkout.
  export SHIP_LAND_SHARED_CHECKOUT="$MAIN"
  export DESK_LAND_REPO="$MAIN"
  export DESK_LAND_WTROOT="$BATS_TEST_TMPDIR/wts"; mkdir -p "$DESK_LAND_WTROOT"
  export SHIP_LAND_STUB_LOG="$BATS_TEST_TMPDIR/stub.log"; : > "$SHIP_LAND_STUB_LOG"
}

# create a worktree on a NEW session branch with one commit ahead of main
mk_wt() {  # $1=branch  $2=path
  ( cd "$MAIN" && git worktree add -q -b "$1" "$2" main \
      && cd "$2" && echo w > "work.txt" && git add -A && git commit -q -m "work $1" )
}

# create a branch with commits but NO live worktree (worktree added then removed)
mk_branch_no_wt() {  # $1=branch
  local t="$BATS_TEST_TMPDIR/mk-$(echo "$1" | tr / -)"
  ( cd "$MAIN" && git worktree add -q -b "$1" "$t" main \
      && cd "$t" && echo x > x.txt && git add -A && git commit -q -m "c $1" )
  git -C "$MAIN" worktree remove --force "$t"
}

# ── preflight: usage (64) ────────────────────────────────────────────────────────────────────
@test "no args → 64" {
  run bash "$DL"
  [ "$status" -eq 64 ]
  echo "$output" | grep -q "pass --branch"
}

@test "both --branch and --worktree → 64" {
  run bash "$DL" --branch feat/x --worktree /tmp/y
  [ "$status" -eq 64 ]
  echo "$output" | grep -q "exactly ONE"
}

@test "unknown arg → 64" {
  run bash "$DL" --frobnicate
  [ "$status" -eq 64 ]
  echo "$output" | grep -q "unknown argument"
}

# ── kill switch (66) ─────────────────────────────────────────────────────────────────────────
@test "HANDOFF_LAND_DISABLED=1 → 66, nothing touched" {
  HANDOFF_LAND_DISABLED=1 run bash "$DL" --branch feat/x
  [ "$status" -eq 66 ]
  echo "$output" | grep -q "HANDOFF_LAND_DISABLED"
  [ ! -s "$SHIP_LAND_STUB_LOG" ]   # ship rail never ran
}

# ── target refusals (65) ─────────────────────────────────────────────────────────────────────
@test "--worktree nonexistent path → 65" {
  run bash "$DL" --worktree "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 65 ]
}

@test "--worktree = shared checkout → 65 (refuses trunk-in-shared-checkout)" {
  run bash "$DL" --worktree "$MAIN"
  [ "$status" -eq 65 ]
  echo "$output" | grep -q "shared checkout"
  [ ! -s "$SHIP_LAND_STUB_LOG" ]
}

@test "--worktree on a NON-session branch → 65" {
  git -C "$MAIN" worktree add -q -b random-branch "$BATS_TEST_TMPDIR/rand" main
  run bash "$DL" --worktree "$BATS_TEST_TMPDIR/rand"
  [ "$status" -eq 65 ]
  echo "$output" | grep -q "not a session branch"
  [ ! -s "$SHIP_LAND_STUB_LOG" ]
}

@test "--branch not found → 65" {
  run bash "$DL" --branch feat/does-not-exist
  [ "$status" -eq 65 ]
  echo "$output" | grep -q "not found"
}

@test "valid session worktree but ship rail missing → 65" {
  mk_wt feat/norail "$BATS_TEST_TMPDIR/norail"
  DESK_LAND_SHIP_LAND_BIN="$BATS_TEST_TMPDIR/nonexistent-ship-land.sh" \
    run bash "$DL" --worktree "$BATS_TEST_TMPDIR/norail"
  [ "$status" -eq 65 ]
  echo "$output" | grep -q "ship rail"
}

# ── delegation to the ship rail (verbatim exit code) ─────────────────────────────────────────
@test "--worktree on session branch, stub rc=0 → 0; ship rail ran IN the worktree" {
  mk_wt feat/work "$BATS_TEST_TMPDIR/work"
  phys="$(cd "$BATS_TEST_TMPDIR/work" && pwd -P)"
  run bash "$DL" --worktree "$BATS_TEST_TMPDIR/work"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "LANDED"
  grep -q "CWD=$phys" "$SHIP_LAND_STUB_LOG"
}

@test "ship rail exit 3 (escalation-PARK) → passed through as 3" {
  mk_wt feat/esc "$BATS_TEST_TMPDIR/esc"
  SHIP_LAND_STUB_RC=3 run bash "$DL" --worktree "$BATS_TEST_TMPDIR/esc"
  [ "$status" -eq 3 ]
  echo "$output" | grep -q "exited 3"
}

@test "ship rail exit 6 (gate-red) → passed through as 6" {
  mk_wt feat/gate "$BATS_TEST_TMPDIR/gate"
  SHIP_LAND_STUB_RC=6 run bash "$DL" --worktree "$BATS_TEST_TMPDIR/gate"
  [ "$status" -eq 6 ]
}

@test "--dry-run forwards --dry-run to the ship rail (no LANDED claim)" {
  mk_wt feat/dry "$BATS_TEST_TMPDIR/dry"
  run bash "$DL" --worktree "$BATS_TEST_TMPDIR/dry" --dry-run
  [ "$status" -eq 0 ]
  grep -q "ARGS=.*--dry-run" "$SHIP_LAND_STUB_LOG"
  echo "$output" | grep -q "dry-run (NOT pushed)"
}

@test "--trunk forwards --trunk <b> to the ship rail" {
  mk_wt feat/trunk "$BATS_TEST_TMPDIR/trunk"
  run bash "$DL" --worktree "$BATS_TEST_TMPDIR/trunk" --trunk release
  [ "$status" -eq 0 ]
  grep -q "ARGS=.*--trunk release" "$SHIP_LAND_STUB_LOG"
}

# ── --branch resolution ──────────────────────────────────────────────────────────────────────
@test "--branch with a LIVE worktree lands THAT worktree" {
  mk_wt feat/live "$BATS_TEST_TMPDIR/live"
  phys="$(cd "$BATS_TEST_TMPDIR/live" && pwd -P)"
  run bash "$DL" --branch feat/live
  [ "$status" -eq 0 ]
  grep -q "CWD=$phys" "$SHIP_LAND_STUB_LOG"
}

@test "--branch with NO live worktree creates a throwaway worktree, lands, then removes it" {
  mk_branch_no_wt feat/orphan
  run bash "$DL" --branch feat/orphan
  [ "$status" -eq 0 ]
  # ship rail ran from a throwaway worktree under DESK_LAND_WTROOT
  grep -q "CWD=.*/\.desk-land-feat-orphan-" "$SHIP_LAND_STUB_LOG"
  # and the throwaway worktree is gone afterwards (no leak)
  ! git -C "$MAIN" worktree list | grep -q "desk-land-feat-orphan"
  ! ls -d "$DESK_LAND_WTROOT"/.desk-land-feat-orphan-* 2>/dev/null
}

# ── handoff-fire.sh `land` dispatch delegates here ───────────────────────────────────────────
@test "handoff-fire.sh land (no args) delegates to desk-land → 64" {
  run bash "$HF" land
  [ "$status" -eq 64 ]
  echo "$output" | grep -q "desk-land:"
}

@test "handoff-fire.sh land --worktree lands via desk-land (stub rc=0)" {
  mk_wt feat/viahf "$BATS_TEST_TMPDIR/viahf"
  run bash "$HF" land --worktree "$BATS_TEST_TMPDIR/viahf"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "LANDED"
}
