#!/usr/bin/env bats
# prune-plan-history — keep-policy for the two-layer plan version store (audit 03 §1c fix 7).
#
# Layer 1 (MANIFEST.jsonl) is the keep-N surface; Layer 2 (the plan-history git repo) is
# compacted, never truncated. The audit modelled `plans/` as N snapshots per plan; on disk it is
# a git WORKING TREE with one current file per plan, so pruning it would destroy the snapshot and
# reclaim nothing. These tests pin all three of those decisions.
#
# Harness laws: L1 fixtures use the producer's literal schema (hooks/plan-version-commit.sh:51-65
# writes {ts,session,tool,path,name,lines,size,sha256}); L2 assertions are failure-distinct — a
# keep case beside every drop case; L3 `[ ]` / `grep -q` only; L4 the "no output ⇒ keep
# everything" path is tested, because a filter that silently empties the file is the worst bug
# this script could have.

setup() {
  # HERMETICITY (run_gate's blocking test-hermeticity ratchet): fixture $HOME FIRST so every test
  # inherits it; the CC_PLAN_* seams below cover this script's inputs, this covers the rest.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PRUNE="$REPO/scripts/prune-plan-history.sh"
  export CC_PLAN_MANIFEST="$BATS_TEST_TMPDIR/plan-versions/MANIFEST.jsonl"
  export CC_PLAN_HISTORY_REPO="$BATS_TEST_TMPDIR/plan-history"
  export CC_PLAN_PRUNE_LOG="$BATS_TEST_TMPDIR/prune.log"
  export TMPDIR="$BATS_TEST_TMPDIR"          # keeps the lock dir out of the shared /tmp
  mkdir -p "$(dirname "$CC_PLAN_MANIFEST")"
}

# <name> <days-ago> — one MANIFEST record in the producer's literal schema
rec() {
  local ts
  ts=$(date -u -v-"$2"d +%Y-%m-%dT%H:%M:%SZ)
  jq -nc --arg ts "$ts" --arg n "$1" \
    '{ts:$ts,session:"s",tool:"Edit",path:("/p/"+$n+".md"),name:$n,lines:10,size:100,
      sha256:"deadbeef"}' >> "$CC_PLAN_MANIFEST"
}
count() { wc -l < "$CC_PLAN_MANIFEST" | tr -d ' '; }
for_plan() { jq -r --arg n "$1" 'select(.name==$n) | .ts' "$CC_PLAN_MANIFEST" | wc -l | tr -d ' '; }

# ── keep-N per plan ────────────────────────────────────────────────────────────────────────────
@test "keeps only the newest 10 records per plan, and keeps them per-PLAN not globally" {
  local i
  for i in $(seq 1 15); do rec alpha "$i"; done
  for i in $(seq 1 15); do rec beta  "$i"; done
  [ "$(count)" -eq 30 ]

  run bash "$PRUNE"
  [ "$status" -eq 0 ]
  [ "$(for_plan alpha)" -eq 10 ]
  [ "$(for_plan beta)"  -eq 10 ]      # a global cap would have starved one of the two
  [ "$(count)" -eq 20 ]
}

@test "a plan with fewer than 10 records loses none" {
  rec gamma 1; rec gamma 2; rec gamma 3
  run bash "$PRUNE"
  [ "$status" -eq 0 ]
  [ "$(for_plan gamma)" -eq 3 ]
}

@test "the records kept are the NEWEST, not an arbitrary 10" {
  local i
  for i in $(seq 1 15); do rec delta "$i"; done
  bash "$PRUNE"
  # oldest surviving must be the 10-day-old one; the 15-day-old must be gone
  run grep -c "$(date -u -v-15d +%Y-%m-%d)" "$CC_PLAN_MANIFEST"
  [ "$output" = "0" ]
  run grep -c "$(date -u -v-3d +%Y-%m-%d)" "$CC_PLAN_MANIFEST"
  [ "$output" = "1" ]
}

# ── 90-day cap ─────────────────────────────────────────────────────────────────────────────────
@test "records past the age cap are dropped even when under the keep-N count" {
  rec epsilon 1
  rec epsilon 200
  rec epsilon 300
  run bash "$PRUNE"
  [ "$status" -eq 0 ]
  [ "$(for_plan epsilon)" -eq 1 ]
}

