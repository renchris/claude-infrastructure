#!/usr/bin/env bats
# THE SHARD ARM — `cc-premise sweep --limit N` (backlog d23f3a444984).
#
# THE DEFECT THIS SUITE PINS. The currency pass costs what its PROBES cost and nothing else:
# measured 2026-08-16 at utility, 265.81 s per pass, of which the whole-store fold is 3.30 s and the
# other ~262 s is 141 falsifier probes at ~1.9 s each. That cost had 2.5x'd in four days, so the
# pass's own wall-clock bound had already been re-sized twice and 4 of its 5 production runs ever
# had died rc 124 against it. A job whose fixed cost is 1% of its variable cost is shardable, and a
# bound that must be re-measured weekly is a bound that will rot the week nobody looks.
#
# WHY THE ARM WAS FILED RATHER THAN BUILT THE DAY IT WAS WANTED, and it is the load-bearing case
# below. `unprobed` — the sweep's count of rows no arm can speak for — is the coverage ratchet's own
# work queue, asserted against a high-water mark. A shard that folded its deferred rows into it
# would file a coverage-regression row on EVERY sharded pass, out of an alarm whose subject
# (capability) had not moved at all. A half-built shard is worse than no shard
# (memory: span-must-equal-subject, alarm-polarity-and-attention-budget). The same trap has a second
# mouth on the way out: `validated --batch` is a SNAPSHOT, so recording a shard under snapshot
# semantics erases every other shard's stamp and snaps `never_validated` back to the whole store
# once per pass. Both are asserted here, in both directions.
#
# WHAT IS ASSERTED, and each is a BEHAVIOUR the caller can see:
#   · the shard BINDS — fewer probes actually execute than there are capable rows
#   · a deferred row is counted as `deferred` and NOT as `unprobed`, and the control proves the two
#     counts are distinguishable (a suite asserting only the first passes on `deferred = unprobed`)
#   · the cursor ADVANCES, so successive passes reach different rows and a CYCLE covers every one
#   · a completed cycle starts the next one instead of reporting nothing left to do
#   · the cursor survives store churn, which is what makes a set-keyed cursor and not an index
#   · `--record` under a shard MERGES, so never-validated falls monotonically across a cycle
#   · the REPORT stays whole-store: the verdict buckets do not shrink with the shard
#   · argument discipline: bare `--limit` and `--limit 0` are rc 2, never a silent whole-store pass

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  CP="$REPO/bin/cc-premise"
  # OWN $HOME first: the stamp file AND the shard cursor both default under it, and a suite that
  # writes the operator's live ~/.claude/autonomy corrupts the census it is testing.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_VALIDATED="$BATS_TEST_TMPDIR/validated.json"
  export CC_PREMISE_CURSOR="$BATS_TEST_TMPDIR/cursor.json"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  printf '#!/bin/bash\necho "[]"\n' > "$BATS_TEST_TMPDIR/nosess"; chmod +x "$BATS_TEST_TMPDIR/nosess"
  export CC_BACKLOG_SESSIONS_BIN="$BATS_TEST_TMPDIR/nosess"
  # CC_PREMISE_REPO pinned EXPLICITLY EMPTY, not unset: unset now defaults to cc-premise's own
  # checkout, and the git arms reading a real repo would make these verdicts depend on whoever
  # landed last. This suite's subject is the shard, not the git arms.
  export CC_PREMISE_REPO=
  : > "$CC_BACKLOG_FILE"
}

# probe_row <title> <probe> → id of a row carrying a STORED falsifier (i.e. probe-CAPABLE).
probe_row() {
  "$CB" add --title "$1" --project probe --source test --falsifier "$2"
}

# probed_ids → the ids this pass actually ran a probe against, one per line.
#
# READ FROM THE STAMP FILE, not from the sweep's own counts, and that is deliberate. The counts are
# what the subject SAYS it did; the stamp is the store's independent record of what it did. A cursor
# bug that advanced without probing would satisfy every count in the report and be caught only here
# (memory: claimed-outcome-vs-checked-outcome).
probed_ids() {
  jq -r '.rows | keys[]' "$CC_BACKLOG_VALIDATED" 2>/dev/null | sort
}

