#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
# cc-task-store — merges per-account task boards into ONE shared store without losing a task.
#
# Fully hermetic: CC_TASKS_DIR / CC_ACCOUNTS_JSON / CC_TASKS_INDEX / CC_TASKS_BACKUP_ROOT all point
# into BATS_TEST_TMPDIR, so no test can read or write the operator's live ~/.claude/tasks. That is
# not politeness — the tool's whole job is bulk-rewriting task ids, and a suite that reached the
# real store could renumber the operator's live board.
#
# The load-bearing tests are:
#   * "two sources into ONE board" — the regression test for a real bug in this tool (each move was
#     planned independently against disk, so account-3 and account-4 both allocated ids 40,41,42 for
#     claude-infrastructure-main). The overwrite guard caught it, but a plan the operator approves
#     has to be correct BEFORE the guard fires.
#   * "verify FAILS when a task is missing" — the positive control. Without it, `verify` returning OK
#     proves nothing, because a verifier that can never fail reports success on an empty merge too.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  C="$REPO/bin/cc-task-store"
  D="$BATS_TEST_TMPDIR"
  export CC_TASKS_DIR="$D/canonical"
  export CC_TASKS_INDEX="$D/tasks-index.json"
  export CC_ACCOUNTS_JSON="$D/accounts.json"
  export CC_TASKS_BACKUP_ROOT="$D/backups"
  mkdir -p "$CC_TASKS_DIR"
  printf '{"taskLists":{}}\n' > "$CC_TASKS_INDEX"

  acct() { mkdir -p "$D/$1/tasks"; }        # a per-account config dir with a real (isolated) store
  accounts() {                              # accounts() acct2 acct3 … → write accounts.json
    local j='{"accounts":['; local sep=""
    for a in "$@"; do j="$j$sep{\"config_dir\":\"$D/$a\"}"; sep=","; done
    printf '%s]}\n' "$j" > "$CC_ACCOUNTS_JSON"
  }
  # mktask <listdir> <id> <subject> [desc] [blocks-csv] [blockedBy-csv]
  # Shape matches what Claude Code actually writes (id/subject/description/activeForm/status +
  # ALWAYS-present blocks/blockedBy arrays). `select(.!="")` was the first spelling of the array
  # fields and it silently emitted NOTHING for the empty case, so every dependency-free fixture was
  # a zero-byte file and the tests exercising them passed vacuously — a fixture is a claim about the
  # producer, so it has to be built the way the producer builds it.
  mktask() {
    local dir="$1" id="$2" subj="$3" desc="${4:-}" blk="${5:-}" bby="${6:-}"
    mkdir -p "$dir"
    jq -nc --arg id "$id" --arg s "$subj" --arg d "$desc" --arg b "$blk" --arg y "$bby" \
      '{id:$id,subject:$s,description:$d,activeForm:$s,status:"pending",
        blocks:   (if $b == "" then [] else ($b | split(",")) end),
        blockedBy:(if $y == "" then [] else ($y | split(",")) end)}' > "$dir/$id.json"
    [ -s "$dir/$id.json" ] || { echo "mktask produced an EMPTY fixture for $dir/$id" >&2; return 1; }
  }
  subjects() { cat "$1"/[0-9]*.json 2>/dev/null | jq -r '.subject' | sort; }
  ids()      { find "$1" -maxdepth 1 -name '*.json' ! -name '_summary.json' -exec basename {} .json \; | sort -n; }
}

@test "plan is read-only — it writes nothing" {
  acct a2; accounts a2
  mktask "$D/a2/tasks/proj" 1 "from-a2"
  before="$(find "$CC_TASKS_DIR" -type f | wc -l)"
  run "$C" plan
  [ "$status" -eq 0 ]
  [ "$(find "$CC_TASKS_DIR" -type f | wc -l)" -eq "$before" ]
}

@test "board present only in a source is created in the shared store" {
  acct a2; accounts a2
  mktask "$D/a2/tasks/proj" 1 "only-in-a2"
  run "$C" merge --yes
  [ "$status" -eq 0 ]
  [ -f "$CC_TASKS_DIR/proj/1.json" ]
  subjects "$CC_TASKS_DIR/proj" | grep -q 'only-in-a2' || false
}

