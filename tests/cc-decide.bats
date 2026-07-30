#!/usr/bin/env bats
# cc-decide — the unattended decision-queue packet tool (P15 §3.2 schema).
#   open  --class A|B|C --what <plain> [--option l::o ...] [--recommendation r]
#         [--default d] [--deadline ISO] [--session-sid s] [--session-pane u]
#         [--staged-artifact p] [--route-around r] [--id id]           → echoes id
#   veto <id> [--by who]      action <id> [--evidence ref]
#   list [--open|--all|--class X|--expiring]
#   expire-sweep              (class-B past deadline ⇒ expired-actioned + REPORT default line)
# Fail-closed: class-B needs default+deadline; class-C must NOT carry a default; what_plain required.
# inv7: a packet is EVIDENCE — status is a VIEW; an OPEN packet is NEVER deleted on age.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CD="$REPO/bin/cc-decide"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
}

# ── open: valid packets ────────────────────────────────────────────────────────
@test "open class-A writes a full-schema packet; id echoed; status open" {
  run bash "$CD" open --class A --what "ship the verified green diff" --recommendation "ship it"
  [ "$status" -eq 0 ]
  id="$output"
  [ -n "$id" ]
  f="$CC_DECISIONS_DIR/$id.json"
  [ -f "$f" ]
  run jq -r '.class' "$f";      [ "$output" = "A" ]
  run jq -r '.what_plain' "$f"; [ "$output" = "ship the verified green diff" ]
  run jq -r '.status' "$f";     [ "$output" = "open" ]
  run jq -e 'has("id") and has("created") and has("options") and has("recommendation")' "$f"
  [ "$status" -eq 0 ]
}

@test "open class-B with default+deadline succeeds; options parsed as label/outcome pairs" {
  run bash "$CD" open --class B --what "which account to continue on" \
    --option "next2::continue on next2 quota" --option "next3::continue on next3 quota" \
    --recommendation "next2 — most quota" --default "continue cross-account on next2" \
    --deadline "2099-01-01T00:00:00Z"
  [ "$status" -eq 0 ]
  f="$CC_DECISIONS_DIR/$output.json"
  run jq -r '.options | length' "$f";                 [ "$output" = "2" ]
  run jq -r '.options[0].label' "$f";                 [ "$output" = "next2" ]
  run jq -r '.options[0].outcome_in_operator_terms' "$f"; [ "$output" = "continue on next2 quota" ]
  run jq -r '.default_if_no_veto' "$f";               [ "$output" = "continue cross-account on next2" ]
}

@test "open class-C with a staged artifact and NO default succeeds" {
  run bash "$CD" open --class C --what "activate the reaper plist" \
    --staged-artifact "/tmp/reaper-activate.sh"
  [ "$status" -eq 0 ]
  f="$CC_DECISIONS_DIR/$output.json"
  run jq -r '.staged_artifact_path' "$f"; [ "$output" = "/tmp/reaper-activate.sh" ]
  run jq -r '.default_if_no_veto' "$f";   [ "$output" = "" ]
}

# ── open: fail-closed schema refusals ──────────────────────────────────────────
@test "REFUSE class-B without default (exit 2)" {
  run bash "$CD" open --class B --what "x" --deadline "2099-01-01T00:00:00Z"
  [ "$status" -eq 2 ]
}

@test "REFUSE class-B without deadline (exit 2)" {
  run bash "$CD" open --class B --what "x" --default "do the thing"
  [ "$status" -eq 2 ]
}

@test "REFUSE class-C WITH a default (C waits, never defaults) (exit 2)" {
  run bash "$CD" open --class C --what "x" --default "auto-activate"
  [ "$status" -eq 2 ]
}

@test "REFUSE missing what_plain (exit 2)" {
  run bash "$CD" open --class A
  [ "$status" -eq 2 ]
}

@test "REFUSE invalid class (exit 2)" {
  run bash "$CD" open --class Z --what "x"
  [ "$status" -eq 2 ]
}

@test "REFUSE class-B with empty deadline value treated as missing (exit 2)" {
  run bash "$CD" open --class B --what "x" --default "d" --deadline ""
  [ "$status" -eq 2 ]
}

# ── recycle-survival: the packet is durable on disk ────────────────────────────
@test "recycle-survival: an opened packet persists and is readable by a fresh invocation" {
  id=$(bash "$CD" open --class B --what "durable decision" --default "d" --deadline "2099-01-01T00:00:00Z")
  # simulate a recycle: nothing in-process survives, but the file must
  [ -f "$CC_DECISIONS_DIR/$id.json" ]
  run bash "$CD" list --open
  echo "$output" | grep -q "$id"
  echo "$output" | grep -q "durable decision"
}

