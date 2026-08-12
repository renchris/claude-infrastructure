#!/usr/bin/env bats
# cc-backlog `dups --mode title|family` + `backfill` — the dodRef-LESS duplicate population
# (backlog 7ff1b6f5ddbb).
#
# THE DEFECT (measured 2026-08-11 over the live ledger). `dups` grouped on project+dodRef, and 206
# of 269 live rows carry no dodRef — so the reporter was structurally blind to 77% of live work.
# The family it was filed about is `memory-index-over-budget`: 8 rows joined by ONE hand-driven
# sweep on 2026-08-08T04:14, which still left two live orphans (cf6eb3e47b12, 152e9cacc8aa) that
# nothing has joined since. And `link` has SEVEN records in the ledger's whole history, six of them
# from that sweep — nothing backfills, so a row filed before its family had a condition stays
# outside the lease forever.
#
# THE CONTROL THAT MAKES THIS SUITE NON-VACUOUS is the first test: over a dodRef-less fixture,
# `--mode dodref` must find NOTHING. Without it, a `title`/`family` key that merely re-found what
# the old key already saw would pass every positive test below.
#
# TWO POPULATIONS, and only one of them is alive today:
#   · `family` — an un-conditioned row matching an EXISTING condition group. Fires on the live
#     store (2 hits in 182 orphans, both true).
#   · `title` — identical titles once digit-bearing tokens are dropped. Reports ZERO groups live,
#     because its population (the post-land scanner's `… @ <sha>` rows, 57 open on 2026-08-09) aged
#     out to 5 unrelated rows two days later. A key whose ability to fire cannot be demonstrated is
#     indistinguishable from one that cannot fire at all, so it is pinned HERE on a fixture
#     replaying that incident's shape, sha for sha (memory: scan-revision-predates-the-fix,
#     sensor-default-off-makes-blindness-the-shipping-path).
#
# THE FLOORS ARE PINNED IN BOTH DIRECTIONS. `shared >= 3` exists because three live rows scored a
# perfect frac=1.0 on ONE shared identifier each; `frac >= 0.40` exists because a row can share
# three identifiers and still be mostly about something else. A suite that only proved matches
# would pass with either floor deleted (memory: guard-proxy-fails-in-both-directions).
#
# HERMETIC. $HOME, the store and the kick marker are all inside $BATS_TEST_TMPDIR; the claimer shape
# is `$(hostname -s)-<pid>`, which takes claimer_live's `kill -0` branch and never consults the
# cc-sessions registry (memory: unfixtured-sensor-executes-the-deployed-subject).

setup() {
  # Project labels in this suite are FIXTURES, not projects — and `cc-backlog add` now WARNS on an
  # explicit --project outside the dispatch set (df2b6a40a5dc), which bats folds into $output. Off
  # here because dispatchability is not this suite's subject; tests/cc-backlog-project-dispatch.bats
  # owns it, unfixtured, in both directions.
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/Development/.worktrees"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  export CC_BACKLOG_WT_ROOT="$HOME/Development/.worktrees"
  HOST="$(hostname -s 2>/dev/null || hostname)"

  # The `memory-index-over-budget` family, shaped after the live rows. The ANCHOR carries the
  # condition; ORPHAN is the un-joined sibling in a different wording — the whole case.
  ANCHOR_T="MEMORY.md index over its loader budget — run compact-memory, the safe-auto arm and the propose-only dedupe"
  ORPHAN_T="MEMORY.md index is over the read limit again at 22.5KB — compact-memory should run its safe-auto pass"
  # Shares ONE identifier (compact-memory) at frac=1.0: the small-denominator trap, measured live.
  THIN_T="the compact-memory hook fires on every edit and asks for a pass"
  # Shares THREE identifiers but is mostly about something else: the dilution case.
  DILUTE_T="compact-memory safe-auto MEMORY.md also scripts/postland-verify.sh bin/cc-dispatch scripts/worktree-pool.sh scripts/land-lock.sh scripts/ship-land.sh scripts/deploy-live.sh"
  # Shares nothing.
  OTHER_T="scripts/postland-verify.sh bisects FAILING only and stamps that culprit onto every entry"
}