@test "colliding ids are renumbered above the target — the incumbent is never overwritten" {
  acct a2; accounts a2
  mktask "$CC_TASKS_DIR/proj" 1 "canonical-one"
  mktask "$CC_TASKS_DIR/proj" 2 "canonical-two"
  mktask "$D/a2/tasks/proj"   1 "account-one"     # same id 1, DIFFERENT task
  mktask "$D/a2/tasks/proj"   2 "account-two"
  run "$C" merge --yes
  [ "$status" -eq 0 ]
  # the incumbents are untouched…
  [ "$(jq -r .subject "$CC_TASKS_DIR/proj/1.json")" = "canonical-one" ]
  [ "$(jq -r .subject "$CC_TASKS_DIR/proj/2.json")" = "canonical-two" ]
  # …and all four tasks exist
  [ "$(subjects "$CC_TASKS_DIR/proj" | wc -l | tr -d ' ')" -eq 4 ]
  subjects "$CC_TASKS_DIR/proj" | grep -q 'account-one' || false
  subjects "$CC_TASKS_DIR/proj" | grep -q 'account-two' || false
}

@test "two sources into ONE board get DISJOINT ids (allocator threads state across moves)" {
  acct a2; acct a3; accounts a2 a3
  mktask "$CC_TASKS_DIR/proj" 5 "incumbent"
  mktask "$D/a2/tasks/proj" 1 "from-a2-alpha"
  mktask "$D/a2/tasks/proj" 2 "from-a2-beta"
  mktask "$D/a3/tasks/proj" 1 "from-a3-alpha"
  mktask "$D/a3/tasks/proj" 2 "from-a3-beta"
  run "$C" merge --yes
  [ "$status" -eq 0 ]
  # 1 incumbent + 4 merged, every id distinct → 5 files and 5 unique ids
  [ "$(ids "$CC_TASKS_DIR/proj" | wc -l | tr -d ' ')" -eq 5 ]
  [ "$(ids "$CC_TASKS_DIR/proj" | sort -u | wc -l | tr -d ' ')" -eq 5 ]
  [ "$(subjects "$CC_TASKS_DIR/proj" | sort -u | wc -l | tr -d ' ')" -eq 5 ]
}

@test "blocks/blockedBy are remapped to the NEW ids, not left pointing at strangers" {
  acct a2; accounts a2
  mktask "$CC_TASKS_DIR/proj" 1 "incumbent-one"
  mktask "$CC_TASKS_DIR/proj" 2 "incumbent-two"
  mktask "$D/a2/tasks/proj" 1 "src-parent" "" "2" ""     # blocks src task 2
  mktask "$D/a2/tasks/proj" 2 "src-child"  "" ""  "1"    # blockedBy src task 1
  run "$C" merge --yes
  [ "$status" -eq 0 ]
  pid="$(grep -l 'src-parent' "$CC_TASKS_DIR/proj"/[0-9]*.json | head -1)"
  cid="$(grep -l 'src-child'  "$CC_TASKS_DIR/proj"/[0-9]*.json | head -1)"
  pnum="$(basename "$pid" .json)"; cnum="$(basename "$cid" .json)"
  # the reference must point at the child's NEW id — never at the incumbent id 2
  [ "$(jq -r '.blocks[0]' "$pid")" = "$cnum" ]
  [ "$(jq -r '.blockedBy[0]' "$cid")" = "$pnum" ]
  [ "$(jq -r '.blocks[0]' "$pid")" != "2" ] || false
}

@test "an unresolvable dependency reference is dropped AND reported, never silently kept" {
  acct a2; accounts a2
  mktask "$D/a2/tasks/proj" 1 "orphan-ref" "" "999" ""    # 999 does not exist in the source
  run "$C" merge --yes
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "unresolvable" || false
  f="$(grep -l 'orphan-ref' "$CC_TASKS_DIR/proj"/[0-9]*.json | head -1)"
  [ "$(jq -r '.blocks | length' "$f")" -eq 0 ]
}

