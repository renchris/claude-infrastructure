#!/usr/bin/env bats
# lr-transplant.sh — SAME-TARGET IDEMPOTENCE (W11, LIMIT_RECOVER_100P § 10).
#
# WHY THIS SUITE EXISTS. W11 stops prescribing a hand-spawned `recover-<sid8>` window when an
# in-place recycle fails after the transplant has already completed (handoff-fire rc 4), and
# prescribes a RETRY of the whole recovery instead. Four of those hand-spawned windows were made on
# 2026-09-19: no --var provenance, no registry row, no watcher — nothing on the box could prove or
# retire them. A retry is only the right prescription if the transplant leg is a no-op the second
# time, so that property needs pinning in both directions.
#
# 🚨 THE SHAPE THE RETRY ACTUALLY HAS. The plan named two refusal sites ("$DST already exists" and
# "lock exists") and a retry after a SUCCESSFUL transplant reaches NEITHER: the source is renamed
# `<sid>.jsonl.handed-off` whenever the driver is not the session itself, so the glob finds nothing
# and the run dies at "no transcript". That is the case test 2 pins, and it is the one that matters.

setup() {
  T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"
  mkdir -p "$HOME/.reso/limit-recover/locks" "$T/from/projects/slug" "$T/to/projects/slug" "$T/other/projects/slug"
  SID=11111111-2222-3333-4444-555555555555
  SRC="$T/from/projects/slug/$SID.jsonl"
  DST="$T/to/projects/slug/$SID.jsonl"
  LOCK="$HOME/.reso/limit-recover/locks/$SID.lock"
  printf '{"type":"assistant","message":{"role":"assistant"}}\n' > "$SRC"
  LRT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/limit-recover/lr-transplant.sh"
}

_transplant() { run bash "$LRT" --sid "$SID" --from "$T/from" --to "$T/to" "$@"; }

@test "transplant: the first run moves it and retires the source" {
  _transplant
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$DST" ] || { echo "target copy missing"; false; }
  [ -f "$SRC.handed-off" ] || { echo "source not retired"; false; }
  [ -f "$LOCK" ] || { echo "no lock"; false; }
}

@test "transplant: a SAME-TARGET retry is rc 0 and moves nothing — the rc-4 retry path" {
  # THE RED-PROOF. Before W11 this second run exited 2 with "no transcript ... under /from/projects",
  # because the first run renamed the source — so `lr-fleet.sh --one` could not re-drive a recovery
  # whose recycle had failed, and the only prescription left was a hand-spawned window.
  _transplant
  [ "$status" -eq 0 ]
  local before; before="$(shasum -a 256 "$DST" | cut -d' ' -f1)"
  _transplant
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *'"already_transplanted":true'* ]] || { echo "$output"; false; }
  [[ "$output" == *'"target_transcript"'* ]] || { echo "$output"; false; }
  # nothing moved
  [ "$(shasum -a 256 "$DST" | cut -d' ' -f1)" = "$before" ] || { echo "the target copy CHANGED"; false; }
}

@test "transplant: a lock naming a DIFFERENT target still refuses, and NAMES the split brain" {
  # The half that keeps the widening bounded. It must refuse, and it must not refuse by claiming the
  # transcript is missing — that is true after the source is retired, and points at the wrong
  # subject, which is what costs a round trip.
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SID" "$T/from" "$T/other" > "$LOCK"
  _transplant
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"already transplanted to"* ]] || { echo "$output"; false; }
  [[ "$output" != *"no transcript"* ]] || { echo "refused for the WRONG reason: $output"; false; }
}

@test "transplant: --force still overrides a same-target lock" {
  _transplant
  [ "$status" -eq 0 ]
  # restore a source so --force has something to copy
  mv "$SRC.handed-off" "$SRC"
  _transplant --force
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *'"already_transplanted":true'* ]] || { echo "--force took the idempotent path: $output"; false; }
}

@test "transplant: a TRUNCATED target is not a finished transplant — no ok over a short copy" {
  # Completeness, not mere existence. The successor appends to the target after the transplant, so
  # the two are legitimately unequal and only "at least as much" is meaningful — but a target with
  # LESS than the source is a half-finished copy, and returning ok over one strands the tail.
  printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' >> "$SRC"
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SID" "$T/from" "$T/to" > "$LOCK"
  printf 'x\n' > "$DST"
  _transplant
  [ "$status" -ne 0 ] || { echo "accepted a truncated target: $output"; false; }
  [[ "$output" != *'"already_transplanted":true'* ]] || { echo "$output"; false; }
}
