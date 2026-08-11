#!/usr/bin/env bats
# cc-backlog `venue` — the ROUTING DECISION recorded on an open row (venuePlan / venueWhy).
#
# The sibling suite tests/cc-backlog-venue.bats guards `claim --venue`, which says where the
# CURRENT HOLDER runs. This one guards the field written BEFORE a holder exists, and the cases that
# matter are the ones where the obvious implementation is silently destructive. Each is a property
# of the FOLD, which is where all three live and where none of them is visible by reading the verb:
#
#   · IT MUST NOT WRITE `venue`. That field is reset-on-claim and selects which liveness oracles
#     may convict — an unclaimed row reading `venue: cloud` invents a session for `reap` to fail to
#     see, and the first ordinary local claim would erase the plan anyway.
#   · IT MUST NOT ADVANCE `lastTs`. A venue label is written by a sweep over the WHOLE store, so
#     folding its ts in stamps today onto every open item at once — flattening the cc-dispatch
#     queue order, which sorts on `.ts // .lastTs`.
#   · IT MUST NOT CARRY `by`. The fold carries `by` across every event, so a record naming its
#     producer would overwrite the LEASE HOLDER on a claimed row.
#
# Every one of those is paired with a CONTROL showing the same fold DOES do the thing for the event
# that is supposed to do it — otherwise "venue did not touch it" is indistinguishable from "nothing
# touches it" and the assertion is dead.
#
# Assertions use the explicit `|| { …; false; }` form: a non-final `[[ ]]` is errexit-EXEMPT under
# bats and would be a DEAD assertion that can never fail.
#
# RED-PROOF (re-runnable): `git show origin/main:bin/cc-backlog` has no `venue` verb at all, so
# every case here exits 2 ("unknown verb") against it.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_DISPATCH_BIN="$BATS_TEST_TMPDIR/absent-dispatch"
  # The eligibility gate shells out to git for the measured arm; this suite is about the WRITE path
  # and must not depend on a repo existing.
  export CC_BACKLOG_ELIGIBLE_GATE=off
}

add() { "$CB" add --title "$1" --project probe --source "${2:-s}"; }
one() { "$CB" list --all --json | jq -c --arg i "$1" 'map(select(.id == $i)) | first'; }
field() { one "$1" | jq -r --arg k "$2" '.[$k] // "«absent»"'; }
lines() { grep -c '' "$CC_BACKLOG_FILE"; }

@test "1 venue writes venuePlan + venueWhy, and list --json carries both" {
  local id; id="$(add "ordinary work")"
  run "$CB" venue "$id" --venue cloud --why "eligible: history certified"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(field "$id" venuePlan)" = cloud ] || { one "$id"; false; }
  [ "$(field "$id" venueWhy)" = "eligible: history certified" ] || { one "$id"; false; }
}

@test "2 the why is HEAD-BIASED so a machine can read the class off it" {
  local id; id="$(add "ordinary work")"
  "$CB" venue "$id" --venue local --why "ineligible-box: pane,launchd" >/dev/null
  local tok; tok="$(one "$id" | jq -r '.venueWhy | split(": ")[0]')"
  [ "$tok" = "ineligible-box" ] || { echo "got $tok"; false; }
}

# ── the three destructive shapes, each with the control that makes the assertion live ───────────

@test "3 it does NOT write the claim-scoped venue field" {
  local id; id="$(add "ordinary work")"
  "$CB" venue "$id" --venue cloud --why "eligible: x" >/dev/null
  [ "$(field "$id" venue)" = local ] \
    || { echo "an UNCLAIMED row must not read venue=cloud — that invents a holder"; one "$id"; false; }
  [ "$(field "$id" venuePlan)" = cloud ] || { one "$id"; false; }
}

@test "4 CONTROL: a CLAIM does set venue — so case 3 is a fact about the verb, not about the fold" {
  local id; id="$(add "ordinary work")"
  "$CB" claim "$id" --by "$$-probe" --venue cloud >/dev/null 2>&1
  [ "$(field "$id" venue)" = cloud ] \
    || { echo "the claim path must still set venue, else case 3 asserts nothing"; one "$id"; false; }
}

@test "5 it does NOT advance lastTs — a store-wide sweep must not restamp every item" {
  # A hand-authored old record, so the two timestamps cannot collide inside one second.
  printf '%s\n' '{"id":"old00000000","ts":"2020-01-01T00:00:00Z","event":"add","title":"t","project":"probe"}' \
    >> "$CC_BACKLOG_FILE"
  "$CB" venue old00000000 --venue local --why "ineligible-box: pane" >/dev/null
  [ "$(field old00000000 lastTs)" = "2020-01-01T00:00:00Z" ] \
    || { echo "lastTs moved: $(field old00000000 lastTs) — cc-dispatch orders the queue on this"; false; }
}

