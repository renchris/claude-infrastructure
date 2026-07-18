#!/usr/bin/env bats
# plan-index-update.sh — dual-mode plan indexer.
#   (hook mode)  PostToolUse Write/Edit: index a plan write into plans-index.json.
#   (reconcile)  `plan-index-update.sh reconcile`: rebuild the index from disk truth,
#                pruning phantom entries (file-missing ⇒ drop), preserving firstIndexed.
#
# Coverage: the three indexed namespaces (~/.claude/plans = global, */docs/plans,
# */.claude-plans); non-plan write is ignored; abspath keying (no cross-project
# basename collision); reconcile prunes phantoms, adds disk truth, refreshes
# `generated`, and preserves firstIndexed on survivors.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/plan-index-update.sh"
  export CC_PLAN_INDEX="$BATS_TEST_TMPDIR/plans-index.json"
  export CC_PLANS_DIR="$BATS_TEST_TMPDIR/global-plans"      # stands in for ~/.claude/plans
  mkdir -p "$CC_PLANS_DIR"
  # Two fake projects, each with a docs/plans store.
  PROJA="$BATS_TEST_TMPDIR/projA"; PROJB="$BATS_TEST_TMPDIR/projB"
  mkdir -p "$PROJA/docs/plans" "$PROJB/docs/plans" "$PROJA/.claude-plans"
  export CC_PLAN_SCAN_ROOTS="$CC_PLANS_DIR:$PROJA/docs/plans:$PROJB/docs/plans:$PROJA/.claude-plans"
}

# Drive the PostToolUse hook: $1=file_path $2=cwd(optional).
drive() { printf '{"tool_input":{"file_path":"%s"},"cwd":"%s"}' "$1" "${2:-$PROJA}" | bash "$HOOK"; }

@test "hook: docs/plans write is indexed by abspath with projectName + namespace" {
  f="$PROJA/docs/plans/roadmap.md"; echo "# Roadmap" > "$f"
  run drive "$f"
  [ "$status" -eq 0 ]
  run jq -r --arg k "$f" '.plans[$k].projectName' "$CC_PLAN_INDEX"
  [ "$output" = "projA" ]
  run jq -r --arg k "$f" '.plans[$k].namespace' "$CC_PLAN_INDEX"
  [ "$output" = "docs-plans" ]
  run jq -r --arg k "$f" '.plans[$k].path' "$CC_PLAN_INDEX"
  [ "$output" = "$f" ]
}

@test "hook: .claude-plans write is indexed with namespace claude-plans" {
  f="$PROJA/.claude-plans/feature.md"; echo "# Feature" > "$f"
  run drive "$f"
  [ "$status" -eq 0 ]
  run jq -r --arg k "$f" '.plans[$k].namespace' "$CC_PLAN_INDEX"
  [ "$output" = "claude-plans" ]
}

@test "hook: global ~/.claude/plans write is indexed (project from cwd)" {
  f="$CC_PLANS_DIR/adjective-noun.md"; echo "# Plan" > "$f"
  run drive "$f" "$PROJB"
  [ "$status" -eq 0 ]
  run jq -r --arg k "$f" '.plans[$k].namespace' "$CC_PLAN_INDEX"
  [ "$output" = "global" ]
  run jq -r --arg k "$f" '.plans[$k].projectName' "$CC_PLAN_INDEX"
  [ "$output" = "projB" ]
}

@test "hook: same basename in two projects does NOT collide (distinct abspath keys)" {
  a="$PROJA/docs/plans/PLAN.md"; b="$PROJB/docs/plans/PLAN.md"
  echo x > "$a"; echo y > "$b"
  drive "$a" "$PROJA"; drive "$b" "$PROJB"
  run jq -r '.plans | length' "$CC_PLAN_INDEX"
  [ "$output" = "2" ]
}

@test "hook: non-plan file is ignored (no index created)" {
  f="$PROJA/src/main.ts"; mkdir -p "$(dirname "$f")"; echo "code" > "$f"
  run drive "$f"
  [ "$status" -eq 0 ]
  [ ! -f "$CC_PLAN_INDEX" ]
}

@test "reconcile: prunes a phantom entry whose file is gone" {
  gone="$PROJA/docs/plans/deleted.md"
  printf '{"version":1,"plans":{"%s":{"project":"%s","projectName":"projA","path":"%s","firstIndexed":"2020-01-01T00:00:00.000Z"}}}\n' \
    "$gone" "$PROJA" "$gone" > "$CC_PLAN_INDEX"
  run bash "$HOOK" reconcile
  [ "$status" -eq 0 ]
  run jq -r --arg k "$gone" '.plans | has($k)' "$CC_PLAN_INDEX"
  [ "$output" = "false" ]
}

