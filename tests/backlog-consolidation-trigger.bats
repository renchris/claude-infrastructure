#!/usr/bin/env bats
# backlog-consolidation-trigger: notice the duplicate-cluster shape before a human has to.
#
# THE POSITIVE CONTROL LIVES HERE, DELIBERATELY. Measured on the live store 2026-08-10 (after the
# 161-item prune) there is not a single cluster at threshold 2 — the shape is real but currently
# absent. A detector verified only against that store would be indistinguishable from a broken one
# returning empty, which is the "a null from a blind instrument is not absence" failure. So the
# fixture below MANUFACTURES the exact shape that occurred: N rows differing only by an embedded sha.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="$REPO/scripts/backlog-consolidation-trigger.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/autonomy"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  : > "$CC_BACKLOG_FILE"
}

# row <id> <title> [event]
row() {
  printf '{"id":"%s","ts":"2026-08-01T00:00:00Z","event":"%s","project":"p","title":"%s"}\n' \
    "$1" "${3:-add}" "$2" >> "$CC_BACKLOG_FILE"
}

# The real shape: post-land RED for ONE suite, one row per culprit sha.
seed_sha_cluster() {
  local n="$1" i sha
  for i in $(seq 1 "$n"); do
    sha="$(printf 'deadbee%04d' "$i")"
    row "id$i$(printf '%08d' "$i")" "post-land RED: tests/deploy-parity.bats @ $sha"
  done
}

@test "POSITIVE CONTROL: N rows differing only by an embedded sha are ONE cluster" {
  seed_sha_cluster 6
  run "$SUT" --threshold 5
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "1 cluster"
  printf '%s' "$output" | grep -q "6x"
}

@test "below the threshold it is SILENT — an alarm that always fires carries no bits" {
  seed_sha_cluster 3
  run "$SUT" --threshold 5
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "no cluster at/above 5"
}

@test "genuinely distinct items are NOT collapsed" {
  row a1aaaaaaaaaa "fix the wake path so a session is not deaf by default"
  row b2bbbbbbbbbb "the memory index is over its loader cap and truncates silently"
  row c3cccccccccc "worktree population is over its janitor ceiling"
  row d4dddddddddd "deploy-live refuses because no green stamp is in the scan window"
  row e5eeeeeeeeee "cc-premise cannot re-run a falsifier at claim time"
  run "$SUT" --threshold 2
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "no cluster at/above 2"
}

@test "CLOSED rows leave the population — consolidating a cluster silences the trigger" {
  seed_sha_cluster 6
  run "$SUT" --threshold 5
  printf '%s' "$output" | grep -q "6x"
  # close five of the six, as a consolidation would. The event argument is QUOTED: a bare `done`
  # here is ambiguous with the loop keyword (SC1010) and reads as a terminator to a human too.
  for i in 1 2 3 4 5; do row "id$i$(printf '%08d' "$i")" "" "done"; done
  run "$SUT" --threshold 5
  printf '%s' "$output" | grep -q "no cluster at/above 5"
}

@test "--assert exits 1 when a cluster crosses, 0 when none does" {
  seed_sha_cluster 6
  run "$SUT" --assert --threshold 5
  [ "$status" -eq 1 ]
  : > "$CC_BACKLOG_FILE"
  seed_sha_cluster 2
  run "$SUT" --assert --threshold 5
  [ "$status" -eq 0 ]
}

@test "an empty store is a no-op, never a crash" {
  run "$SUT" --assert
  [ "$status" -eq 0 ]
}

@test "an unknown argument is refused rather than silently ignored" {
  run "$SUT" --nonsense
  [ "$status" -eq 2 ]
}

# ── THE ACTUATOR (--fold, READINESS R6) ────────────────────────────────────────────────────────
# The detector above only ever COUNTS. These pin the half that writes, and the first thing they have
# to pin is what it REFUSES: the live store's largest cluster on 2026-08-11 was 14 rows that the
# detector's `<sha>` normalisation had merged out of NINE different stranded worktrees. A fold of
# that cluster joins eight unrelated pieces of work under one condition, and `link` feeds claim
# guard (6), so the join refuses dispatch on them. The refutation control is therefore not optional
# garnish here — it is the assertion the writer exists to satisfy.

fold_setup() {
  CB="$REPO/bin/cc-backlog"
  export CC_BACKLOG_BIN="$CB" CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/kick" CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
}

n_records() { grep -c . "$CC_BACKLOG_FILE"; }
n_open()    { bash "$CB" list --all --json | jq '[.[]|select(.status=="open")]|length'; }