teardown() {
  [ -f "$BATS_TEST_TMPDIR/live.pid" ] && kill "$(cat "$BATS_TEST_TMPDIR/live.pid")" 2>/dev/null || true
  return 0
}

live_claimer() {
  sleep 60 >/dev/null 2>&1 &
  echo $! > "$BATS_TEST_TMPDIR/live.pid"
  echo "$HOST-$(cat "$BATS_TEST_TMPDIR/live.pid")"
}

# The post-land scanner's shape: one condition, one row per scan, the sha in the TITLE. Every sha
# here carries a digit — a pure-[a-f] sha would survive the normaliser, which the header documents.
add_scan_rows() {
  S1="$(bash "$CB" add --project P --title "relogin-probes-row-key.bats rule-1 leak survives the gate @ ea188b7fe304" --source scan)"
  S2="$(bash "$CB" add --project P --title "relogin-probes-row-key.bats rule-1 leak survives the gate @ bbe7ebbb04eb" --source scan)"
  S3="$(bash "$CB" add --project P --title "relogin-probes-row-key.bats rule-1 leak survives the gate @ 6e406c7bb10d" --source scan)"
}

add_family() {
  ANCHOR="$(bash "$CB" add --project P --title "$ANCHOR_T" --condition memory-index-over-budget)"
  ORPHAN="$(bash "$CB" add --project P --title "$ORPHAN_T" --source sess-B)"
}

# ── THE CONTROL: the old key is blind to this whole population ─────────────────────────────────

@test "CONTROL — over dodRef-less rows the dodref key finds NOTHING (the defect being fixed)" {
  add_scan_rows
  add_family
  run bash "$CB" dups --mode dodref --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '.dodref | length')" -eq 0 ]
  # …while the two new keys both see it. If this half ever passes with the control above failing,
  # the new keys are just re-finding dodRef groups.
  run bash "$CB" dups --mode title --json
  [ "$(echo "$output" | jq '.title | length')" -eq 1 ]
  run bash "$CB" dups --mode family --json
  [ "$(echo "$output" | jq '.family | length')" -eq 1 ]
}

@test "dodref key still groups what it always did (regression pin)" {
  bash "$CB" add --project P --dod-ref docs/plans/X.md --title "phase one of X" --source a >/dev/null
  bash "$CB" add --project P --dod-ref docs/plans/X.md --title "phase two of X" --source b >/dev/null
  run bash "$CB" dups --mode dodref --json
  [ "$(echo "$output" | jq '.dodref | length')" -eq 1 ]
  [ "$(echo "$output" | jq '.dodref[0].items | length')" -eq 2 ]
}

# ── KEY 2: normalised-title identity ───────────────────────────────────────────────────────────

@test "title key collapses three rows that differ ONLY by a trailing @ sha" {
  add_scan_rows
  [ "$S1" != "$S2" ]; [ "$S2" != "$S3" ]      # three distinct ids: the mint-side defect
  run bash "$CB" dups --mode title --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '.title | length')" -eq 1 ]
  [ "$(echo "$output" | jq '.title[0].items | length')" -eq 3 ]
}

@test "title key does NOT group rows whose titles genuinely differ (negative control)" {
  bash "$CB" add --project P --title "the land gate memoises its statics @ ea188b7fe304" --source scan >/dev/null
  bash "$CB" add --project P --title "worker-claim-gate goes blind inside a worktree @ bbe7ebbb04eb" --source scan >/dev/null
  run bash "$CB" dups --mode title --json
  [ "$(echo "$output" | jq '.title | length')" -eq 0 ]
}

@test "title key drops a group whose rows ALREADY share one condition (answered, not news)" {
  add_scan_rows
  bash "$CB" link "$S1" --condition postland-scan-duplicate-minting >/dev/null
  bash "$CB" link "$S2" --condition postland-scan-duplicate-minting >/dev/null
  bash "$CB" link "$S3" --condition postland-scan-duplicate-minting >/dev/null
  run bash "$CB" dups --mode title --json
  [ "$(echo "$output" | jq '.title | length')" -eq 0 ]
}

