#!/usr/bin/env bats
# find-plan.sh --list-open — the desk's cross-project "what is ALL open work?" verb.
# Enumerates every plan (index ∪ disk scan, deduped) whose status is NOT terminal
# (complete/superseded), one line each: STATUS | project | path | title. A plan with
# no/unparseable status is listed as UNKNOWN — never hidden. Terminal plans are excluded.
#
# Also guards that the pre-existing name→content resolution still works (no regression).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FP="$REPO/scripts/find-plan.sh"
  export CC_PLAN_INDEX="$BATS_TEST_TMPDIR/plans-index.json"
  PA="$BATS_TEST_TMPDIR/projA"; PB="$BATS_TEST_TMPDIR/projB"
  mkdir -p "$PA/docs/plans" "$PB/docs/plans"
  printf -- '---\nstatus: open\ntitle: Alpha Roadmap\n---\n# Alpha\n' > "$PA/docs/plans/open1.md"
  printf -- '# Just A Heading\nbody\n'                                > "$PA/docs/plans/nostatus.md"
  printf -- '---\nstatus: complete\n---\n# Done\n'                    > "$PB/docs/plans/done.md"
  printf -- '---\nstatus: superseded\n---\n# Old\n'                   > "$PB/docs/plans/old.md"
  printf -- '---\nstatus: in-progress\ntitle: Bravo\n---\n# Bravo\n'  > "$PB/docs/plans/prog.md"
  export CC_PLAN_SCAN_ROOTS="$PA/docs/plans:$PB/docs/plans"
  echo '{"version":1,"plans":{}}' > "$CC_PLAN_INDEX"
}

list_open() { bash "$FP" --list-open; }

@test "lists an open plan with STATUS, project, path, and title" {
  run list_open
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'OPEN.*projA.*open1\.md.*Alpha Roadmap'
}

@test "status-less plan is listed as UNKNOWN (never hidden)" {
  run list_open
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'UNKNOWN.*nostatus\.md'
}

@test "in-progress plan is listed as IN-PROGRESS with its title" {
  run list_open
  echo "$output" | grep -qE 'IN-PROGRESS.*projB.*prog\.md.*Bravo'
}

@test "complete and superseded plans are EXCLUDED" {
  run list_open
  ! echo "$output" | grep -q 'done\.md'
  ! echo "$output" | grep -q 'old\.md'
}

@test "enumeration spans multiple projects (cross-project)" {
  run list_open
  echo "$output" | grep -q 'projA'
  echo "$output" | grep -q 'projB'
}

@test "reads the index: an indexed plan outside the scan roots still appears" {
  # Only projA is in the scan roots; projB's plan is discoverable ONLY via the index.
  export CC_PLAN_SCAN_ROOTS="$PA/docs/plans"
  idxplan="$PB/docs/plans/prog.md"
  jq --arg k "$idxplan" '.plans[$k]={project:"'"$PB"'",projectName:"projB",path:$k,namespace:"docs-plans"}' \
    "$CC_PLAN_INDEX" > "$CC_PLAN_INDEX.t" && mv "$CC_PLAN_INDEX.t" "$CC_PLAN_INDEX"
  run list_open
  echo "$output" | grep -qE 'IN-PROGRESS.*prog\.md'
}

@test "empty index + empty disk → exit 0, no output" {
  export CC_PLAN_SCAN_ROOTS="$BATS_TEST_TMPDIR/none"
  echo '{"version":1,"plans":{}}' > "$CC_PLAN_INDEX"
  run list_open
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "regression: name→content resolution by absolute path still works" {
  run bash "$FP" "$PA/docs/plans/open1.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '# Alpha'
}
