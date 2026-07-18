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
  ! echo "$output" | grep -q "$id"
  run jq -r '.status' "$CC_DECISIONS_DIR/$id.json"
  [ "$output" = "open" ]
}

@test "expire-sweep NEVER fires a class-C default (C waits; it has no deadline)" {
  id=$(bash "$CD" open --class C --what "waits forever" --staged-artifact /tmp/x.sh)
  run bash "$CD" expire-sweep
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "$id"
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

# ── veto / action transitions ──────────────────────────────────────────────────
@test "veto transitions open→vetoed; the default then never fires on expire-sweep" {
  id=$(bash "$CD" open --class B --what "vetoed one" --default "d" --deadline "2000-01-01T00:00:00Z")
  bash "$CD" veto "$id" --by operator >/dev/null
  run jq -r '.status' "$CC_DECISIONS_DIR/$id.json"; [ "$output" = "vetoed" ]
  run bash "$CD" expire-sweep
  ! echo "$output" | grep -q "$id"
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
