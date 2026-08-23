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

# ── THE CONSERVATION SPAN (2026-08-12, W2) ────────────────────────────────────────────────────────
# Measured on the fold's first real apply against the live store: 46 links written, 0 refused, and
# `conservation=FAILED live 555→555 · open 330→331`. Nothing was wrong with the fold — a sibling
# session unblocked an unrelated row during the ~3 minutes the apply took. The assertion spanned the
# WHOLE STORE while its subject is only the rows the run linked, so any concurrent write anywhere read
# as "the key merged across a distinction", which is the one verdict a caller may never flip past.
#
# The wrapper below is the only way to reach that branch deterministically: a real cc-backlog for
# every verb, plus a sibling write injected at exactly the moment a link lands.
sibling_wrapper() { # $1 = the sibling verb to run after each link
  W="$BATS_TEST_TMPDIR/cb-wrapper"
  cat > "$W" <<WRAP
#!/usr/bin/env bash
real="$CB"
if [ "\$1" = link ]; then
  bash "\$real" "\$@"; rc=\$?
  $1
  exit \$rc
fi
exec bash "\$real" "\$@"
WRAP
  chmod +x "$W"
  export CC_BACKLOG_BIN="$W"
}

@test "SPAN: a SIBLING's write during an apply is 'unknown', never FAILED — and the links still land" {
  fold_setup
  seed_sha_cluster 6
  # The sibling files a brand-new row, which moves both the count and the id set — the exact shape
  # that produced the false FAILED. A link has no status arm, so this cannot be ours.
  sibling_wrapper 'bash "$real" add --project other --title "a sibling filed this mid-apply" --source sib >/dev/null 2>&1'
  run "$SUT" --fold --apply
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "6 link(s) written"
  printf '%s' "$output" | grep -q "conservation=unknown"
  [ "$(printf '%s' "$output" | grep -c 'conservation=FAILED')" -eq 0 ]
  printf '%s' "$output" | grep -q "kept its status"
}

