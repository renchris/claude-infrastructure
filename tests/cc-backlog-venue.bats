#!/usr/bin/env bats
# cc-backlog VENUE — an oracle that cannot SEE a population must not RETURN A VERDICT about it.
#
# Both liveness oracles are host-local (`kill -0` + the cc-sessions pane registry; `lsof -d cwd` +
# `pgrep -f` over a local worktree). A worker in an Anthropic-managed VM is in neither population,
# and the registry ANSWERS "absent" rather than failing — which the pre-venue code read as rc 1,
# PROVEN NOT-LIVE, i.e. `reopen`, i.e. cc-dispatch's fire predicate, i.e. a second worker onto live
# work. See VENUE in bin/cc-backlog's header and docs/research/cloud-observability-2026-08-07.md.
#
# THE CONTROLS ARE THE POINT. A suite that only proved "cloud abstains" would pass just as happily
# against a claimer_live() that abstained on EVERYTHING — which would disable local dead-worker
# detection entirely and read as a green board (memory: control-must-replay-the-real-artifact,
# positive-control-the-denominator). So every venue assertion below is paired with a local one that
# must still CONVICT, and the pre-existing-record case is asserted directly.
#
# WHAT THIS SUITE PINS, MEASURED per-site 2026-08-07 (memory: per-site-mutation-attributes-coverage —
# one mutant per SITE, because a blanket mutant over redundant siblings under-reports):
#   remove claimer_live's venue gate ONLY  → 0 red   (survives)
#   remove owned_wait's  venue gate ONLY   → 0 red   (survives)
#   remove BOTH                            → 5 red   (tests 1,2,3,8,12)
# So the suite pins the PAIR, not either gate. That is not a hole to plug by asserting on internals:
# the redundancy is the design (siblings over one population must share the state model, or the one
# left behind re-opens the defect), and these tests assert BEHAVIOUR. But do not read a green board
# as "both gates are covered" — deleting either one alone is invisible here. A refactor that removes
# one must be judged by the argument in bin/cc-backlog's VENUE header, not by this suite going green.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  # OWN $HOME before anything else. The three seams that actually reach live state are fixtured
  # explicitly below, and were from the start — but that is a per-seam defence, and it only covers
  # the seams that exist TODAY. Any future default that resolves under $HOME (the subject already
  # has several: the IDL, the sessions-bin resolver, the worktree root) would silently start writing
  # to the operator's real ~/ with no test change to mark it. Owning $HOME makes the leak structural
  # rather than a thing each new seam has to remember, which is what the hermeticity ratchet asks for.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # The registry probe is the one thing the subject reads under $HOME that these tests DEPEND on
  # answering: claimer_live's local branch needs an oracle that ANSWERS "not listed" (rc 1) for the
  # dead-local controls. With $HOME owned there is no ~/.claude/bin/cc-sessions to resolve, which
  # would make it UNRESOLVED (rc 2) and let the local controls abstain — passing vacuously for a
  # reason that has nothing to do with venue. Stub it to an empty-but-valid registry.
  printf '#!/bin/bash\necho "[]"\n' > "$BATS_TEST_TMPDIR/nosess"; chmod +x "$BATS_TEST_TMPDIR/nosess"
  export CC_BACKLOG_SESSIONS_BIN="$BATS_TEST_TMPDIR/nosess"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  # The reap verdict journal defaults under $HOME; fixture it in setup() (never per-test) so no test
  # in this file can append to the operator's live ~/.claude/autonomy/idl.jsonl.
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  # Own the worktree-root seam too: owned_wait treats an ABSENT root as starvation (rc 2), which
  # would make the local control abstain for a reason that has nothing to do with venue and let a
  # broken venue gate pass vacuously. A present-but-empty root gives the local path the real
  # "answered, nobody home" rc 1 it needs.
  export CC_BACKLOG_WT_ROOT="$BATS_TEST_TMPDIR/worktrees"
  mkdir -p "$CC_BACKLOG_WT_ROOT"
}

# add_and_claim <source> <claimer> [--venue V] → the id, claimed and aged past the stale gate.
add_and_claim() {
  local src="$1" who="$2"; shift 2
  local id; id="$("$CB" add --title "venue probe $src" --project probe --source "$src")"
  "$CB" claim "$id" --by "$who" "$@" >/dev/null
  printf '%s' "$id"
}