@test "FOLD: a mechanically identical cluster is joined to ONE condition, append-only" {
  fold_setup
  seed_sha_cluster 6
  before_rec="$(n_records)"; before_open="$(n_open)"
  run "$SUT" --fold --apply
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "6 link(s) written"
  printf '%s' "$output" | grep -q "conservation=ok"
  # APPEND-ONLY: exactly six new records, all `link`, and not one row closed or created.
  [ "$(n_records)" -eq $(( before_rec + 6 )) ]
  [ "$(jq -r 'select(.event=="link")|.id' "$CC_BACKLOG_FILE" | wc -l | tr -d ' ')" -eq 6 ]
  [ "$(n_open)" -eq "$before_open" ]
  # ONE condition across the whole group — that is what makes it one effort under the lease.
  [ "$(bash "$CB" list --all --json | jq -r '[.[].condition]|unique|length')" -eq 1 ]
}

@test "FOLD REFUTATION: rows the detector merges but that name DIFFERENT subjects are NOT folded" {
  fold_setup
  # The live shape, verbatim: one sentence, nine worktrees. The detector's key erases the sha and
  # calls this one 9x cluster; the fold key keeps the letters and sees nine subjects.
  for w in 7ff1b6f5ddbb 4ce34a4f703c 70dff02dcf4a 9bc82b51843e 6110fc45141e 5bb6555f22df 28740c313840 5bf8aaaf2f5c 4f657ed3e064; do
    row "id${w:0:12}" "re-land wt-$w (/Users/x/.worktrees/wt-$w): ship-land exited 6 (exit) and its author's pane may be gone"
  done
  run "$SUT" --threshold 5
  printf '%s' "$output" | grep -q "9x"          # the detector DOES see one cluster
  run "$SUT" --fold --apply
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "nothing to fold"
  [ "$(jq -r 'select(.event=="link")|.id' "$CC_BACKLOG_FILE" | wc -l | tr -d ' ')" -eq 0 ]
}

@test "FOLD: a dry run writes NOTHING, and a second apply writes nothing either" {
  fold_setup
  seed_sha_cluster 6
  before_rec="$(n_records)"
  run "$SUT" --fold
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "DRY RUN"
  [ "$(n_records)" -eq "$before_rec" ]
  run "$SUT" --fold --apply
  printf '%s' "$output" | grep -q "6 link(s) written"
  mid="$(n_records)"
  run "$SUT" --fold --apply
  printf '%s' "$output" | grep -q "1 already joined"
  [ "$(n_records)" -eq "$mid" ]
}

@test "FOLD FLOOR: a group naming no file, path or ref is unscoreable and abstains" {
  fold_setup
  # Same sentence, same everything, no identifier anywhere — only a bare number varies. Two
  # different operator steps can look exactly like this, so the key must not act.
  for i in 1 2 3 4 5 6; do row "idfloor$(printf '%06d' "$i")" "restart the pane and wait $i seconds"; done
  run "$SUT" --threshold 5
  printf '%s' "$output" | grep -q "6x"
  run "$SUT" --fold --apply
  printf '%s' "$output" | grep -q "nothing to fold"
  [ "$(jq -r 'select(.event=="link")|.id' "$CC_BACKLOG_FILE" | wc -l | tr -d ' ')" -eq 0 ]
}

@test "ESCALATION: a fully foldable cluster files NOTHING — the pile is not answered by growing it" {
  fold_setup
  seed_sha_cluster 6
  run "$SUT" --file --threshold 5
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "nothing to escalate"
  # the store must hold the six seeded rows and not a seventh asking a human to look at them
  [ "$(bash "$CB" list --all --json | jq 'length')" -eq 6 ]
}

@test "ESCALATION: the cluster the fold key REFUSES is the one that reaches a human" {
  fold_setup
  for w in 7ff1b6f5ddbb 4ce34a4f703c 70dff02dcf4a 9bc82b51843e 6110fc45141e 5bb6555f22df; do
    row "id${w:0:12}" "re-land wt-$w (/Users/x/.worktrees/wt-$w): ship-land exited 6 (exit) and its author's pane may be gone"
  done
  run "$SUT" --file --threshold 5
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "filed/updated"
  [ "$(bash "$CB" list --all --json | jq '[.[]|select(.source=="backlog-consolidation-trigger")]|length')" -eq 1 ]
  bash "$CB" list --all --json | jq -e '.[]|select(.source=="backlog-consolidation-trigger")|.title|test("REFUSED")' >/dev/null
}
