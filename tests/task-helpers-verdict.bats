#!/usr/bin/env bats
# task-helpers.sh find_active_list — the THREE-STATE VERDICT and the WORK BOUND.
#
# Backlog row 22705859d07d filed this as "5s of dead time + rc=124 indistinguishable from
# 'no active list'". The PERFORMANCE half was already fixed by d31fee77f (2026-08-11 14:42,
# the same day the row was measured): the function is 0.11 s on the live 2,640-dir store, so
# the 5 s hook timeout can no longer fire and rc=124 is unreachable. The CORRECTNESS half
# survived that fix untouched, because it was never about the timeout: an unreadable index
# and a genuinely-unmapped project BOTH printed "" and returned 0. This suite pins the
# distinction, and pins the work bound in the unit that does not move with machine load.
#
# WHY WORK COUNT, NOT SECONDS. A wall-clock assertion sized in the foreground becomes a
# permanent non-verdict once this box demotes background work to PRI=4. The durable
# invariant the perf fix actually established is O(1) index reads — ONE `jq`, and zero
# per-directory forks — so that is what is asserted, via PATH shims that count execs.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/hooks/lib/task-helpers.sh"
  # Hermeticity: $HOME too, not just the CC_* overrides — the lib falls back to
  # "$HOME/.claude/tasks" whenever CC_TASKS_DIR does not exist, which is exactly the state
  # a few of these cases construct on purpose.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  export CC_TASKS_DIR="$BATS_TEST_TMPDIR/tasks"
  export CC_TASKS_INDEX="$BATS_TEST_TMPDIR/tasks-index.json"
  mkdir -p "$CC_TASKS_DIR"
  PA="$BATS_TEST_TMPDIR/projA"; PB="$BATS_TEST_TMPDIR/projB"
  echo '{"version":1,"taskLists":{}}' > "$CC_TASKS_INDEX"
  # shellcheck source=/dev/null
  . "$LIB"
}

mk_list() {
  local d="$CC_TASKS_DIR/$1"; mkdir -p "$d"
  printf '{"id":1,"subject":"t","description":"d","status":"%s"}' "${3:-pending}" > "$d/1.json"
  touch -t "$2" "$d/1.json"
}
add_map() {
  jq --arg k "$1" --arg p "$2" --arg pn "$3" '.taskLists[$k]={project:$p,projectName:$pn}' \
    "$CC_TASKS_INDEX" > "$CC_TASKS_INDEX.t" && mv "$CC_TASKS_INDEX.t" "$CC_TASKS_INDEX"
}

# ── The three states ────────────────────────────────────────────────────────────────

@test "FOUND — a mapped list returns rc 0 and its id" {
  mk_list listA 202601010000 pending
  add_map listA "$PA" projA
  run find_active_list "$PA" "$CC_TASKS_INDEX"
  [ "$status" -eq 0 ]
  [ "$output" = "listA" ]
}

