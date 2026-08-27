#!/usr/bin/env bats
# CC_DISPATCH_VENUE_ONLY — the migration lever: fire ONE venue, park the rest VISIBLY.
#
# WHY THIS KNOB EXISTS. Before it, the dispatcher had exactly two states: everything fires, or
# DECIDE_ONLY stops every spawn including the cloud ones. "Migrate from local spawn to cloud spawn"
# was inexpressible. This is the third axis.
#
# THE LOAD-BEARING PROPERTY is NOT that it narrows — it is that narrowing to nothing is
# DISTINGUISHABLE from a healthy empty queue. A filter that silently matched zero rows would read
# exactly like a correctly-configured cloud-only box with no cloud work: a total outage wearing the
# shape of success. Every test below either pins the parked COUNT or pins the REFUSAL.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="$REPO/bin/cc-dispatch"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/autonomy"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_DISPATCH_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_DISPATCH_LOCK_DIR="$BATS_TEST_TMPDIR/lock"
  export CC_DISPATCH_PROJECT="p"
  : > "$CC_BACKLOG_FILE"; : > "$CC_DISPATCH_IDL"
}

# row <id> <venuePlan|-> — an open, dispatchable item in project p
row() {
  local vp=""
  [ "${2:--}" != "-" ] && vp=", \"venuePlan\":\"$2\""
  printf '{"id":"%s","ts":"2026-08-01T00:00:00Z","event":"add","project":"p","title":"t %s"%s}\n' \
    "$1" "$1" "$vp" >> "$CC_BACKLOG_FILE"
}

@test "unset: the filter is absent, so every dispatchable item survives (the incumbent path)" {
  row a cloud; row b local; row c -
  run env -u CC_DISPATCH_VENUE_ONLY "$SUT" --decide
  [ "$status" -eq 0 ]
  # No park record at all — an unset filter must not journal a narrowing that did not happen.
  ! grep -q 'venue-only' "$CC_DISPATCH_IDL"
}

@test "=cloud admits ONLY the cloud rows" {
  row a cloud; row b local; row c cloud
  run env CC_DISPATCH_VENUE_ONLY=cloud "$SUT" --decide
  [ "$status" -eq 0 ]
  grep -q 'venue-only=cloud parked 1 of 3' "$CC_DISPATCH_IDL"
}

@test "an UNLABELLED row is parked too — absence of a plan is not evidence of eligibility" {
  # The producer fails CLOSED for the same reason: a wrong answer in a venue nobody can SEE.
  row a cloud; row c -; row d -
  run env CC_DISPATCH_VENUE_ONLY=cloud "$SUT" --decide
  [ "$status" -eq 0 ]
  grep -q 'venue-only=cloud parked 2 of 3' "$CC_DISPATCH_IDL"
}

# THE TEST THIS FILE EXISTS FOR. Narrowing to zero must be LOUD.
@test "parking the WHOLE queue is journalled with its count, never a silent empty wave" {
  row b local; row c local
  run env CC_DISPATCH_VENUE_ONLY=cloud "$SUT" --decide
  [ "$status" -eq 0 ]
  grep -q 'venue-only=cloud parked 2 of 2' "$CC_DISPATCH_IDL"
}

@test "a genuinely empty queue does NOT emit a park record — the two states stay apart" {
  # The other half of the discrimination: no dispatchable rows at all is not the same event as
  # 'the filter removed them', and a reader must be able to tell which happened.
  run env CC_DISPATCH_VENUE_ONLY=cloud "$SUT" --decide
  [ "$status" -eq 0 ]
  ! grep -q 'venue-only' "$CC_DISPATCH_IDL"
}

@test "an unrecognised value REFUSES the pass rather than narrowing it to zero" {
  # A typo'd venue matches no row, and a silent narrowing would be indistinguishable from a healthy
  # cloud-only box with an empty cloud queue (MEMORY: default-path-hardening-is-blind-to-the-
  # explicit-argument). Fail-closed and visible beats fail-quiet.
  row a cloud; row b local
  run env CC_DISPATCH_VENUE_ONLY=Cloud "$SUT" --decide
  [ "$status" -eq 3 ]
  printf '%s' "$output" | grep -q 'closed set'
  grep -q 'outside the closed set' "$CC_DISPATCH_IDL"
}