@test "identical content is deduped, and a re-run adds nothing (idempotent)" {
  acct a2; accounts a2
  mktask "$CC_TASKS_DIR/proj" 1 "same-task" "same-desc"
  mktask "$D/a2/tasks/proj"   7 "same-task" "same-desc"
  run "$C" merge --yes
  [ "$status" -eq 0 ]
  [ "$(ids "$CC_TASKS_DIR/proj" | wc -l | tr -d ' ')" -eq 1 ]
  run "$C" merge --yes                     # second run must be a no-op
  [ "$status" -eq 0 ]
  [ "$(ids "$CC_TASKS_DIR/proj" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "re-running after a real merge does not duplicate the merged tasks" {
  acct a2; accounts a2
  mktask "$D/a2/tasks/proj" 1 "alpha"
  mktask "$D/a2/tasks/proj" 2 "beta"
  run "$C" merge --yes
  [ "$status" -eq 0 ]
  n1="$(ids "$CC_TASKS_DIR/proj" | wc -l | tr -d ' ')"
  run "$C" merge --yes
  [ "$status" -eq 0 ]
  [ "$(ids "$CC_TASKS_DIR/proj" | wc -l | tr -d ' ')" -eq "$n1" ]
}

@test "source stores are NEVER modified — the merge is additive only" {
  acct a2; accounts a2
  mktask "$D/a2/tasks/proj" 1 "keep-me"
  sig_before="$(find "$D/a2/tasks" -type f -exec shasum {} \; | sort)"
  run "$C" merge --yes
  [ "$status" -eq 0 ]
  [ "$(find "$D/a2/tasks" -type f -exec shasum {} \; | sort)" = "$sig_before" ]
}

@test "a store already SYMLINKED to canonical is not treated as a source (no self-merge)" {
  acct a2; mkdir -p "$D/a1"; ln -s "$CC_TASKS_DIR" "$D/a1/tasks"; accounts a1 a2
  mktask "$CC_TASKS_DIR/proj" 1 "canonical-task"
  run "$C" merge --yes
  [ "$status" -eq 0 ]
  [ "$(ids "$CC_TASKS_DIR/proj" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "verify passes after a merge (no loss)" {
  acct a2; accounts a2
  mktask "$CC_TASKS_DIR/proj" 1 "incumbent"
  mktask "$D/a2/tasks/proj" 1 "merged-a"
  mktask "$D/a2/tasks/proj" 2 "merged-b"
  run "$C" merge --yes
  [ "$status" -eq 0 ]
  run "$C" verify
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'no loss' || false
}

@test "verify FAILS when a source task is absent — the positive control" {
  acct a2; accounts a2
  mktask "$D/a2/tasks/proj" 1 "never-merged"
  run "$C" verify                       # no merge was run, so the task cannot be present
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'FAIL' || false
  echo "$output" | grep -q 'never-merged' || false
}

@test "merge takes a backup before writing" {
  acct a2; accounts a2
  mktask "$D/a2/tasks/proj" 1 "backed-up"
  run "$C" merge --yes
  [ "$status" -eq 0 ]
  [ -d "$CC_TASKS_BACKUP_ROOT" ]
  [ "$(find "$CC_TASKS_BACKUP_ROOT" -name '1.json' | wc -l | tr -d ' ')" -ge 1 ]
}

@test "merged tasks carry provenance (which account, which original id)" {
  acct a2; accounts a2
  mktask "$D/a2/tasks/proj" 9 "traceable"
  run "$C" merge --yes
  [ "$status" -eq 0 ]
  f="$(grep -l 'traceable' "$CC_TASKS_DIR/proj"/[0-9]*.json | head -1)"
  [ "$(jq -r '.metadata.originalId' "$f")" = "9" ]
  [ "$(jq -r '.metadata.mergedFrom' "$f")" = "a2" ]
}

@test "_summary.json is rebuilt so the board header matches what is on disk" {
  acct a2; accounts a2
  mktask "$CC_TASKS_DIR/proj" 1 "one"
  printf '{"taskListId":"proj","totalOnDisk":99,"tasks":[]}\n' > "$CC_TASKS_DIR/proj/_summary.json"
  mktask "$D/a2/tasks/proj" 1 "two"
  run "$C" merge --yes
  [ "$status" -eq 0 ]
  [ "$(jq -r '.totalOnDisk' "$CC_TASKS_DIR/proj/_summary.json")" -eq 2 ]
  [ "$(jq -r '.tasks | length' "$CC_TASKS_DIR/proj/_summary.json")" -eq 2 ]
}

@test "empty source boards are skipped, not materialised as empty shells" {
  acct a2; accounts a2
  mkdir -p "$D/a2/tasks/hollow"
  run "$C" merge --yes
  [ "$status" -eq 0 ]
  [ ! -d "$CC_TASKS_DIR/hollow" ]
}