# reap_aged <id> → `reap --dry-run` with the claim aged past every stale gate via the NOW seam.
# The seam is the producer's own (CC_BACKLOG_NOW), so this exercises the real fold, not a fixture.
# 100000s is past CC_BACKLOG_UNRESOLVED_MAX_S (21600), so an abstaining item reaches the ceiling
# and BLOCKs out to a human — the terminal state, not the ordinary one.
reap_aged() {
  CC_BACKLOG_NOW=$(( $(date +%s) + 100000 )) "$CB" reap --dry-run 2>&1
}

# reap_mid <id> → past the 5400s stale gate but UNDER the 21600s abstention ceiling: the state a
# cloud claim actually sits in while its worker is running. Asserted separately from reap_aged
# because "did not reopen" is also true at the ceiling, where the reason is the BLOCK — a suite
# that only checked the aged case could not tell abstention from escalation.
reap_mid() {
  CC_BACKLOG_NOW=$(( $(date +%s) + 7200 )) "$CB" reap --dry-run 2>&1
}

# ── the defect, and its control ────────────────────────────────────────────────────────────────

@test "cloud claim: an unobservable worker is NOT convicted dead" {
  local id; id="$(add_and_claim cloud-abstain "cloudvm-4242" --venue cloud)"
  run reap_aged "$id"
  [ "$status" -eq 0 ]
  # The pre-venue behaviour, verbatim from the 2026-08-07 measurement, was WOULD-REOPEN.
  [[ "$output" != *"WOULD-REOPEN"* ]] || false
  [[ "$output" == *"$id"* ]]
}

@test "cloud claim under the ceiling: ABSTAINS, and says so" {
  local id; id="$(add_and_claim cloud-keep "cloudvm-4242" --venue cloud)"
  run reap_mid "$id"
  [ "$status" -eq 0 ]
  [[ "$output" == *"KEEP $id"* ]] || false
  [[ "$output" == *"UNRESOLVED"* ]] || false
  [[ "$output" == *"not proof of death"* ]]
}

@test "cloud claim past the ceiling: BLOCKS to a human, never reopens" {
  local id; id="$(add_and_claim cloud-block "cloudvm-4242" --venue cloud)"
  run reap_aged "$id"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WOULD-BLOCK"* ]] || false
  [[ "$output" != *"WOULD-REOPEN"* ]]
}

@test "CONTROL: the gate keys on the VENUE FIELD, not on the shape of the claimer name" {
  # Same claimer string as the cloud tests, claimed --venue local. If the gate were string-matching
  # the name (or if venue defaulted to anything but local) this would abstain; it must convict.
  local id; id="$(add_and_claim venue-not-name "cloudvm-4242" --venue local)"
  run reap_aged "$id"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WOULD-REOPEN"* ]] || false
  [[ "$output" == *"dead-worker"* ]]
}

@test "CONTROL: a dead LOCAL claimer is still convicted — the gate did not disable detection" {
  # A pid that cannot be live: claimed by this host with pid 0 is not a well-formed live claimer,
  # so use a real-shaped <host>-<pid> whose pid is reaped. $$ + a large offset is not guaranteed
  # free, so spawn and wait: the pid is provably gone before we build the claim.
  local dead; dead="$(bash -c 'echo $$')"
  local id; id="$(add_and_claim local-dead "$(hostname -s)-$dead")"
  run reap_aged "$id"
  [ "$status" -eq 0 ]
  # This is the assertion the whole change is measured against: local detection must be UNCHANGED.
  [[ "$output" == *"WOULD-REOPEN"* ]] || false
  [[ "$output" == *"dead-worker"* ]]
}

@test "CONTROL: a live LOCAL claimer is still recognised live" {
  local id; id="$(add_and_claim local-live "$(hostname -s)-$$")"
  run reap_aged "$id"
  [ "$status" -eq 0 ]
  [[ "$output" != *"WOULD-REOPEN"* ]] || false
  # Past LIVE_CLAIM_MAX_S a live claimer is a wedge, which BLOCKS rather than reopens.
  [[ "$output" == *"WOULD-BLOCK"* ]]
}

