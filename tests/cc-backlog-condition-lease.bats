#!/usr/bin/env bats
# cc-backlog `link` + the SIBLING-CONDITION LEASE — one condition, one worker (backlog 0bded74c6fa2).
#
# The defect (measured 2026-08-07). The event key is project+title+source, so two SESSIONS filing one
# piece of work in two wordings mint two ids: 97f16b6709fa (08:47:44Z) and 6078392359ac (08:47:54Z),
# same project, same dodRef, ten seconds apart, NEITHER carrying a condition. Both were claimed, both
# dispatched, and two worktrees built the same mechanism to completion.
#
# `add --condition` cannot reach this: it derives the id FROM the condition, so two rows sharing one
# can never exist (0 such groups in 1257 live add events) — a lease keyed on `.condition` alone
# governs an empty population. `link` joins rows that ALREADY exist, which is what gives the lease
# something to govern; the lease then refuses to put a second worker on work a sibling row holds.
#
# TWO CONTROLS, and neither is incidental:
#   · THE DEFECT REPRODUCED — the same two rows UNLINKED must still both claim. Without it, a lease
#     that refused everything (or a `link` that silently no-op'd) passes this file green.
#   · THE LEASE MUST RELEASE — a linked sibling whose claimer is provably dead and whose worktree is
#     absent must NOT hold the lease. Without it, a lease that never releases passes every positive
#     test above while stranding both rows forever (memory: abstain-rule-can-retire-the-common-case).
#
# CLAIMER SHAPE IS LOad-BEARING AND HERMETIC. Every claimer here is `$(hostname -s)-<pid>`, which is
# exactly what cc-dispatch writes. That shape takes claimer_live's `kill -0` branch and never
# consults the cc-sessions registry, so this suite reads no state outside its own $HOME
# (memory: unfixtured-sensor-executes-the-deployed-subject).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  DISPATCH="$REPO/bin/cc-dispatch"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/Development/.worktrees"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  # The worktree-occupancy oracle's root. Present-but-empty is the REAL box's shape for an item with
  # no worktree: absent root answers rc 2 (UNRESOLVED) and would make every lease refuse, which would
  # hide a stuck lease behind a passing suite.
  export CC_BACKLOG_WT_ROOT="$HOME/Development/.worktrees"
  HOST="$(hostname -s 2>/dev/null || hostname)"
  # Two wordings of one piece of work, shaped after the live incident.
  T1="inertness faces 3-4: activations-as-migrations + done moves one store right"
  T2="Faces 3-4 of inertness-generator-2026-08-07 §3 + F3 lint: activations-become-migrations"
}

teardown() {
  [ -f "$BATS_TEST_TMPDIR/live.pid" ] && kill "$(cat "$BATS_TEST_TMPDIR/live.pid")" 2>/dev/null
  return 0
}

# A process that is genuinely alive for the duration of one test, so claimer_live's `kill -0` has
# something true to say. Sleeps are not a timing dependency here — nothing waits on the clock — but
# TWO details are load-bearing, and getting either wrong HANGS the whole suite rather than failing it:
#
#   · `>/dev/null 2>&1` ON THE BACKGROUND JOB. This helper is called inside `$( )`, and a command
#     substitution reads its pipe until EVERY writer closes it. A bare `sleep 60 &` inherits that
#     pipe, so the substitution blocks for the full sleep and bats waits behind it — measured here:
#     the suite sat wedged with two orphaned `sleep` processes holding the fds, looking exactly like
#     a slow suite under load rather than a harness bug.
#   · THE PID GOES TO A FILE, not a variable. `$( )` is a subshell, so `LIVE_PID=$!` would be set in
#     a child and `teardown` would have nothing to kill — the orphan then outlives the run.
#
# 60s, not 300: long enough that no test can outrun it, short enough that a missed teardown clears
# itself instead of littering the box.
live_claimer() {
  sleep 60 >/dev/null 2>&1 &
  echo $! > "$BATS_TEST_TMPDIR/live.pid"
  echo "$HOST-$(cat "$BATS_TEST_TMPDIR/live.pid")"
}
# REAPED, not merely exited: `kill -0` returns 0 on an unreaped zombie, so a dead claimer that was
# never waited for would read LIVE (memory: kill-on-reaped-child-fails-fast-path-hides-it).
dead_claimer() {
  local p; sleep 0 >/dev/null 2>&1 & p=$!; wait "$p" 2>/dev/null
  echo "$HOST-$p"
}