@test "title key ignores DONE rows — a terminal family is not a standing alarm" {
  add_scan_rows
  # "done" QUOTED: it is cc-backlog's verb, but bare it parses as the shell keyword (SC1010) — the
  # shipped dispatch table quotes it for the same reason (`cmd_transition "done"`).
  bash "$CB" "done" "$S1" --evidence abc123 >/dev/null
  bash "$CB" "done" "$S2" --evidence abc123 >/dev/null
  run bash "$CB" dups --mode title --json
  [ "$(echo "$output" | jq '.title | length')" -eq 0 ]
}

# ── KEY 3: the condition family ────────────────────────────────────────────────────────────────

@test "family key matches an un-conditioned row to an EXISTING condition group" {
  add_family
  run bash "$CB" dups --mode family --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.family[0].id')" = "$ORPHAN" ]
  [ "$(echo "$output" | jq -r '.family[0].cands[0].cond')" = "memory-index-over-budget" ]
}

@test "FLOOR — one shared identifier at frac=1.0 is NOT a match (the small-denominator trap)" {
  add_family
  THIN="$(bash "$CB" add --project P --title "$THIN_T" --source sess-C)"
  run bash "$CB" dups --mode family --json
  [ "$(echo "$output" | jq --arg i "$THIN" '[.family[] | select(.id == $i)] | length')" -eq 0 ]
  # …and the floor is what excluded it: drop the floor and the same row IS reported. Without this
  # half the test would also pass if the row were excluded for some unrelated reason.
  run bash "$CB" dups --mode family --min-shared 1 --json
  [ "$(echo "$output" | jq --arg i "$THIN" '[.family[] | select(.id == $i)] | length')" -eq 1 ]
}

@test "FLOOR — three shared identifiers diluted by six unshared ones is NOT a match" {
  add_family
  DIL="$(bash "$CB" add --project P --title "$DILUTE_T" --source sess-D)"
  run bash "$CB" dups --mode family --json
  [ "$(echo "$output" | jq --arg i "$DIL" '[.family[] | select(.id == $i)] | length')" -eq 0 ]
  run bash "$CB" dups --mode family --min-frac 0.05 --json
  [ "$(echo "$output" | jq --arg i "$DIL" '[.family[] | select(.id == $i)] | length')" -eq 1 ]
}

@test "family key ignores a row that shares nothing with any group" {
  add_family
  OTH="$(bash "$CB" add --project P --title "$OTHER_T" --source sess-E)"
  run bash "$CB" dups --mode family --json
  [ "$(echo "$output" | jq --arg i "$OTH" '[.family[] | select(.id == $i)] | length')" -eq 0 ]
}

@test "family key ignores a row that ALREADY carries a condition" {
  add_family
  bash "$CB" link "$ORPHAN" --condition memory-index-over-budget >/dev/null
  run bash "$CB" dups --mode family --json
  [ "$(echo "$output" | jq '.family | length')" -eq 0 ]
}

@test "family key labels from EVERY status — a fully-done group still catches a recurrence" {
  add_family
  bash "$CB" "done" "$ANCHOR" --evidence deadbeef >/dev/null   # quoted: bare `done` is SC1010
  run bash "$CB" dups --mode family --json
  [ "$(echo "$output" | jq -r '.family[0].id')" = "$ORPHAN" ]
}

# ── backfill ───────────────────────────────────────────────────────────────────────────────────

@test "backfill DRY RUN writes nothing at all" {
  add_family
  cp "$CC_BACKLOG_FILE" "$BATS_TEST_TMPDIR/before.jsonl"
  run bash "$CB" backfill
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF -- "DRY RUN"
  printf '%s' "$output" | grep -qF -- "link $ORPHAN --condition memory-index-over-budget"
  diff -q "$BATS_TEST_TMPDIR/before.jsonl" "$CC_BACKLOG_FILE"
}