@test "SPAN: a row that LOSES its status across its own link is still FAILED, rc 1" {
  fold_setup
  seed_sha_cluster 6
  # THE CONTROL FOR THE CONTROL. `unknown` above must not be a blanket amnesty: this wrapper harms
  # the very row it just linked, which is the only damage a link could ever do, and it must convict.
  sibling_wrapper 'bash "$real" block "$2" --needs "harmed by the wrapper" >/dev/null 2>&1'
  run "$SUT" --fold --apply
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q "conservation=FAILED"
  printf '%s' "$output" | grep -q "changed status"
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

# ── THE ENGINE GUARD IS FAIL-CLOSED (backlog 2366f99e04a7) ───────────────────────────────────────
# This script is wired into autonomy-sweep.sh:538 as `--file` on a 300 s tick with `>/dev/null 2>&1`,
# so its stderr reaches nobody and the rc is the ONLY thing that leaves the process. `exit 0` on an
# absent jq was therefore indistinguishable, to the only reader there is, from a clean store with no
# cluster — the same shape backlog-grouping-sweep.sh carried for its whole deployed life (963dbd0a2).
#
# THE MUTANT ARM IS WHAT CREDITS THE CHANGE. Every `[ "$status" -eq 2 ]` below would also pass
# against a subject that exited 2 for an unrelated reason, so the pre-fix spelling is restored at the
# one site this change touched and asserted to reach 0 on the SAME fixture. It is a sed over the
# working tree with anchors counted BOTH ways rather than a `git show` of a ref: a branch name
# advances past the fix the moment it lands and would then compare the fix to itself
# (memory: control-must-replay-the-real-artifact, per-site-mutation-attributes-coverage).
#
# VACUITY, ONE LEVEL BELOW THE ASSERTION: the engine guard is reached only after the store guard
# above it passes, so a fixture with no store would exit 0 at the WRONG guard and say nothing about
# this change. setup() writes $CC_BACKLOG_FILE, and store_present() re-asserts it here rather than
# trusting that.

store_present() { [ -f "$CC_BACKLOG_FILE" ]; }

# A PATH with no jq on it. Built by NAMING what the guard path needs rather than by shadowing,
# because absence cannot be spelled as an override.
nojq_path() {
  local d="$BATS_TEST_TMPDIR/nojq" t p
  mkdir -p "$d"
  for t in dirname date mkdir rm head tr cat grep sed; do
    p="$(command -v "$t" 2>/dev/null)"
    [ -n "$p" ] && ln -sf "$p" "$d/$t"
  done
  printf '%s' "$d"
}

# A cc-backlog that records every invocation; the store's own behaviour is not under test here.
eg_stub_backlog() {
  EG_CALLS="$BATS_TEST_TMPDIR/eg.calls"
  EG_STUB="$BATS_TEST_TMPDIR/cc-backlog-stub"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$EG_CALLS" > "$EG_STUB"
  chmod +x "$EG_STUB"
  export CC_BACKLOG_BIN="$EG_STUB"
  export CC_PAGE_DAMP_DIR="$BATS_TEST_TMPDIR/damp"
}
eg_calls() { [ -f "${EG_CALLS:-}" ] && wc -l < "$EG_CALLS" | tr -d ' ' || printf '0'; }

# THE MUTANT: the pre-fix fail-open restored at the one site this change created, anchored both ways
# so a rename of the site reds the anchor instead of silently producing a mutant identical to the
# subject (memory: sibling-guard-makes-the-fixture-vacuous).
eg_mutant() {
  EG_MUT="$BATS_TEST_TMPDIR/mutant-trigger.sh"
  [ "$(grep -c '|| engine_absent ' "$SUT")" -eq 1 ]
  sed 's/|| engine_absent .*/|| { printf "jq missing — fail-open\\n" >\&2; exit 0; }/' "$SUT" > "$EG_MUT"
  [ "$(grep -c '|| engine_absent ' "$EG_MUT")" -eq 0 ]
  chmod +x "$EG_MUT"
}

@test "no jq ⇒ rc 2, not the fail-open 0 the scheduled caller could not tell from a clean store" {
  store_present
  seed_sha_cluster 6
  # `env` rather than a PATH prefix on `run`: the restricted PATH has no bash on it either, so the
  # prefix form exits 127 and every assertion below would be measuring the harness
  # (memory: hermetic-in-stubs-not-in-interpreter).
  run env PATH="$(nojq_path)" /bin/bash "$SUT" --threshold 5
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q 'jq missing'
  printf '%s' "$output" | grep -q 'CANNOT MEASURE'
}

@test "MUTANT: the pre-fix exit reaches 0 on the same fixture — the arm that credits the change" {
  store_present
  seed_sha_cluster 6
  eg_mutant
  run env PATH="$(nojq_path)" /bin/bash "$EG_MUT" --threshold 5
  # Fail-open, exactly as trunk behaved: an absent engine read as a clean store.
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'fail-open'
}

@test "--file with no jq files ONE condition-keyed, self-falsifying row" {
  store_present
  eg_stub_backlog
  run env PATH="$(nojq_path)" /bin/bash "$SUT" --file --threshold 5
  [ "$status" -eq 2 ]
  [ "$(eg_calls)" -eq 1 ]
  grep -q 'backlog-consolidation-engine-absent' "$EG_CALLS"
  grep -q 'command -v jq' "$EG_CALLS"
}

@test "--assert with no jq stays a pure READ: rc 2, and not one write to the ledger" {
  store_present
  eg_stub_backlog
  run env PATH="$(nojq_path)" /bin/bash "$SUT" --assert --threshold 5
  # 2 is in cc-premise's _FALSIFIER_UNASKABLE_RCS, so a consumer reads UNVERIFIED — never "gone".
  [ "$status" -eq 2 ]
  [ "$(eg_calls)" -eq 0 ]
}

@test "POLARITY: engine present is never rc 2 — an alarm that always fires carries no bits" {
  store_present
  seed_sha_cluster 6
  run "$SUT" --threshold 5
  [ "$status" -eq 0 ]
  run "$SUT" --assert --threshold 5
  [ "$status" -eq 1 ]
}
