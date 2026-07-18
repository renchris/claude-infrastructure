#!/usr/bin/env bats
# task-helpers.sh — project-scoped task-list resolution (G-P14-7).
#   find_active_list now filters by project via the tasks-index map: it returns
#   only a list mapped to the queried project, NEVER a globally-most-recent foreign
#   list. Unmapped (UUID/foreign) lists never surface. Adds a `--all-open` rollup
#   over every project's open task lists.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/hooks/lib/task-helpers.sh"
  export CC_TASKS_DIR="$BATS_TEST_TMPDIR/tasks"
  export CC_TASKS_INDEX="$BATS_TEST_TMPDIR/tasks-index.json"
  mkdir -p "$CC_TASKS_DIR"
  PA="$BATS_TEST_TMPDIR/projA"; PB="$BATS_TEST_TMPDIR/projB"
  echo '{"version":1,"taskLists":{}}' > "$CC_TASKS_INDEX"
  # shellcheck source=/dev/null
  . "$LIB"
}

# mk_list <listid> <mtime YYYYMMDDhhmm> <status>  — one task at that status+mtime.
mk_list() {
  local d="$CC_TASKS_DIR/$1"; mkdir -p "$d"
  printf '{"id":1,"subject":"t","description":"d","status":"%s"}' "${3:-pending}" > "$d/1.json"
  touch -t "$2" "$d/1.json"
}
# add_map <listid> <projectPath> <projectName>
add_map() {
  jq --arg k "$1" --arg p "$2" --arg pn "$3" '.taskLists[$k]={project:$p,projectName:$pn}' \
    "$CC_TASKS_INDEX" > "$CC_TASKS_INDEX.t" && mv "$CC_TASKS_INDEX.t" "$CC_TASKS_INDEX"
}

@test "find_active_list returns THIS project's list, not a newer foreign one" {
  mk_list listA 202601010000 pending
  mk_list listB 202612310000 pending          # newer, belongs to projB
  add_map listA "$PA" projA
  add_map listB "$PB" projB
  run find_active_list "$PA" "$CC_TASKS_INDEX"
  [ "$output" = "listA" ]
}

@test "find_active_list scopes correctly for the other project too" {
  mk_list listA 202601010000 pending
  mk_list listB 202612310000 pending
  add_map listA "$PA" projA
  add_map listB "$PB" projB
  run find_active_list "$PB" "$CC_TASKS_INDEX"
  [ "$output" = "listB" ]
}

@test "find_active_list ignores an unmapped (UUID/foreign) list even if newest" {
  mk_list listA 202601010000 pending
  mk_list uuidX 202612310000 pending          # newest, unmapped
  add_map listA "$PA" projA
  run find_active_list "$PA" "$CC_TASKS_INDEX"
  [ "$output" = "listA" ]
}

@test "find_active_list returns empty when NO list maps to the project (no foreign fallback)" {
  mk_list listB 202612310000 pending          # only a foreign list exists
  add_map listB "$PB" projB
  run find_active_list "$PA" "$CC_TASKS_INDEX"
  [ -z "$output" ]
}

@test "find_active_list with no project arg keeps legacy global-most-recent behavior" {
  mk_list listA 202601010000 pending
  mk_list listB 202612310000 pending
  run find_active_list "" "$CC_TASKS_INDEX"
  [ "$output" = "listB" ]                      # newest, unfiltered
}

@test "--all-open rollup lists every project's open task lists" {
  mk_list listA 202601010000 pending
  mk_list listB 202601020000 in_progress
  mk_list listC 202601030000 completed        # 0 open ⇒ excluded
  add_map listA "$PA" projA
  add_map listB "$PB" projB
  add_map listC "$PA" projA
  run bash "$LIB" --all-open
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'projA'
  echo "$output" | grep -q 'projB'
  echo "$output" | grep -q 'listA'
  echo "$output" | grep -q 'listB'
  ! echo "$output" | grep -q 'listC'
}

@test "--all-open shows an unmapped open list as (unmapped), never silently dropped" {
  mk_list uuidZ 202601040000 pending          # open but not in the index
  run bash "$LIB" --all-open
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'uuidZ'
  echo "$output" | grep -qi 'unmapped'
}