@test "backfill --apply joins the orphan to its condition" {
  add_family
  run bash "$CB" backfill --apply
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF -- "verdict=linked"
  run bash "$CB" list --all --json
  [ "$(echo "$output" | jq -r --arg i "$ORPHAN" '.[] | select(.id == $i) | .condition')" = "memory-index-over-budget" ]
}

@test "backfill --apply is idempotent — a second pass appends no record" {
  add_family
  bash "$CB" backfill --apply >/dev/null
  cp "$CC_BACKLOG_FILE" "$BATS_TEST_TMPDIR/after1.jsonl"
  run bash "$CB" backfill --apply
  [ "$status" -eq 0 ]
  diff -q "$BATS_TEST_TMPDIR/after1.jsonl" "$CC_BACKLOG_FILE"
}

@test "backfill NEVER re-keys a row already on another condition (no --force, ever)" {
  add_family
  bash "$CB" link "$ORPHAN" --condition some-other-standing-state >/dev/null
  run bash "$CB" backfill --apply
  [ "$status" -eq 0 ]
  run bash "$CB" list --all --json
  [ "$(echo "$output" | jq -r --arg i "$ORPHAN" '.[] | select(.id == $i) | .condition')" = "some-other-standing-state" ]
}

@test "backfill ABSTAINS on a row matching two groups, and says so" {
  add_family
  # A second group over the SAME identifiers: the orphan now matches both, so neither is safe.
  bash "$CB" add --project P --title "$ANCHOR_T" --condition memory-index-rotation-policy >/dev/null
  run bash "$CB" backfill --apply
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF -- "ambiguous"
  run bash "$CB" list --all --json
  [ "$(echo "$output" | jq -r --arg i "$ORPHAN" '.[] | select(.id == $i) | .condition // ""')" = "" ]
}

@test "backfill scopes to --project" {
  add_family
  run bash "$CB" backfill --project OTHERPROJ
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF -- "nothing to join"
}

# ── The point of all of it: the join must reach the LEASE ──────────────────────────────────────

@test "END-TO-END — after backfill --apply the condition lease refuses the second worker" {
  add_family
  # Before the join, both rows claim: the 2026-08-07 defect, still reproducible.
  run bash "$CB" claim "$ANCHOR" --by "$(live_claimer)"
  [ "$status" -eq 0 ]
  run bash "$CB" claim "$ORPHAN" --by "$HOST-$$"
  [ "$status" -eq 0 ]
  # Reset and re-run WITH the backfill in between.
  bash "$CB" reopen "$ANCHOR" --force >/dev/null
  bash "$CB" reopen "$ORPHAN" --force >/dev/null
  bash "$CB" backfill --apply >/dev/null
  run bash "$CB" claim "$ANCHOR" --by "$(live_claimer)"
  [ "$status" -eq 0 ]
  run bash "$CB" claim "$ORPHAN" --by "$HOST-$$"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qF -- "sibling-held"
}

# ── Argument handling ──────────────────────────────────────────────────────────────────────────

@test "dups rejects an unknown --mode rather than silently reporting one key" {
  run bash "$CB" dups --mode dodrefs
  [ "$status" -eq 2 ]
  # The refusal must ENUMERATE the live modes — a stale list here is how a caller learns a key
  # exists. `mechanical` (READINESS R6) joined them on 2026-08-11.
  printf '%s' "$output" | grep -qF -- "dodref|title|family|mechanical|all"
}

@test "dups --json emits EVERY key on every mode, so a consumer never guesses" {
  add_family
  run bash "$CB" dups --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'has("dodref") and has("title") and has("family") and has("mechanical")')" = "true" ]
  # --mode <one key> must still emit the whole shape, empty arrays and all: a consumer that has to
  # infer which key produced a bare array is the defect this shape replaced.
  run bash "$CB" dups --mode mechanical --json
  [ "$(echo "$output" | jq 'has("dodref") and has("title") and has("family") and has("mechanical")')" = "true" ]
}

@test "default mode is all — the family shows without asking for it" {
  add_family
  run bash "$CB" dups
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF -- "memory-index-over-budget"
}