# ── THE SHARD BINDS ──────────────────────────────────────────────────────────────────────────────

@test "1 --limit N probes at most N capable rows and DEFERS the rest" {
  probe_row "one"   "exit 1" >/dev/null
  probe_row "two"   "exit 1" >/dev/null
  probe_row "three" "exit 1" >/dev/null
  run python3 "$CP" sweep --limit 2 --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.probe_capable')" = "3" ]
  [ "$(printf '%s' "$output" | jq -r '.assessed')"      = "2" ]
  [ "$(printf '%s' "$output" | jq -r '.deferred')"      = "1" ]
}

@test "2 a limit at or above the population probes everything and defers nothing" {
  # The control for case 1. Without it, case 1 would pass over an arm that deferred unconditionally.
  probe_row "one" "exit 1" >/dev/null
  probe_row "two" "exit 1" >/dev/null
  run python3 "$CP" sweep --limit 9 --json
  [ "$(printf '%s' "$output" | jq -r '.assessed')" = "2" ]
  [ "$(printf '%s' "$output" | jq -r '.deferred')" = "0" ]
}

@test "3 NO --limit is the whole store, and reports the shard fields inert" {
  # The second control: the default path must be unchanged by the arm's existence.
  probe_row "one" "exit 1" >/dev/null
  probe_row "two" "exit 1" >/dev/null
  run python3 "$CP" sweep --json
  [ "$(printf '%s' "$output" | jq -r '.assessed')"    = "2" ]
  [ "$(printf '%s' "$output" | jq -r '.deferred')"    = "0" ]
  [ "$(printf '%s' "$output" | jq -r '.limit')"       = "0" ]
  [ "$(printf '%s' "$output" | jq -r '.shard_cycle')" = "0" ]
}

# ── THE LOAD-BEARING SEPARATION ──────────────────────────────────────────────────────────────────

@test "4 A DEFERRED ROW IS NOT AN UNPROBED ONE — the reason this arm was filed, not built" {
  # 🚨 `unprobed` is the coverage ratchet's input and is asserted against a high-water mark. If a
  # deferred row folded into it, every sharded pass would report a coverage regression the store had
  # not suffered, and the ratchet's consumer would file a condition-keyed row for it — once per pass,
  # forever, about nothing.
  #
  # BOTH POPULATIONS ARE PRESENT ON PURPOSE. Two rows carry a probe (capable, one of them deferred)
  # and two carry none (genuinely unprobed). A suite fixturing only the capable rows could not tell
  # `deferred` from `unprobed` at all: both counts would read the same number and an implementation
  # that aliased them would pass (memory: control-must-replay-the-real-artifact).
  probe_row "capable one" "exit 1" >/dev/null
  probe_row "capable two" "exit 1" >/dev/null
  "$CB" add --title "no probe at all" --project probe --source test >/dev/null
  "$CB" add --title "also no probe"   --project probe --source test >/dev/null
  run python3 "$CP" sweep --limit 1 --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.non_done')" = "4" ]
  [ "$(printf '%s' "$output" | jq -r '.assessed')" = "1" ]   # the shard
  [ "$(printf '%s' "$output" | jq -r '.deferred')" = "1" ]   # the capable row held back
  [ "$(printf '%s' "$output" | jq -r '.unprobed')" = "2" ]   # ← the two with NO arm, and ONLY those
}

@test "5 the SAME store unsharded reports the same unprobed count — the shard moves only deferred" {
  # The direct control for case 4: `unprobed` must be a property of the STORE, not of the pass's
  # limit. If the two numbers differed, the ratchet's input would depend on a scheduling choice.
  probe_row "capable one" "exit 1" >/dev/null
  probe_row "capable two" "exit 1" >/dev/null
  "$CB" add --title "no probe at all" --project probe --source test >/dev/null
  "$CB" add --title "also no probe"   --project probe --source test >/dev/null
  run python3 "$CP" sweep --json
  [ "$(printf '%s' "$output" | jq -r '.unprobed')" = "2" ]
  [ "$(printf '%s' "$output" | jq -r '.deferred')" = "0" ]
}