add_pair() {
  A="$(bash "$CB" add --project P --dod-ref docs/research/inertness.md --title "$T1" --source sess-A)"
  B="$(bash "$CB" add --project P --dod-ref docs/research/inertness.md --title "$T2" --source sess-B)"
}
link_pair() {
  bash "$CB" link "$A" --condition inertness-faces-three-four >/dev/null
  bash "$CB" link "$B" --condition inertness-faces-three-four >/dev/null
}

# ── CONTROL: the live defect, reproduced ──────────────────────────────────────────────────────────

@test "CONTROL — two wordings of one condition, UNLINKED, are still BOTH claimable (the defect)" {
  add_pair
  [ "$A" != "$B" ]
  run bash "$CB" claim "$A" --by "$(live_claimer)"
  [ "$status" -eq 0 ]
  run bash "$CB" claim "$B" --by "$HOST-$$"
  [ "$status" -eq 0 ]        # <- two workers on one piece of work: 2026-08-07
}

# ── the lease ─────────────────────────────────────────────────────────────────────────────────────

@test "linked rows: a claim is REFUSED while the sibling is LIVE" {
  add_pair; link_pair
  bash "$CB" claim "$A" --by "$(live_claimer)"
  run bash "$CB" claim "$B" --by "$HOST-$$"
  [ "$status" -eq 4 ]
}

@test "the refusal carries verdict=sibling-held on line 1 and names the sibling" {
  add_pair; link_pair
  bash "$CB" claim "$A" --by "$(live_claimer)"
  run bash "$CB" claim "$B" --by "$HOST-$$"
  [ "$(printf '%s' "$output" | head -1 | grep -c 'verdict=sibling-held')" -eq 1 ]
  printf '%s' "$output" | head -1 | grep -q "$A"
}

@test "a REFUSED claim appends NOTHING — the item is exactly as it was" {
  add_pair; link_pair
  bash "$CB" claim "$A" --by "$(live_claimer)"
  before="$(grep -c '' "$CC_BACKLOG_FILE")"
  run bash "$CB" claim "$B" --by "$HOST-$$"
  [ "$status" -eq 4 ]
  [ "$(grep -c '' "$CC_BACKLOG_FILE")" -eq "$before" ]
  [ "$(bash "$CB" list --all --json | jq -r --arg i "$B" '.[]|select(.id==$i)|.status')" = "open" ]
}

# ── CONTROL: the lease must RELEASE, or it strands both rows forever ──────────────────────────────

@test "CONTROL — a DEAD sibling does not hold the lease: the claim PROCEEDS" {
  add_pair; link_pair
  bash "$CB" claim "$A" --by "$(dead_claimer)"
  run bash "$CB" claim "$B" --by "$HOST-$$"
  [ "$status" -eq 0 ]
}

@test "--force overrides the sibling lease" {
  add_pair; link_pair
  bash "$CB" claim "$A" --by "$(live_claimer)"
  run bash "$CB" claim "$B" --by "$HOST-$$" --force
  [ "$status" -eq 0 ]
}

@test "the lease is scoped to the PROJECT: the same slug elsewhere does not hold it" {
  A="$(bash "$CB" add --project P --title "$T1" --source s)"
  B="$(bash "$CB" add --project OTHER --title "$T2" --source s)"
  bash "$CB" link "$A" --condition shared-slug >/dev/null
  bash "$CB" link "$B" --condition shared-slug >/dev/null
  bash "$CB" claim "$A" --by "$(live_claimer)"
  run bash "$CB" claim "$B" --by "$HOST-$$"
  [ "$status" -eq 0 ]
}