@test "=local is symmetric — the lever is a filter, not a cloud special case" {
  # If only 'cloud' worked this would be a hardcoded migration rather than a venue filter, and
  # rolling BACK to local-only would need another code change.
  row a cloud; row b local
  run env CC_DISPATCH_VENUE_ONLY=local "$SUT" --decide
  [ "$status" -eq 0 ]
  grep -q 'venue-only=local parked 1 of 2' "$CC_DISPATCH_IDL"
}

# ══ A VENUE REFUSAL COSTS THE ROW ITS SLOT (cloud-lane fix #2) ════════════════════════════════════
#
# THE DEFECT. A row the actuator refused off-box keeps its `venuePlan=cloud` label, so it stays
# dispatchable, so it re-admits at the head of the queue every pass and is refused again — while
# holding a cloud slot. Measured 2026-08-24: six such rows held all six slots and the seven rows
# that COULD run off-box were admitted zero times in a day.
#
# 🚨 NOT VIA thrash_map. That map keys on `.action=="failed"`, and the claim gate records this
# refusal as `skipped` deliberately — a refusal is the system working, not a fault. These cases pin
# the exclusion to the actuator's OWN recorded verdict instead, and case (d) pins that no `failed`
# record is minted, so a later "fix" that routes it through the fault counter goes red here.
#
# RED-PROOF, MEASURED 2026-08-24 and re-runnable — `git archive bd5eab33e bin/cc-dispatch` into a
# scratch tree, copy this file to its tests/, run bats:
#
#     (a) RED — the pre-fix tree has no exclusion, so the refused row takes the one slot and the
#               eligible row behind it is never admitted. This is the defect, reproduced.
#     (e) RED — the pre-fix tree journals `ceiling:12` on a cloud pass whose free_slots is 6.
#     (c)     — GREEN on BOTH trees BY DESIGN. It is the positive control for (a): it proves this
#               harness can observe an admission at all, so (a)'s absence is evidence of the
#               exclusion rather than of a broken fixture (memory: positive-control-the-denominator).
#     (b) (b2) (d) (f) — GREEN on both trees, and they are GUARDS, not red-proofs. Stated plainly
#               rather than counted as part of the red: they pin properties the old tree could not
#               violate because it had no exclusion to make stale and no fault to mis-shape. What
#               they protect is the NEXT edit to this code, which is a real job but a different one.

# iso_ago <bsd-spec> <gnu-spec> — a UTC ISO timestamp that many units in the PAST, relative to NOW.
#
# 🚨 EVERY REFUSAL FIXTURE HERE MUST BE NOW-RELATIVE, AND A LITERAL DATE IS A TIME BOMB. The
# exclusion under test admits the row again once the refusal is older than
# CC_DISPATCH_VENUE_REFUSAL_TTL (bin/cc-dispatch:1732, default 86400s), so a fixture dated by hand
# is only inside the TTL on the day it was typed. This file shipped with a literal
# `2026-08-24T08:00:00Z` default and case (a) went red at 2026-08-25T08:00Z — silently, for two
# days, and it was the sole red suite standing between trunk and a green stamp, which is what the
# deploy converger needs before it will advance the live layer. Diagnosed 2026-08-26.
#   The trap has a second face worth naming, because it makes a test pass rather than fail: case (b)
# proves a refusal SELF-CLEARS when the row is touched afterwards, and with a stale literal date
# that refusal was ALSO expired, so (b) went green without exercising the self-clear arm at all — a
# vacuous pass wearing a green tick (memory: control-calibrated-to-implementation-decays,
# sibling-guard-makes-the-fixture-vacuous). Both are fixed by dating from `now`.
#   Cases that want an EXPIRED refusal must force it with CC_DISPATCH_VENUE_REFUSAL_TTL, never by
# picking an old date — see (b2), which pins TTL=1 so expiry is by construction, not by calendar.
iso_ago() {
  date -u -v-"$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "-$2" +%Y-%m-%dT%H:%M:%SZ
}

