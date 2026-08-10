#!/usr/bin/env bats
# setup-task-symlinks — the _summary.json freshness guard (scaling-bottlenecks-2026-08-09 §5
# P0-2, item a7eebe63d0d0). The guard is what keeps ~2,155 mostly-empty task dirs from being
# re-summarised on every session start; these tests pin each guard branch by CONTENT (a
# sentinel that only regenerate_summary would overwrite), never by mtime comparison, and the
# CC_TASKS_SUMMARY_FORCE control proves the guard — not something upstream — is what preserves
# the sentinel (per-site mutation discipline: a neutered guard turns test 1 red via the control
# staying green).

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_TASKS_DIR="$BATS_TEST_TMPDIR/tasks"; mkdir -p "$CC_TASKS_DIR"
  export CC_TASKS_INDEX="$BATS_TEST_TMPDIR/tasks-index.json"
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/proj"; mkdir -p "$CLAUDE_PROJECT_DIR"
  unset CLAUDE_CODE_TASK_LIST_ID CC_TASKS_SUMMARY_FORCE 2>/dev/null || true
  HOOK="$BATS_TEST_DIRNAME/../hooks/setup-task-symlinks.sh"
}

run_hook() { (cd "$CLAUDE_PROJECT_DIR" && bash "$HOOK"); }

mk_fresh_dir() {  # a dir whose summary POSTDATES its one task → guard must skip it
  local d="$CC_TASKS_DIR/$1"; mkdir -p "$d"
  printf '{"id":"1","status":"pending","description":"seed"}\n' > "$d/t1.json"
  touch -t 202601010000 "$d/t1.json"
  printf 'SENTINEL-%s\n' "$1" > "$d/_summary.json"
}

@test "fresh dir is skipped: summary content survives a run" {
  mk_fresh_dir alpha
  run run_hook
  [ "$status" -eq 0 ]
  grep -q "SENTINEL-alpha" "$CC_TASKS_DIR/alpha/_summary.json"
}

@test "stale dir regenerates: a task newer than the summary overwrites the sentinel" {
  local d="$CC_TASKS_DIR/beta"; mkdir -p "$d"
  printf 'SENTINEL-beta\n' > "$d/_summary.json"
  touch -t 202601010000 "$d/_summary.json"
  printf '{"id":"1","status":"pending","description":"seed"}\n' > "$d/t1.json"   # now > summary
  run run_hook
  [ "$status" -eq 0 ]
  ! grep -q "SENTINEL-beta" "$d/_summary.json"
}

@test "tasks with no summary regenerate" {
  local d="$CC_TASKS_DIR/gamma"; mkdir -p "$d"
  printf '{"id":"1","status":"pending","description":"seed"}\n' > "$d/t1.json"
  run run_hook
  [ "$status" -eq 0 ]
  [ -f "$d/_summary.json" ]
}

@test "empty dir with no summary stays untouched (the 97% mass case)" {
  mkdir -p "$CC_TASKS_DIR/delta"
  run run_hook
  [ "$status" -eq 0 ]
  [ ! -f "$CC_TASKS_DIR/delta/_summary.json" ]
}

@test "control: CC_TASKS_SUMMARY_FORCE=1 rewrites even the fresh dir (guard is load-bearing)" {
  mk_fresh_dir epsilon
  CC_TASKS_SUMMARY_FORCE=1 run run_hook
  [ "$status" -eq 0 ]
  ! grep -q "SENTINEL-epsilon" "$CC_TASKS_DIR/epsilon/_summary.json"
}