@test "an UNLINKED third row sharing only the dodRef is NOT leased (dodRef is not the key)" {
  add_pair; link_pair
  C="$(bash "$CB" add --project P --dod-ref docs/research/inertness.md \
        --title "postland auto-revert actuator is 12% effective" --source sess-C)"
  bash "$CB" claim "$A" --by "$(live_claimer)"
  run bash "$CB" claim "$C" --by "$HOST-$$"
  [ "$status" -eq 0 ]        # 8e8a306f6dc0's real shape: same doc, different work
}

# ── link ──────────────────────────────────────────────────────────────────────────────────────────

@test "link attaches a condition to a row that already exists" {
  add_pair
  bash "$CB" link "$A" --condition inertness-faces-three-four
  [ "$(bash "$CB" list --all --json | jq -r --arg i "$A" '.[]|select(.id==$i)|.condition')" \
    = "inertness-faces-three-four" ]
}

@test "link does not change status: a claimed row stays claimed" {
  add_pair
  bash "$CB" claim "$A" --by "$(live_claimer)"
  bash "$CB" link "$A" --condition inertness-faces-three-four
  [ "$(bash "$CB" list --all --json | jq -r --arg i "$A" '.[]|select(.id==$i)|.status')" = "claimed" ]
}

@test "link is idempotent on the same slug — a re-link writes nothing" {
  add_pair
  bash "$CB" link "$A" --condition inertness-faces-three-four >/dev/null
  before="$(grep -c '' "$CC_BACKLOG_FILE")"
  run bash "$CB" link "$A" --condition inertness-faces-three-four
  [ "$status" -eq 0 ]
  [ "$(grep -c '' "$CC_BACKLOG_FILE")" -eq "$before" ]
}

@test "re-keying a row to a DIFFERENT condition is REFUSED without --force" {
  add_pair
  bash "$CB" link "$A" --condition inertness-faces-three-four >/dev/null
  run bash "$CB" link "$A" --condition something-else
  [ "$status" -eq 4 ]
  run bash "$CB" link "$A" --condition something-else --force
  [ "$status" -eq 0 ]
}

@test "link enforces the SAME digit rule as add --condition (a measurement is not a state)" {
  add_pair
  run bash "$CB" link "$A" --condition memory-index-over-budget-20.5KB
  [ "$status" -eq 2 ]
  # `list --json` DELETES an empty condition on purpose (`has("condition")` is its exact test), so a
  # bare `.condition` reads `null` here, never "". Asserting `= ""` tested the reader, not the write.
  [ "$(bash "$CB" list --all --json | jq -r --arg i "$A" '.[]|select(.id==$i)|has("condition")')" = "false" ]
}

@test "link of an unknown id is rc 3, not a silent write" {
  run bash "$CB" link deadbeefcafe --condition some-state
  [ "$status" -eq 3 ]
}

# ── dups: a report, never a gate ──────────────────────────────────────────────────────────────────

@test "dups reports two live rows sharing project+dodRef" {
  add_pair
  run bash "$CB" dups --json
  [ "$(printf '%s' "$output" | jq 'length')" -eq 1 ]
  [ "$(printf '%s' "$output" | jq '.[0].items|length')" -eq 2 ]
}

@test "dups DROPS a group once its rows are joined — an answered group is not re-reported" {
  add_pair; link_pair
  run bash "$CB" dups --json
  [ "$(printf '%s' "$output" | jq 'length')" -eq 0 ]
}

@test "dups ignores terminal rows: a finished plan is not a standing alarm" {
  add_pair
  bash "$CB" claim "$A" --by "$HOST-$$" >/dev/null
  # "done" QUOTED: it is cc-backlog's verb, but bare it parses as the shell keyword (SC1010) — the
  # shipped dispatch table quotes it for the same reason (`cmd_transition "done"`).
  bash "$CB" "done" "$A" --evidence abc123 >/dev/null
  run bash "$CB" dups --json
  [ "$(printf '%s' "$output" | jq 'length')" -eq 0 ]
}