# refused <id> [ts] — the exact record the claim gate writes when cc-eligible refuses the item for
# this venue. Replayed verbatim from the live journal rather than approximated, because the
# exclusion parses this string (memory: control-must-replay-the-real-artifact).
# Default ts is ONE HOUR AGO — recent enough to be live under any sane TTL, and never a literal.
refused() {
  printf '{"ts":"%s","actor":"cc-dispatch","action":"skipped","detail":"%s: cloud-ineligible — claim REFUSED at the actuator: this work cannot run off-box — cc-backlog claim: REFUSED verdict=cloud-ineligible  %s — it claims LOCALLY untouched, or `cc-backlog claim %s --venue cloud --force`"}\n' \
    "${2:-$(iso_ago 1H '1 hour')}" "$1" "$1" "$1" >> "$CC_DISPATCH_IDL"
}
# admitted <id> → 1 if this pass journalled an `admit` decision for it, else 0
admitted() {
  jq -rs --arg i "$1" '[.[]|select(.action=="decision" and .id==$i and .verdict=="admit")]|length' \
    "$CC_DISPATCH_IDL" 2>/dev/null || echo 0
}

@test "(a) a row ALREADY refused off-box yields its cloud slot to work that can run" {
  row aa11cd016cb0 cloud; row bb22e58ac42d cloud
  refused aa11cd016cb0
  run env CC_DISPATCH_VENUE_ONLY=cloud CC_DISPATCH_CLOUD_CEILING=1 "$SUT" --decide
  [ "$status" -eq 0 ]
  # `a` is gone from the queue entirely — not admitted, not deferred, no decision of any kind.
  [ "$(admitted aa11cd016cb0)" -eq 0 ]
  [ "$(jq -rs '[.[]|select(.action=="decision" and .id=="aa11cd016cb0")]|length' "$CC_DISPATCH_IDL")" -eq 0 ]
  # ...and the ONE slot goes to the row behind it, which is the whole point of the fix.
  [ "$(admitted bb22e58ac42d)" -eq 1 ]
  grep -q 'venue-refused: 1 of 2' "$CC_DISPATCH_IDL"
}

@test "(b) the exclusion SELF-CLEARS: a row touched since its refusal is admitted again" {
  # Otherwise this fix mints the very thing it cures — a verdict that outlives the state it was a
  # verdict about. Anything that HAPPENS TO the row (reopen, unblock, an edited condition) advances
  # lastTs past the refusal, and the row re-enters the queue on the next pass with no operator
  # action. A `venue` record deliberately does NOT count: bin/cc-backlog:1157-1170 keeps venue
  # annotations out of lastTs on purpose, and the re-derived label is the other arm of the cure.
  #
  # The two fixture stamps are NOW-RELATIVE and ORDERED — refusal 2h ago, reopen 1h ago — so the
  # refusal is still LIVE under the TTL and the only thing that can admit this row is the
  # self-clear. With the literal dates this carried until 2026-08-26 the refusal was also expired,
  # so the row was admitted by the TTL and this case scored a green without touching its subject.
  local _ref _touch
  _ref="$(iso_ago 2H '2 hours')"; _touch="$(iso_ago 1H '1 hour')"
  printf '{"id":"aa11cd016cb0","ts":"2026-08-01T00:00:00Z","event":"add","project":"p","title":"t aa11cd016cb0","venuePlan":"cloud"}\n' >> "$CC_BACKLOG_FILE"
  printf '{"id":"aa11cd016cb0","ts":"%s","event":"reopen","project":"p"}\n' "$_touch" >> "$CC_BACKLOG_FILE"
  refused aa11cd016cb0 "$_ref"
  run env CC_DISPATCH_VENUE_ONLY=cloud "$SUT" --decide
  [ "$status" -eq 0 ]
  [ "$(admitted aa11cd016cb0)" -eq 1 ]
  ! grep -q 'venue-refused' "$CC_DISPATCH_IDL"
}