@test "FLOOR: the newest record of an all-stale plan survives the age cap" {
  # Without this, a 90-day cap erased 163 of 523 real plans outright — the index would stop
  # knowing they exist while plans/<name>.md and the git history still hold them.
  rec zeta 200
  rec zeta 300
  run bash "$PRUNE"
  [ "$status" -eq 0 ]
  [ "$(for_plan zeta)" -eq 1 ]
  run jq -r 'select(.name=="zeta") | .ts' "$CC_PLAN_MANIFEST"
  echo "$output" | grep -q "$(date -u -v-200d +%Y-%m-%d)"   # the NEWEST of the two, not the oldest
}

# ── never empty the file ───────────────────────────────────────────────────────────────────────
@test "a manifest of pure garbage is left intact, not emptied" {
  printf 'not json at all\nstill not json\n' > "$CC_PLAN_MANIFEST"
  run bash "$PRUNE"
  [ "$status" -eq 0 ]
  [ "$(count)" -eq 2 ]
  grep -q "SKIPPED" "$CC_PLAN_PRUNE_LOG"
}

@test "one corrupt line does not abort the pass or lose the good records" {
  rec eta 1
  printf '{ broken\n' >> "$CC_PLAN_MANIFEST"
  rec eta 2
  run bash "$PRUNE"
  [ "$status" -eq 0 ]
  [ "$(for_plan eta)" -eq 2 ]
}

@test "a missing manifest is a no-op, not an error" {
  run bash "$PRUNE"
  [ "$status" -eq 0 ]
}

@test "output stays one valid JSON object per line in the producer's schema" {
  rec theta 1; rec theta 2
  bash "$PRUNE"
  run jq -e -s 'all(has("ts") and has("name") and has("sha256") and has("path"))' "$CC_PLAN_MANIFEST"
  [ "$status" -eq 0 ]
}

# ── Layer 2: the git repo is COMPACTED, never truncated ────────────────────────────────────────
@test "git gc runs on the plan-history repo and every commit survives" {
  # `git -C ""` is a NO-OP — guarded at the BINDING so both use sites below can read bare.
  : "${CC_PLAN_HISTORY_REPO:?plan-history fixture: repo path required}"
  git init -q "$CC_PLAN_HISTORY_REPO"
  git -C "$CC_PLAN_HISTORY_REPO" config user.email t@t; git -C "$CC_PLAN_HISTORY_REPO" config user.name t
  mkdir -p "$CC_PLAN_HISTORY_REPO/plans"
  local i
  for i in 1 2 3; do
    printf 'v%s\n' "$i" > "$CC_PLAN_HISTORY_REPO/plans/p.md"
    git -C "$CC_PLAN_HISTORY_REPO" add -A
    git -C "$CC_PLAN_HISTORY_REPO" commit -qm "v$i"
  done
  local before; before=$(git -C "$CC_PLAN_HISTORY_REPO" rev-list --count HEAD)

  run bash "$PRUNE"
  [ "$status" -eq 0 ]
  [ "$(git -C "$CC_PLAN_HISTORY_REPO" rev-list --count HEAD)" = "$before" ]
  [ -f "$CC_PLAN_HISTORY_REPO/plans/p.md" ]        # the working tree is NOT pruned
  run git -C "$CC_PLAN_HISTORY_REPO" fsck --no-progress
  [ "$status" -eq 0 ]
}

# ── the daily wiring exists where prune-backups' does ──────────────────────────────────────────
@test "session-start.sh invokes it daily, beside the backup prune" {
  run grep -c 'prune-plan-history.sh' "$REPO/hooks/session-start.sh"
  [ "$output" = "1" ]
  grep -q 'last-plan-history-prune' "$REPO/hooks/session-start.sh"
  run bash -n "$REPO/hooks/session-start.sh"
  [ "$status" -eq 0 ]
}

# ── concurrency guard ──────────────────────────────────────────────────────────────────────────
@test "a fresh lock makes a second run exit without touching the manifest" {
  local i; for i in $(seq 1 15); do rec iota "$i"; done
  mkdir -p "$TMPDIR/.plan-history-prune.lock"
  run bash "$PRUNE"
  [ "$status" -eq 0 ]
  [ "$(count)" -eq 15 ]
  rmdir "$TMPDIR/.plan-history-prune.lock"
}