@test "6 CONTROL: a CLAIM does advance lastTs — the fold is not simply frozen" {
  printf '%s\n' '{"id":"old11111111","ts":"2020-01-01T00:00:00Z","event":"add","title":"t","project":"probe"}' \
    >> "$CC_BACKLOG_FILE"
  "$CB" claim old11111111 --by "$$-probe" >/dev/null 2>&1
  [ "$(field old11111111 lastTs)" != "2020-01-01T00:00:00Z" ] \
    || { echo "nothing advances lastTs, so case 5 proves nothing"; false; }
}

@test "7 it does NOT re-assign a live claim — the holder survives the annotation" {
  local id; id="$(add "ordinary work")"
  "$CB" claim "$id" --by "holder-9999" >/dev/null 2>&1
  [ "$(field "$id" by)" = "holder-9999" ] || { echo "setup failed"; one "$id"; false; }
  "$CB" venue "$id" --venue local --why "ineligible-box: pane" >/dev/null
  [ "$(field "$id" by)" = "holder-9999" ] \
    || { echo "the lease holder was overwritten by an annotation: $(field "$id" by)"; false; }
  [ "$(field "$id" status)" = claimed ] \
    || { echo "status changed: $(field "$id" status)"; false; }
}

@test "8 an unlabelled item carries NO venuePlan KEY, so select(.venuePlan) is the coverage test" {
  local id; id="$(add "never routed")"
  # jq treats the empty string as TRUTHY, so a ""-carrying key would make every item in the store
  # answer yes on the day the field appeared — the same defect `falsifier` was fixed for.
  one "$id" | jq -e 'has("venuePlan") | not' >/dev/null || { one "$id"; false; }
  one "$id" | jq -e 'has("venueWhy") | not' >/dev/null || { one "$id"; false; }
  local n; n="$("$CB" list --all --json | jq '[.[] | select(.venuePlan)] | length')"
  [ "$n" -eq 0 ] || { echo "coverage reads $n over a store with no labels"; false; }
}

# ── the closed set, the required why, and the refusals ─────────────────────────────────────────

@test "9 --venue is a CLOSED SET: a typo is rc 2, never free text that falls through to local" {
  local id; id="$(add "ordinary work")"
  run "$CB" venue "$id" --venue clod --why "x: y"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [ "$(field "$id" venuePlan)" = "«absent»" ] || { echo "a rejected verdict was still written"; false; }
}

@test "10 --why is REQUIRED — a label with no recorded reason is unauditable" {
  local id; id="$(add "ordinary work")"
  run "$CB" venue "$id" --venue cloud
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"--why"* ]] || { echo "the refusal must name what is missing: $output"; false; }
}

@test "11 an unknown id is rc 3, and a DONE item is rc 4 under its own reason" {
  run "$CB" venue nosuchid0000 --venue cloud --why "x: y"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  local id; id="$(add "finished work")"
  "$CB" done "$id" --evidence "landed" >/dev/null 2>&1
  run "$CB" venue "$id" --venue cloud --why "x: y"
  [ "$status" -eq 4 ] || { echo "$output"; false; }
  [[ "$output" == *"DONE"* ]] || { echo "$output"; false; }
}

# ── idempotence and re-routing ─────────────────────────────────────────────────────────────────

@test "12 IDEMPOTENT: an unchanged decision appends nothing — the producer is meant to be re-run" {
  local id before; id="$(add "ordinary work")"
  "$CB" venue "$id" --venue cloud --why "eligible: x" >/dev/null
  before="$(lines)"
  "$CB" venue "$id" --venue cloud --why "eligible: x" >/dev/null
  "$CB" venue "$id" --venue cloud --why "eligible: x" >/dev/null
  [ "$(lines)" -eq "$before" ] \
    || { echo "grew from $before to $(lines) — a cadence sweep would bury every real decision"; false; }
}

@test "13 A CHANGED decision DOES append, and the LATER record wins" {
  local id before; id="$(add "ordinary work")"
  "$CB" venue "$id" --venue cloud --why "eligible: x" >/dev/null
  before="$(lines)"
  run "$CB" venue "$id" --venue local --why "ineligible-deep-history: 2ac85e49"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(lines)" -gt "$before" ] || { echo "a re-route must be recorded"; false; }
  [ "$(field "$id" venuePlan)" = local ] \
    || { echo "last-non-empty-wins is what lets a moved tree retract a label"; one "$id"; false; }
  [ "$(field "$id" venueWhy)" = "ineligible-deep-history: 2ac85e49" ] || { one "$id"; false; }
}

@test "14 a re-route is LOUD about having been one" {
  local id; id="$(add "ordinary work")"
  "$CB" venue "$id" --venue cloud --why "eligible: x" >/dev/null
  run "$CB" venue "$id" --venue local --why "premise-superseded: gone"
  [[ "$output" == *"RE-ROUTED"* ]] \
    || { echo "a decision reversing itself must not read like a first write: $output"; false; }
}

@test "15 the label changes NO status — routing is not a transition" {
  local id; id="$(add "ordinary work")"
  "$CB" venue "$id" --venue cloud --why "eligible: x" >/dev/null
  [ "$(field "$id" status)" = open ] || { one "$id"; false; }
  one "$id" | jq -e '.wasDone == false' >/dev/null || { one "$id"; false; }
}