@test "(b2) the exclusion EXPIRES — a verdict has a shelf life, so it can never go permanently stale" {
  # The second self-clearing arm, and the one that makes this repair unable to become the defect it
  # repairs. TTL is forced to 1 s here and the refusal is dated in the past, so it is expired by
  # construction rather than by waiting.
  row aa11cd016cb0 cloud; row bb22e58ac42d cloud
  refused aa11cd016cb0 2026-08-24T08:00:00Z
  run env CC_DISPATCH_VENUE_ONLY=cloud CC_DISPATCH_VENUE_REFUSAL_TTL=1 "$SUT" --decide
  [ "$status" -eq 0 ]
  [ "$(admitted aa11cd016cb0)" -eq 1 ]
  ! grep -q 'venue-refused' "$CC_DISPATCH_IDL"
}

@test "(c) CONTROL: with no refusal on record the same row IS admitted" {
  # The positive control for (a). Without it, an exclusion that dropped EVERY row — or a harness
  # that journalled no admits at all — would read exactly like a working fix
  # (memory: positive-control-the-denominator).
  row aa11cd016cb0 cloud; row bb22e58ac42d cloud
  run env CC_DISPATCH_VENUE_ONLY=cloud CC_DISPATCH_CLOUD_CEILING=1 "$SUT" --decide
  [ "$status" -eq 0 ]
  [ "$(admitted aa11cd016cb0)" -eq 1 ]
  ! grep -q 'venue-refused' "$CC_DISPATCH_IDL"
}

@test "(d) the refusal is NEVER re-shaped as a fault — no failed record is minted for it" {
  # The design note at the claim gate chose `skipped` for this refusal on purpose, and thrash_map
  # counts only `failed`. This pins that the ordering fix did not smuggle a fault-shaped signal in
  # to get the demotion it wanted.
  row aa11cd016cb0 cloud; row bb22e58ac42d cloud
  refused aa11cd016cb0
  run env CC_DISPATCH_VENUE_ONLY=cloud CC_DISPATCH_CLOUD_CEILING=1 "$SUT" --decide
  [ "$status" -eq 0 ]
  [ "$(jq -rs '[.[]|select(.action=="failed")]|length' "$CC_DISPATCH_IDL")" -eq 0 ]
}

# ══ THE JOURNALLED CEILING IS THE LANE'S OWN (cloud-lane fix #4) ══════════════════════════════════
@test "(e) a cloud pass journals ceiling=CLOUD_CEILING, not the on-box CEILING" {
  # A live record read `{"free_slots":6,"ceiling":12,"live_workers":0}` — arithmetically impossible
  # under its own fields (6 = CLOUD_CEILING−0, 12 = CEILING), so anyone reading the journal derived
  # the wrong denominator and could not tell the two lanes apart. RED on bd5eab33e: it reads 12.
  row aa11cd016cb0 cloud; row bb22e58ac42d cloud
  run env CC_DISPATCH_VENUE_ONLY=cloud CC_DISPATCH_CLOUD_CEILING=6 CC_DISPATCH_CEILING=12 "$SUT" --decide
  [ "$status" -eq 0 ]
  [ "$(jq -rs '[.[]|select(.action=="decision")|.ceiling]|unique|join(",")' "$CC_DISPATCH_IDL")" = 6 ]
  # and the record is self-consistent: free_slots == ceiling − live_workers
  [ "$(jq -rs '[.[]|select(.action=="decision" and .verdict=="admit")|(.free_slots == (.ceiling - (.live_workers // 0)))]|all' "$CC_DISPATCH_IDL")" = true ]
}

@test "(f) a LOCAL pass still journals the on-box CEILING — the fix is per-lane, not a rename" {
  row aa11cd016cb0 local; row bb22e58ac42d local
  run env CC_DISPATCH_VENUE_ONLY=local CC_DISPATCH_CLOUD_CEILING=6 CC_DISPATCH_CEILING=12 "$SUT" --decide
  [ "$status" -eq 0 ]
  [ "$(jq -rs '[.[]|select(.action=="decision")|.ceiling]|unique|join(",")' "$CC_DISPATCH_IDL")" = 12 ]
}