@test "dups gates NOTHING — the rows it names are still claimable" {
  add_pair
  bash "$CB" dups >/dev/null
  run bash "$CB" claim "$B" --by "$HOST-$$"
  [ "$status" -eq 0 ]
}

# ── the dispatcher seam: the verdict must survive claim_excerpt ───────────────────────────────────
# cc-dispatch can only see this refusal through claim_excerpt (head -1 | tr -cd printable | cut -c1-200).
# A refusal whose token fell outside that window would silently degrade to the lease's FAILED path —
# and FAILED feeds thrash_map a fault record every tick for a correct refusal. The real function is
# extracted from the shipped bin/cc-dispatch and run against the real refusal (memory:
# control-must-replay-the-real-artifact).

@test "verdict=sibling-held survives cc-dispatch's own claim_excerpt" {
  [ -f "$DISPATCH" ] || skip "bin/cc-dispatch not found"
  LIB="$BATS_TEST_TMPDIR/lib.sh"
  sed -n '/^claim_excerpt()/,/^}/p' "$DISPATCH" > "$LIB"
  grep -q '^claim_excerpt()' "$LIB" || skip "could not extract claim_excerpt"
  add_pair; link_pair
  bash "$CB" claim "$A" --by "$(live_claimer)"
  # rc 4 IS the refusal under test, and bats' errexit would fail the test on it. Captured into `rc`
  # and asserted rather than swallowed with `|| true`: a silenced exit code cannot tell "refused as
  # designed" from "the claim never ran" (memory: claimed-outcome-vs-checked-outcome).
  rc=0; bash "$CB" claim "$B" --by "$HOST-$$" 2>"$BATS_TEST_TMPDIR/err" >/dev/null || rc=$?
  [ "$rc" -eq 4 ]
  run bash -c ". '$LIB'; claim_excerpt '$BATS_TEST_TMPDIR/err'"
  [ "$(printf '%s' "$output" | grep -c 'verdict=sibling-held')" -eq 1 ]
}

@test "MUTATION CONTROL — a done-latched refusal does NOT carry the sibling token" {
  [ -f "$DISPATCH" ] || skip "bin/cc-dispatch not found"
  LIB="$BATS_TEST_TMPDIR/lib.sh"
  sed -n '/^claim_excerpt()/,/^}/p' "$DISPATCH" > "$LIB"
  add_pair
  bash "$CB" claim "$A" --by "$HOST-$$" >/dev/null
  # "done" QUOTED: it is cc-backlog's verb, but bare it parses as the shell keyword (SC1010) — the
  # shipped dispatch table quotes it for the same reason (`cmd_transition "done"`).
  bash "$CB" "done" "$A" --evidence abc123 >/dev/null
  rc=0; bash "$CB" claim "$A" --by "$HOST-$$" 2>"$BATS_TEST_TMPDIR/err" >/dev/null || rc=$?
  [ "$rc" -eq 4 ]
  run bash -c ". '$LIB'; claim_excerpt '$BATS_TEST_TMPDIR/err'"
  [ "$(printf '%s' "$output" | grep -c 'verdict=sibling-held')" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'verdict=done-latched')" -eq 1 ]
}

@test "cc-dispatch discriminates sibling-held BEFORE the generic lease FAILED path" {
  [ -f "$DISPATCH" ] || skip "bin/cc-dispatch not found"
  sib="$(grep -n 'verdict=sibling-held}' "$DISPATCH" | head -1 | cut -d: -f1)"
  dl="$(grep -n 'verdict=done-latched}' "$DISPATCH" | head -1 | cut -d: -f1)"
  fail="$(grep -n 'claim rc=\$crc' "$DISPATCH" | head -1 | cut -d: -f1)"
  # Separate lines, never `[ A ] && [ B ]`: under bats' errexit the && chain short-circuits, so a
  # false A silently skips B (memory: exact-count-assertion-tripwires-its-own-subject).
  [ -n "$sib" ]
  [ -n "$dl" ]
  [ -n "$fail" ]
  [ "$sib" -lt "$fail" ]
  [ "$dl"  -lt "$fail" ]
}