@test "reconcile: adds a plan present on disk but missing from the index" {
  echo '{"version":1,"plans":{}}' > "$CC_PLAN_INDEX"
  f="$PROJB/docs/plans/fresh.md"; echo "# Fresh" > "$f"
  run bash "$HOOK" reconcile
  [ "$status" -eq 0 ]
  run jq -r --arg k "$f" '.plans[$k].projectName' "$CC_PLAN_INDEX"
  [ "$output" = "projB" ]
}

@test "reconcile: refreshes generated and preserves firstIndexed on survivors" {
  f="$PROJA/docs/plans/keep.md"; echo "# Keep" > "$f"
  printf '{"version":1,"generated":"2020-01-01T00:00:00.000Z","plans":{"%s":{"project":"%s","projectName":"projA","path":"%s","firstIndexed":"2020-06-03T00:00:00.000Z"}}}\n' \
    "$f" "$PROJA" "$f" > "$CC_PLAN_INDEX"
  run bash "$HOOK" reconcile
  [ "$status" -eq 0 ]
  run jq -r --arg k "$f" '.plans[$k].firstIndexed' "$CC_PLAN_INDEX"
  [ "$output" = "2020-06-03T00:00:00.000Z" ]        # preserved
  run jq -r '.generated' "$CC_PLAN_INDEX"
  [ "$output" != "2020-01-01T00:00:00.000Z" ]       # refreshed
}

@test "reconcile: empty disk + all-phantom index yields empty plans (all pruned)" {
  export CC_PLAN_SCAN_ROOTS="$BATS_TEST_TMPDIR/nonexistent"
  printf '{"version":1,"plans":{"ghost.md":{"projectName":"x"}}}\n' > "$CC_PLAN_INDEX"
  run bash "$HOOK" reconcile
  [ "$status" -eq 0 ]
  run jq -r '.plans | length' "$CC_PLAN_INDEX"
  [ "$output" = "0" ]
}

# ── Task 2: setup-plan-symlinks.sh truthful SessionStart counts ──────────────────
SYMHOOK() { echo "$REPO/hooks/setup-plan-symlinks.sh"; }
# Run the SessionStart hook with cwd=project; echo its additionalContext string.
sym_ctx() {
  local proj="$1"
  env CLAUDE_PROJECT_DIR="$proj" CC_PLAN_INDEX="$CC_PLAN_INDEX" CC_PLANS_DIR="$CC_PLANS_DIR" \
    bash -c "cd '$proj' && bash '$(SYMHOOK)'" | jq -r '.hookSpecificOutput.additionalContext'
}

@test "count: claude-infra-like project with 5 docs/plans reports 5, not 0" {
  proj="$BATS_TEST_TMPDIR/infra"; mkdir -p "$proj/docs/plans"
  for n in 1 2 3 4 5; do echo "# Plan $n" > "$proj/docs/plans/plan$n.md"; done
  echo '{"version":1,"plans":{}}' > "$CC_PLAN_INDEX"
  run sym_ctx "$proj"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'Plans: 5/5'          # status-less plans count as open
  ! echo "$output" | grep -qE 'Plans: 0'
}

@test "count: complete/superseded plans are not counted as open" {
  proj="$BATS_TEST_TMPDIR/mix"; mkdir -p "$proj/docs/plans"
  printf -- '---\nstatus: complete\n---\n# Done\n'      > "$proj/docs/plans/done.md"
  printf -- '---\nstatus: superseded\n---\n# Old\n'      > "$proj/docs/plans/old.md"
  printf -- '---\nstatus: open\n---\n# Live\n'           > "$proj/docs/plans/live.md"
  echo '{"version":1,"plans":{}}' > "$CC_PLAN_INDEX"
  run sym_ctx "$proj"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'Plans: 1/3'          # 1 open of 3 total
}

@test "count: all-projects total comes from the index" {
  proj="$BATS_TEST_TMPDIR/acc"; mkdir -p "$proj/docs/plans"
  echo "# P" > "$proj/docs/plans/p.md"
  printf '{"version":1,"plans":{"/a/docs/plans/x.md":{"project":"/a","namespace":"docs-plans"},"/b/docs/plans/y.md":{"project":"/b","namespace":"docs-plans"},"/c/docs/plans/z.md":{"project":"/c","namespace":"docs-plans"}}}\n' > "$CC_PLAN_INDEX"
  run sym_ctx "$proj"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '3 all'               # index length = 3
}