# ── THE CURSOR ───────────────────────────────────────────────────────────────────────────────────

@test "6 successive passes reach DIFFERENT rows, and a full cycle reaches every one" {
  # Without a cursor the shard would re-ask the same first N rows forever and the rows behind them
  # would never be probed at all — a currency pass with a permanent blind spot, which is a strictly
  # worse failure than the cost it was built to bound.
  local a b c
  a="$(probe_row "one"   "exit 1")"
  b="$(probe_row "two"   "exit 1")"
  c="$(probe_row "three" "exit 1")"
  python3 "$CP" sweep --limit 1 --record --json >/dev/null
  local first; first="$(probed_ids)"
  [ "$(printf '%s\n' "$first" | wc -l | tr -d ' ')" = "1" ]

  python3 "$CP" sweep --limit 1 --record --json >/dev/null
  local second; second="$(probed_ids)"
  [ "$(printf '%s\n' "$second" | wc -l | tr -d ' ')" = "2" ]

  python3 "$CP" sweep --limit 1 --record --json >/dev/null
  # THE CYCLE'S GUARANTEE: three passes of one over three capable rows reach all three, exactly once
  # each. Asserted as the SET, so an implementation that re-asked one row and skipped another cannot
  # pass on the count alone.
  [ "$(probed_ids | tr '\n' ' ')" = "$(printf '%s\n%s\n%s\n' "$a" "$b" "$c" | sort | tr '\n' ' ')" ]
}

@test "7 a COMPLETED cycle starts the next one rather than reporting nothing to do" {
  # Currency decays continuously, so "every row has been asked once" is the signal to begin again.
  # An arm that went quiet at the end of a cycle would stop measuring and look healthy doing it.
  probe_row "one" "exit 1" >/dev/null
  probe_row "two" "exit 1" >/dev/null
  run python3 "$CP" sweep --limit 2 --json
  [ "$(printf '%s' "$output" | jq -r '.shard_cycle')"   = "1" ]
  [ "$(printf '%s' "$output" | jq -r '.shard_pending')" = "0" ]
  run python3 "$CP" sweep --limit 2 --json
  [ "$(printf '%s' "$output" | jq -r '.shard_cycle')" = "2" ]
  [ "$(printf '%s' "$output" | jq -r '.assessed')"    = "2" ]
}

@test "8 the cursor is keyed on IDS, so store churn cannot make it skip a row" {
  # 🚨 WHY THIS IS A SET AND NOT AN INDEX, asserted as the exact row an offset cursor would skip.
  # This store gains and closes rows continuously — the sweep's own `--close-falsified` closes some —
  # so an integer offset points into a list that MOVED under it. Close the row at position 1 and
  # every later row shifts left by one; an offset of 1 then lands on what is now position 2 and the
  # row that slid into position 1 is skipped SILENTLY, with nothing downstream able to tell
  # "deferred to the next pass" from "deferred forever".
  #
  # THE POSITIONS ARE READ FROM THE FOLD, never assumed from insertion order — `cc-backlog list`
  # sorts, so a test hardcoding "the first row I added" would be asserting against an ordering it
  # does not control (memory: control-calibrated-to-implementation-decays).
  probe_row "one"   "exit 1" >/dev/null
  probe_row "two"   "exit 1" >/dev/null
  probe_row "three" "exit 1" >/dev/null
  probe_row "four"  "exit 1" >/dev/null
  local o1; o1="$("$CB" list --all --json | jq -r '[.[] | select(.status != "done")][0].id')"
  python3 "$CP" sweep --limit 1 --record --json >/dev/null
  [ "$(probed_ids)" = "$o1" ]

  # `done` QUOTED: unquoted, shellcheck parses the verb as the loop keyword and reds SC1010 on the
  # land gate's .bats arm. Quoting changes nothing at runtime and is the fix that message names.
  "$CB" 'done' "$o1" --evidence "closed between passes" >/dev/null 2>&1
  # The row that has just SLID INTO the vacated position. A set-keyed cursor asks it next because it
  # has not been asked; an offset cursor steps past it to the row behind it.
  local slid; slid="$("$CB" list --all --json | jq -r '[.[] | select(.status != "done")][0].id')"
  python3 "$CP" sweep --limit 1 --record --json >/dev/null
  [ "$(probed_ids | grep -c "^${slid}$")" = "1" ]

  # …and the cycle covers the three SURVIVORS without restarting: three passes after the close, all
  # three are stamped, `shard_pending` has reached 0 and the cycle counter has not moved.
  python3 "$CP" sweep --limit 1 --record --json >/dev/null
  run python3 "$CP" sweep --limit 1 --record --json
  [ "$(printf '%s' "$output" | jq -r '.shard_cycle')" = "1" ]
  [ "$(printf '%s' "$output" | jq -r '.shard_pending')" = "0" ]
  # The closed row's stamp has also left the file — a merge carries LIVE rows only, so the stamp
  # cannot grow forever with entries nothing will ever consult.
  [ "$(probed_ids | wc -l | tr -d ' ')" = "3" ]
  [ "$(probed_ids | grep -c "^${o1}$")" = "0" ]
}