@test "NONE — index readable, nothing maps: rc 0 and empty (a real answer)" {
  mk_list listB 202612310000 pending
  add_map listB "$PB" projB
  run find_active_list "$PA" "$CC_TASKS_INDEX"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "UNDETERMINED — a MISSING index is rc 2, not a silent 'none'" {
  mk_list listA 202601010000 pending
  run find_active_list "$PA" "$BATS_TEST_TMPDIR/no-such-index.json"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "UNDETERMINED — an UNPARSEABLE index is rc 2, not a silent 'none'" {
  # The load-bearing case. Byte-identical stdout to the NONE case above, so stdout alone
  # can never separate them; before the fix the rc was identical too, and every consumer
  # read "this project has no task list" off a question that was never answered.
  mk_list listA 202601010000 pending
  add_map listA "$PA" projA
  printf 'this is not json {{{' > "$CC_TASKS_INDEX"
  run find_active_list "$PA" "$CC_TASKS_INDEX"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "UNDETERMINED — jq unavailable is rc 2 (the tool, not the data, is missing)" {
  mk_list listA 202601010000 pending
  add_map listA "$PA" projA
  local shim="$BATS_TEST_TMPDIR/nojq"; mkdir -p "$shim"
  # A shim exiting 127 — the shell's own command-not-found status, indistinguishable from
  # absence to the function. Emptying PATH instead would be a WEAKER control and a
  # non-hermetic one: this box ships BOTH /opt/homebrew/bin/jq and /usr/bin/jq, so a
  # PATH=/usr/bin:/bin "removal" still resolves jq and the case passed vacuously.
  printf '#!/bin/bash\nexit 127\n' > "$shim/jq"; chmod +x "$shim/jq"
  PATH="$shim:$PATH" run find_active_list "$PA" "$CC_TASKS_INDEX"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "an EMPTY task store is NONE (rc 0), not UNDETERMINED" {
  # "There are no lists" is an answer. Only an unanswerable question earns rc 2, or the
  # new state fires on the ordinary first-run case and carries no information.
  add_map listA "$PA" projA
  rm -rf "${CC_TASKS_DIR:?}"/*
  run find_active_list "$PA" "$CC_TASKS_INDEX"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the legacy no-project path never returns UNDETERMINED" {
  # It reads no index at all, so it has no unanswerable case; a rc 2 here would strand
  # the two callers that invoke find_active_list with no arguments.
  mk_list listA 202601010000 pending
  run find_active_list "" "$BATS_TEST_TMPDIR/no-such-index.json"
  [ "$status" -eq 0 ]
  [ "$output" = "listA" ]
}

@test "the --active CLI entrypoint propagates the verdict rc" {
  mk_list listA 202601010000 pending
  add_map listA "$PA" projA
  run bash "$LIB" --active "$PA" "$CC_TASKS_INDEX"
  [ "$status" -eq 0 ]
  [ "$output" = "listA" ]
  run bash "$LIB" --active "$PA" "$BATS_TEST_TMPDIR/no-such-index.json"
  [ "$status" -eq 2 ]
}

# ── The work bound ──────────────────────────────────────────────────────────────────

@test "the work bound is O(1) index reads: ONE jq and ZERO per-directory forks" {
  # 60 task-list directories, 1 mapped. The pre-d31fee77f implementation forked a jq per
  # DIRECTORY (each re-reading the whole index) plus basename+ls+head+stat per directory —
  # 2,400 dirs x a 136 KB index ~ 21 s. Counting execs instead of seconds keeps this
  # assertion valid under the background QoS band, where a timing bound cannot survive.
  local shim="$BATS_TEST_TMPDIR/shim"; mkdir -p "$shim"
  local jqc="$BATS_TEST_TMPDIR/jq.count" forkc="$BATS_TEST_TMPDIR/fork.count"
  : > "$jqc"; : > "$forkc"
  local realjq; realjq="$(command -v jq)"
  printf '#!/bin/bash\necho x >> "%s"\nexec "%s" "$@"\n' "$jqc" "$realjq" > "$shim/jq"
  local f
  for f in basename ls head stat wc cat; do
    printf '#!/bin/bash\necho %s >> "%s"\nexec /usr/bin/%s "$@"\n' "$f" "$forkc" "$f" > "$shim/$f"
  done
  chmod +x "$shim"/*

  local i
  for i in $(seq 1 60); do mk_list "bulk$i" 20260101000"$((i % 10))" pending; done
  add_map bulk7 "$PA" projA

  PATH="$shim:$PATH" run find_active_list "$PA" "$CC_TASKS_INDEX"
  [ "$status" -eq 0 ]
  [ "$output" = "bulk7" ]
  # Exactly one index read, independent of the 60 directories.
  # MUTATION-PROVEN: re-inserting the historical per-directory `jq -r .taskLists "$index"`
  # into the loop reds exactly this line (jq count 60, not 1) and nothing else.
  [ "$(grep -c . < "$jqc")" -eq 1 ]
  # And not one per-directory helper fork. Reported by name so a regression names itself.
  # HONEST COVERAGE NOTE: this second assertion is NOT mutation-proven. Restoring the
  # historical `listid=$(basename "$dir")` made the suite exceed its 90 s bound and emit no
  # ok/not ok line at all — the shims are themselves bash scripts, so 60 extra forks land on
  # top of every fork bats already makes. A timeout is not a verdict, so this is kept as a
  # documented invariant guard, not as evidence. The jq assertion above carries the proof.
  [ "$(grep -c . < "$forkc")" -eq 0 ]
}