@test "open is idempotent — same class+sid+what does NOT duplicate an open packet" {
  a=$(bash "$CD" open --class B --what "same" --session-sid s1 --default "d" --deadline "2099-01-01T00:00:00Z")
  b=$(bash "$CD" open --class B --what "same" --session-sid s1 --default "d" --deadline "2099-01-01T00:00:00Z")
  [ "$a" = "$b" ]
  n=$(ls "$CC_DECISIONS_DIR"/*.json | wc -l | tr -d ' ')
  [ "$n" -eq 1 ]
}

# ── expire-sweep: class-B past deadline fires the default (REPORTS, never executes) ─
@test "expire-sweep transitions a past-deadline class-B to expired-actioned and REPORTS the default" {
  id=$(bash "$CD" open --class B --what "fire me" --default "park to backlog + continue" \
        --deadline "2000-01-01T00:00:00Z")
  run bash "$CD" expire-sweep
  [ "$status" -eq 0 ]
  # reports the fired default line for the caller to act on
  echo "$output" | grep -q "$id"
  echo "$output" | grep -q "park to backlog + continue"
  run jq -r '.status' "$CC_DECISIONS_DIR/$id.json"
  [ "$output" = "expired-actioned" ]
}

@test "expire-sweep leaves a NOT-yet-past class-B open (no premature fire)" {
  id=$(bash "$CD" open --class B --what "future" --default "d" --deadline "2099-01-01T00:00:00Z")
  run bash "$CD" expire-sweep
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "$id" || false
  run jq -r '.status' "$CC_DECISIONS_DIR/$id.json"
  [ "$output" = "open" ]
}

@test "expire-sweep NEVER fires a class-C default (C waits; it has no deadline)" {
  id=$(bash "$CD" open --class C --what "waits forever" --staged-artifact /tmp/x.sh)
  run bash "$CD" expire-sweep
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "$id" || false
  run jq -r '.status' "$CC_DECISIONS_DIR/$id.json"
  [ "$output" = "open" ]
}

# ── inv7: no age-deletion of an OPEN packet ────────────────────────────────────
@test "inv7: expire-sweep never DELETES a packet file — open packets remain on disk" {
  idb=$(bash "$CD" open --class B --what "past" --default "d" --deadline "2000-01-01T00:00:00Z")
  idc=$(bash "$CD" open --class C --what "waits" --staged-artifact /tmp/y.sh)
  bash "$CD" expire-sweep >/dev/null
  [ -f "$CC_DECISIONS_DIR/$idb.json" ]   # transitioned, NOT deleted
  [ -f "$CC_DECISIONS_DIR/$idc.json" ]   # untouched open, NOT deleted
}

# ── status FOLD: an absent/empty .status reads as "open" ───────────────────────
# Every status predicate is a jq `select`, so a packet with no `.status` DROPS OUT with a zero exit
# — absent from the board rather than flagged, the wrong polarity for an operator queue. Six live
# `shipland-esc-*` packets written directly by scripts/ship-land.sh (bypassing `open`) carried no
# `.status` and were invisible to `list --open`, autonomy-sweep, cc-digest and operator-readout.
# The producer is fixed; the fold is what recovers the LEGACY packets already on disk, without
# rewriting them (inv7: a packet is EVIDENCE, never overwritten to satisfy a view).

# Write a raw packet with NO .status key — exactly what ship-land used to emit.
# NB: the `extra` object is interpolated into the jq PROGRAM, so it must reach jq as bare `{...}`.
# Defaulting it inline as "${3:-\{\}}" does NOT work: inside double quotes bash leaves `\{` intact,
# so jq receives a literal backslash and dies with a compile error — which fails the FIXTURE rather
# than the assertion, and a fixture that cannot build proves nothing about the code under test.
_raw_pkt() {  # $1=id $2=class [$3=extra jq object merged in]
  local extra="${3:-}"
  [ -n "$extra" ] || extra='{}'
  mkdir -p "$CC_DECISIONS_DIR"
  jq -n --arg id "$1" --arg c "$2" \
    '{id:$id, class:$c, what_plain:"legacy packet with no status key",
      options:[], recommendation:"review", default_if_no_veto:null, matched:["a.sql: effect"]}
     + ('"$extra"')' > "$CC_DECISIONS_DIR/$1.json"
  # A fixture is a CLAIM: assert it actually built, so a future quoting slip fails HERE, loudly.
  [ -s "$CC_DECISIONS_DIR/$1.json" ] || { echo "_raw_pkt: fixture build failed for $1" >&2; return 1; }
}

@test "FOLD: a packet with NO .status key is still listed by list --open" {
  # RED-PROOF: pre-fix the predicate was `.status == "open"`, so this row was silently dropped.
  _raw_pkt legacy-nostatus C
  run bash "$CD" list --open
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "legacy-nostatus"
}

@test "FOLD: the status COLUMN renders 'open' for a status-less packet, not the '?' pad" {
  # The TSV padding sweep surfaced the defect by rendering `?` here (which then shifted .class into
  # the status column). The fold must resolve the cell, not just pad it.
  _raw_pkt legacy-col C
  run bash "$CD" list --open
  echo "$output" | grep -q '^open .*legacy-col'
}

@test "FOLD: a present-but-EMPTY .status also reads as open (a bare // is not enough)" {
  # `//` substitutes for null/false ONLY, never for a present empty string — the same trap the CELL
  # prelude documents. A truncated/hand-edited packet with "status":"" must still reach the board.
  _raw_pkt legacy-empty C '{status:""}'
  run bash "$CD" list --open
  echo "$output" | grep -q "legacy-empty"
}

@test "FOLD does NOT over-reach: a TERMINAL status stays out of list --open" {
  # The control that makes the fold falsifiable in the other direction. A fold implemented as
  # "treat everything as open" would pass the three tests above and fail here.
  _raw_pkt legacy-actioned C '{status:"actioned"}'
  _raw_pkt legacy-vetoed   C '{status:"vetoed"}'
  run bash "$CD" list --open
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "legacy-actioned" || false
  ! echo "$output" | grep -q "legacy-vetoed"   || false
  # ...but --all still shows them (status is a VIEW; the packet is evidence)
  run bash "$CD" list --all
  echo "$output" | grep -q "legacy-actioned"
}

# ── the guard that makes the FOLD safe (contract guard, not a defect regression) ─
# NB on RED-proof honesty: pre-fix these two cases passed VACUOUSLY — a status-less packet was
# dropped by expire-sweep's `.status == "open"` too, so it could not fire either. They are live only
# once the fold exists, and they pin the pairing: verified by applying the fold WITHOUT the
# `(.veto_deadline // "")` guard, which auto-closes all six live packets against a null default.
@test "FOLD+GUARD: a status-less, deadline-less class-B is NOT auto-fired by expire-sweep" {
  # In jq a MISSING key is `null`, and BOTH `null != ""` and `null < <now>` are TRUE. So folding the
  # status without guarding the deadline would transition a land-block NO HUMAN EVER SAW straight to
  # `expired-actioned`, firing a null default. The fold must make such packets VISIBLE, never CLOSED.
  _raw_pkt legacy-nodeadline B
  run bash "$CD" expire-sweep
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "legacy-nodeadline" || false
  # still on disk and still reported open — parked, awaiting the operator
  run jq -r '.status // "ABSENT"' "$CC_DECISIONS_DIR/legacy-nodeadline.json"
  [ "$output" = "ABSENT" ]
  run bash "$CD" list --open
  echo "$output" | grep -q "legacy-nodeadline"
}

@test "FOLD+GUARD: a status-less class-B with an EMPTY deadline is not fired either" {
  _raw_pkt legacy-emptydeadline B '{veto_deadline:""}'
  run bash "$CD" expire-sweep
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "legacy-emptydeadline" || false
}

@test "FOLD+GUARD: a status-less class-B WITH a past deadline still fires (the fold is live)" {
  # The positive control for the pair: the guard must block only the deadline-LESS case. A packet
  # that genuinely declared a past deadline must still fire its default under the fold — otherwise
  # the guard would have silently disabled expire-sweep for every legacy packet.
  _raw_pkt legacy-pastdeadline B '{veto_deadline:"2000-01-01T00:00:00Z", default_if_no_veto:"park it"}'
  run bash "$CD" expire-sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "legacy-pastdeadline"
  echo "$output" | grep -q "park it"
  run jq -r '.status' "$CC_DECISIONS_DIR/legacy-pastdeadline.json"
  [ "$output" = "expired-actioned" ]
}

# ── veto / action transitions ──────────────────────────────────────────────────
@test "veto transitions open→vetoed; the default then never fires on expire-sweep" {
  id=$(bash "$CD" open --class B --what "vetoed one" --default "d" --deadline "2000-01-01T00:00:00Z")
  bash "$CD" veto "$id" --by operator >/dev/null
  run jq -r '.status' "$CC_DECISIONS_DIR/$id.json"; [ "$output" = "vetoed" ]
  run bash "$CD" expire-sweep
  ! echo "$output" | grep -q "$id" || false
  run jq -r '.status' "$CC_DECISIONS_DIR/$id.json"; [ "$output" = "vetoed" ]
}

@test "action transitions open→actioned with evidence" {
  id=$(bash "$CD" open --class A --what "done one")
  bash "$CD" action "$id" --evidence "commit:abc123" >/dev/null
  run jq -r '.status' "$CC_DECISIONS_DIR/$id.json";   [ "$output" = "actioned" ]
  run jq -r '.evidence' "$CC_DECISIONS_DIR/$id.json"; [ "$output" = "commit:abc123" ]
}

# ── list filters ───────────────────────────────────────────────────────────────
@test "list --class B shows only B packets" {
  bash "$CD" open --class A --what "a-item" >/dev/null
  bash "$CD" open --class B --what "b-item" --default d --deadline 2099-01-01T00:00:00Z >/dev/null
  run bash "$CD" list --class B
  echo "$output" | grep -q "b-item"
  ! echo "$output" | grep -q "a-item"
}