@test "CONTROL: a pre-venue record (no venue field) behaves exactly as before" {
  # Hand-write the record shape that all pre-existing ledger lines have — no venue key at all.
  local id="aaaaaaaaaaaa" dead; dead="$(bash -c 'echo $$')"
  printf '%s\n' \
    "{\"id\":\"$id\",\"ts\":\"2026-08-07T00:00:00Z\",\"event\":\"add\",\"project\":\"probe\",\"title\":\"pre-venue\",\"dodRef\":\"\",\"source\":\"pre-venue\"}" \
    "{\"id\":\"$id\",\"ts\":\"2026-08-07T00:00:01Z\",\"event\":\"claim\",\"by\":\"$(hostname -s)-$dead\"}" \
    > "$CC_BACKLOG_FILE"
  run reap_aged "$id"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WOULD-REOPEN"* ]] || false
  [[ "$output" == *"dead-worker"* ]]
}

# ── the acquire side: the lease must not hand a cloud incumbent's work to a second worker ──────

@test "cloud incumbent: the LEASE refuses to displace it" {
  local id; id="$(add_and_claim cloud-lease "cloudvm-777" --venue cloud)"
  run "$CB" claim "$id" --by "$(hostname -s)-$$"
  [ "$status" -eq 4 ]
  [[ "$output" == *"UNRESOLVED"* ]]
}

@test "CONTROL: the LEASE still displaces a dead LOCAL incumbent" {
  local dead; dead="$(bash -c 'echo $$')"
  local id; id="$(add_and_claim local-lease "$(hostname -s)-$dead")"
  run "$CB" claim "$id" --by "$(hostname -s)-$$"
  [ "$status" -eq 0 ]
}

# ── the closed set: a mislabel must not fall back to local ─────────────────────────────────────

@test "unknown venue is refused, never silently treated as local" {
  local id; id="$("$CB" add --title "venue typo" --project probe --source venue-typo)"
  run "$CB" claim "$id" --by "cloudvm-1" --venue clod
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown --venue"* ]] || false
  # And nothing was written: a refused claim must not leave the item claimed.
  run "$CB" list --json
  [[ "$output" != *'"status":"claimed"'* ]]
}

@test "--venue is claim-only" {
  local id; id="$("$CB" add --title "venue on done" --project probe --source venue-scope)"
  "$CB" claim "$id" --by "$(hostname -s)-$$" >/dev/null
  # `done` is QUOTED: unquoted, shellcheck parses the bare word as the loop keyword and reports
  # SC1010 ("use a semicolon or linefeed before done"). It is a verb here, not a terminator.
  run "$CB" "done" "$id" --evidence deadbeef --venue cloud
  [ "$status" -eq 2 ]
  [[ "$output" == *"applies only to claim"* ]]
}

# ── the venue must survive a re-key, or the worker demotes itself into the blind oracles ───────

@test "reclaim preserves a cloud venue" {
  local id; id="$(add_and_claim cloud-reclaim "cloudvm-888" --venue cloud)"
  run "$CB" reclaim "$id" --by "cloud-worker-abc"
  [ "$status" -eq 0 ]
  run "$CB" list --json
  [[ "$output" == *'"venue":"cloud"'* ]] || false
  # …and the re-keyed claim is still unobservable rather than dead.
  run reap_aged "$id"
  [[ "$output" != *"WOULD-REOPEN"* ]]
}

@test "a later LOCAL claim resets the venue — it does not inherit cloud" {
  local id; id="$(add_and_claim venue-reset "cloudvm-999" --venue cloud)"
  "$CB" reopen "$id" --force >/dev/null
  local dead; dead="$(bash -c 'echo $$')"
  "$CB" claim "$id" --by "$(hostname -s)-$dead" >/dev/null
  run "$CB" list --json
  [[ "$output" == *'"venue":"local"'* ]] || false
  # The reset is load-bearing: a carried-forward "cloud" would make this dead local worker
  # permanently unobservable to oracles that can see it perfectly well.
  run reap_aged "$id"
  [[ "$output" == *"WOULD-REOPEN"* ]]
}