@test "9 an UNREADABLE cursor restarts the cycle rather than inventing a seen set" {
  # Fail-open in the direction that costs wall-clock, never in the one that skips rows: a fabricated
  # `seen` set would silently starve rows forever, and this file's whole law is that a sensor failure
  # may never look like an answer.
  probe_row "one" "exit 1" >/dev/null
  printf 'not json at all\n' > "$CC_PREMISE_CURSOR"
  run python3 "$CP" sweep --limit 1 --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.assessed')" = "1" ]
  [ "$(printf '%s' "$output" | jq -r '.cursor_note')" = "ok" ]
}

# ── THE STAMP, THE SECOND MOUTH OF THE SAME TRAP ─────────────────────────────────────────────────

@test "10 a sharded --record MERGES, so never-validated falls monotonically across a cycle" {
  # 🚨 `validated --batch` is a SNAPSHOT — written whole or not at all — which is exactly right when
  # the batch IS the population. Handing it a shard under those semantics erases every other shard's
  # stamp, so `never_validated` would snap back to the whole store once per pass: the same
  # false-staleness reading the snapshot rule exists to prevent, reached from the other side.
  probe_row "one"   "exit 1" >/dev/null
  probe_row "two"   "exit 1" >/dev/null
  probe_row "three" "exit 1" >/dev/null
  run "$CB" freshness --never
  [ "$output" = "3" ]
  python3 "$CP" sweep --limit 1 --record --json >/dev/null
  run "$CB" freshness --never
  [ "$output" = "2" ]
  python3 "$CP" sweep --limit 1 --record --json >/dev/null
  run "$CB" freshness --never
  [ "$output" = "1" ]                       # ← 3 again under snapshot semantics
  python3 "$CP" sweep --limit 1 --record --json >/dev/null
  run "$CB" freshness --never
  [ "$output" = "0" ]
}

@test "11 an UNSHARDED --record still REPLACES — a whole pass is still a snapshot" {
  # The control for case 10. Merge must be the shard's semantics, not the writer's new default:
  # a whole-store pass that stopped replacing would carry a retired row's stamp forever.
  local a b
  a="$(probe_row "one" "exit 1")"
  b="$(probe_row "two" "exit 1")"
  python3 "$CP" sweep --record --json >/dev/null
  [ "$(probed_ids | wc -l | tr -d ' ')" = "2" ]
  # Retire one row's PROBE. It is still live and still non-done, but no arm speaks for it now, so a
  # replacing writer must drop its stamp and a merging one would keep it.
  "$CB" falsify "$a" --clear >/dev/null 2>&1
  python3 "$CP" sweep --record --json >/dev/null
  [ "$(probed_ids | tr '\n' ' ')" = "$b " ]
}

@test "12 --merge on the SINGLE-row form is rc 2, never silently adjacent behaviour" {
  local a; a="$(probe_row "one" "exit 1")"
  run "$CB" validated "$a" --verdict clear --merge
  [ "$status" -eq 2 ]
}

@test "13 a merge over an UNREADABLE stamp file refuses — it must not discard the standing pass" {
  # Falling back to an empty prior would let one corrupt read throw away every other shard's
  # measurement while reporting success, which is the catastrophe the empty-batch refusal guards
  # against with a different cause.
  local a; a="$(probe_row "one" "exit 1")"
  printf 'garbage\n' > "$CC_BACKLOG_VALIDATED"
  # `run` must not sit inside a pipeline — the pipe forks it and `$status` never reaches this shell,
  # so the assertion below would read an empty string and pass on any rc at all.
  printf '{"id":"%s","verdict":"clear"}\n' "$a" > "$BATS_TEST_TMPDIR/batch.jsonl"
  run bash -c "'$CB' validated --batch --merge --sha deadbeef < '$BATS_TEST_TMPDIR/batch.jsonl'"
  [ "$status" -eq 2 ]
  [ "$(cat "$CC_BACKLOG_VALIDATED")" = "garbage" ]
}

# ── THE REPORT DOES NOT SHRINK WITH THE SHARD ────────────────────────────────────────────────────

@test "14 the verdict buckets stay WHOLE-STORE on a sharded pass" {
  # Only the MEASUREMENT is sharded. The prose arms cost ~3 s of a 265 s pass, so deferring them
  # would buy nothing and would make "0 self-duplicate rows" mean two different things on alternating
  # passes — a report a reader cannot difference against yesterday's.
  local canon; canon="$(probe_row "the canonical one" "exit 1")"
  "$CB" add --project probe --source test \
    --title "DUPLICATE of ${canon} — this row is redundant" >/dev/null
  probe_row "filler one" "exit 1" >/dev/null
  probe_row "filler two" "exit 1" >/dev/null
  run python3 "$CP" sweep --limit 1 --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.non_done')" = "4" ]
  [ "$(printf '%s' "$output" | jq -r '.assessed')" = "1" ]
  # The self-duplicate is found even though its own row was never probed this pass.
  [ "$(printf '%s' "$output" | jq -r '.self_duplicate | length')" = "1" ]
}

@test "15 a DEFERRED row's probe genuinely did not run — the shard is real, not cosmetic" {
  # 🚨 THE COST TEST. If `--limit` only relabelled rows while still executing every probe, every
  # count above would still pass and the pass would cost exactly what it cost before — the arm would
  # be decorative and the bound would go on rotting. The probe here has a SIDE EFFECT, so the
  # filesystem answers the question the report cannot (memory: claimed-outcome-vs-checked-outcome).
  probe_row "touches a file" "touch '$BATS_TEST_TMPDIR/ran-a'; exit 1" >/dev/null
  probe_row "touches another" "touch '$BATS_TEST_TMPDIR/ran-b'; exit 1" >/dev/null
  python3 "$CP" sweep --limit 1 --json >/dev/null
  local n=0
  [ -f "$BATS_TEST_TMPDIR/ran-a" ] && n=$((n + 1))
  [ -f "$BATS_TEST_TMPDIR/ran-b" ] && n=$((n + 1))
  [ "$n" -eq 1 ]
}

# ── ARGUMENT DISCIPLINE ──────────────────────────────────────────────────────────────────────────

@test "16 a bare --limit and --limit 0 are rc 2 — a limit must never fail OPEN into a whole pass" {
  # `--limit 0` is the internal no-limit sentinel, so accepting it from a caller would turn the
  # cheapest possible request into the most expensive one. A flag whose typo'd form is the dear one
  # is the same trap `--close-falsified` was given a mandatory cap to avoid.
  probe_row "one" "exit 1" >/dev/null
  run python3 "$CP" sweep --limit
  [ "$status" -eq 2 ]
  run python3 "$CP" sweep --limit 0
  [ "$status" -eq 2 ]
  run python3 "$CP" sweep --limit notanumber
  [ "$status" -eq 2 ]
}

@test "17 the human render NAMES the shard — a silent one reads as a falling falsified count" {
  probe_row "one"   "exit 1" >/dev/null
  probe_row "two"   "exit 1" >/dev/null
  probe_row "three" "exit 1" >/dev/null
  run python3 "$CP" sweep --limit 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"shard"* ]] || false
  [[ "$output" == *"deferred"* ]] || false
}
