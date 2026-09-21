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
  # PINNED, not inherited. The subject honours LR_STATE_DIR (W5-B) as every reader of its lock
  # already did, so an ambient LR_STATE_DIR in the runner's environment would put the lock outside
  # the fixture and every case here would fail for a reason that is not the subject. The value is
  # the same path the suite has always used, so nothing about these cases changes.
  export LR_STATE_DIR="$HOME/.reso/limit-recover"
  mkdir -p "$HOME/.reso/limit-recover/locks" "$T/from/projects/slug" "$T/to/projects/slug" \
           "$T/other/projects/slug" "$T/third/projects/slug"
  SID=11111111-2222-3333-4444-555555555555
  SRC="$T/from/projects/slug/$SID.jsonl"
  DST="$T/to/projects/slug/$SID.jsonl"
  THIRD="$T/third/projects/slug/$SID.jsonl"
  LOCK="$HOME/.reso/limit-recover/locks/$SID.lock"
  printf '{"type":"assistant","message":{"role":"assistant"}}\n' > "$SRC"
  LRT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/limit-recover/lr-transplant.sh"
  IV="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/limit-recover/lr-ingest-verify.sh"
}

_transplant() { run bash "$LRT" --sid "$SID" --from "$T/from" --to "$T/to" "$@"; }
# the SECOND hop: off the store the first one landed on
_hop2() { run bash "$LRT" --sid "$SID" --from "$T/to" --to "$T/third"; }
_lockf() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$LOCK" "$1"; }
_lockchain() { python3 -c 'import json,sys;print(" ".join(json.load(open(sys.argv[1])).get("chain") or []))' "$LOCK"; }

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

# ══ W5-B — CUSTODY: A RE-LIMITED TARGET CAN BE MOVED AGAIN ═══════════════════════════════════════
# The five cases above answer "has THIS move already happened". None of them could answer "may this
# session move ON", and that is the state a SECOND limit produces: A→B lands, B hits its own limit
# hours later, and `--from B --to C` was refused twice over — once as a split brain naming B, and
# again by the bare lock-existence check further down. The lock now records CUSTODY: `owner` is the
# store holding the session now, `chain` every store it has passed through, `ts_first` the first
# claim's timestamp. A move whose --from IS the current owner is a hop; everything else still
# refuses, and the four pinned behaviours above are unchanged.

@test "transplant: a RE-LIMITED target can be moved ON — the second hop is not a split brain" {
  _transplant
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  _hop2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$THIRD" ] || { echo "the second hop copied nothing"; false; }
  [ -f "$DST.handed-off" ] || { echo "the intermediate source was not retired"; false; }
  [ "$(_lockf owner)" = "$T/third" ] || { echo "owner is $(_lockf owner)"; false; }
  [ "$(_lockf to)" = "$T/third" ] || { echo "to is $(_lockf to)"; false; }
  # the chain carries all three stores, in the order they were visited
  [[ "$(_lockchain)" == *"/from "*"/to "*"/third" ]] || { echo "chain: $(_lockchain)"; false; }
  # and the RECEIPT carries it too: lr-handoff.sh:825 writes this stdout verbatim into the bundle's
  # transplant.json, which outlives the lock (locks are transient on this box — lr-lib.sh:528-536).
  [[ "$output" == *'"hop":2'* ]] || { echo "the receipt does not say which hop this was: $output"; false; }
  [[ "$output" == *'"chain":['* ]] || { echo "the receipt carries no chain: $output"; false; }
  [[ "$output" == *'"ts_first":'* ]] || { echo "the receipt carries no origin timestamp: $output"; false; }
}

@test "transplant: a THIRD hop keeps the WHOLE chain — the origin store is not dropped" {
  # Two hops can be reconstructed from a lock's own from+to, so a 2-hop fixture cannot tell a real
  # chain read from the pre-W5-B fallback. Three can: the origin survives only if the recorded
  # chain is actually read forward.
  mkdir -p "$T/fourth/projects/slug"
  _transplant; [ "$status" -eq 0 ] || { echo "$output"; false; }
  _hop2;       [ "$status" -eq 0 ] || { echo "$output"; false; }
  run bash "$LRT" --sid "$SID" --from "$T/third" --to "$T/fourth"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(_lockchain)" == *"/from "*"/to "*"/third "*"/fourth" ]] \
    || { echo "the chain lost a store: $(_lockchain)"; false; }
  [[ "$output" == *'"hop":3'* ]] || { echo "$output"; false; }
}

@test "transplant: the hop keeps ts_first and REFRESHES ts — a fresh claim is not born stale" {
  # bin/cc-limited:969 reads `ts` as the age of the claim (NOW - ts <= CLAIM_GRACE_S ⇒ in grace).
  # Carrying the first hop's ts forward would render a healthy in-flight second recovery as an
  # overdue claim the instant it was taken. ts_first is the field that remembers the origin.
  _transplant
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # TWO DISTINCT STAMPS, and COMPACT json. Distinct, because with one value the "keep ts_first" and
  # "fall back to ts" reads are indistinguishable and a mutant dropping either survives. Compact,
  # because every reader of this lock in the fleet — lr-transplant.sh, lr-lib.sh:514,
  # lr-fire-resume.sh:259 — matches the literal `"to":"`, so a pretty-printed lock (json.dumps'
  # default `", "` separators) is invisible to all three. Nothing may ever reformat this file.
  python3 - "$LOCK" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["ts_first"] = "2020-01-01T00:00:00Z"
d["ts"] = "2021-06-06T06:06:06Z"
open(p, "w").write(json.dumps(d, separators=(",", ":")) + "\n")
PY
  _hop2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(_lockf ts_first)" = "2020-01-01T00:00:00Z" ] \
    || { echo "ts_first was not carried forward: $(_lockf ts_first)"; false; }
  [ "$(_lockf ts)" != "2020-01-01T00:00:00Z" ] \
    || { echo "ts was not refreshed — a live claim is born outside its grace window"; false; }
  [ "$(_lockf ts)" != "2021-06-06T06:06:06Z" ] \
    || { echo "ts is the PREVIOUS claim's stamp, not this one's"; false; }
}

@test "transplant: a PRE-W5-B lock (no owner, no chain) still hops, and the chain is reconstructed" {
  # Every lock on disk today was written by the old writer. The hop must read one, and the chain it
  # reconstructs must not silently lose the origin store.
  cp "$SRC" "$DST"
  mv "$SRC" "$SRC.handed-off"
  printf '{"sid":"%s","from":"%s","to":"%s","ts":"2026-09-19T00:00:00Z","pid":1,"host":"h"}\n' \
    "$SID" "$T/from" "$T/to" > "$LOCK"
  _hop2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(_lockf owner)" = "$T/third" ] || { echo "owner is $(_lockf owner)"; false; }
  [[ "$(_lockchain)" == *"/from "*"/to "*"/third" ]] || { echo "chain lost a store: $(_lockchain)"; false; }
  [ "$(_lockf ts_first)" = "2026-09-19T00:00:00Z" ] \
    || { echo "the legacy lock's ts is the origin timestamp: $(_lockf ts_first)"; false; }
}

@test "transplant: a hop whose --from reaches the owner through a SYMLINK is still a hop" {
  # Not theoretical: ~/.claude-next/projects is a symlink to ~/.claude/projects on this box, so a
  # LOGICAL --from compared against the realpathed lock target misses and the hop is refused.
  _transplant
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  ln -s "$T/to" "$T/to-link"
  run bash "$LRT" --sid "$SID" --from "$T/to-link" --to "$T/third"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$THIRD" ] || { echo "the hop through the symlink copied nothing"; false; }
}

@test "transplant: a STRANGER --from is still refused, and the refusal names the hop that would work" {
  # The half that keeps the widening bounded, and the half that makes the refusal actionable:
  # "recover it at its CURRENT target" is unactionable when the current target is the store that
  # just hit its own limit, which is the whole reason this session is being moved.
  printf '{"sid":"%s","from":"%s","to":"%s","owner":"%s"}\n' "$SID" "$T/from" "$T/other" "$T/other" > "$LOCK"
  _transplant
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"already transplanted to"* ]] || { echo "$output"; false; }
  [[ "$output" == *"--from $T/other"* ]] || { echo "the refusal names no way forward: $output"; false; }
}

@test "transplant: OWNER is the authority on custody, the legacy to field is only its fallback" {
  # Both fields are written together on every hop and always agree, so this is the only shape that
  # can tell the two readers apart: a lock whose `to` was left behind while `owner` names the store
  # that actually holds the session. Reading `to` here refuses a retry that already happened.
  cp "$SRC" "$DST"
  printf '{"sid":"%s","from":"%s","to":"%s","owner":"%s","ts":"2026-09-19T00:00:00Z"}\n' \
    "$SID" "$T/from" "$T/other" "$T/to" > "$LOCK"
  _transplant
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *'"already_transplanted":true'* ]] || { echo "$output"; false; }
}

@test "transplant: the lock is written where every READER looks — LR_STATE_DIR, not a hardcoded HOME" {
  # lr-lib.sh:511, lr-fire-resume.sh:244, lr-fleet.sh:69, bin/cc-limited:88 and
  # hooks/recover-inject.sh:55 all resolve this directory through LR_STATE_DIR. The WRITER was the
  # one place that hardcoded $HOME, so a fleet run with LR_STATE_DIR set wrote locks nothing read.
  LR_STATE_DIR="$T/altstate" run bash "$LRT" --sid "$SID" --from "$T/from" --to "$T/to"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$T/altstate/locks/$SID.lock" ] || { echo "no lock under LR_STATE_DIR"; false; }
  [ ! -e "$LOCK" ] || { echo "the lock also landed in the hardcoded HOME path"; false; }
}

@test "transplant: the source is retired even with CLAUDE_CODE_SESSION_ID UNSET — SF-j refuted" {
  # PLAN_DRAFT § W5's acceptance item SF-j asserts the opposite: that the rename is SKIPPED under
  # `env -u CLAUDE_CODE_SESSION_ID`, yielding source_retired:0, and calls it "red today". The guard
  # reads "${CLAUDE_CODE_SESSION_ID:-}" != "$SID", so an unset variable expands to "" — which is not
  # the sid — and the rename runs. Executed against the tree 2026-09-20: source_retired:1. The one
  # condition that DOES skip it is the live session driving its own move, pinned below it.
  run env -u CLAUDE_CODE_SESSION_ID bash "$LRT" --sid "$SID" --from "$T/from" --to "$T/to"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *'"source_retired":1'* ]] || { echo "$output"; false; }
  [ -f "$SRC.handed-off" ] || { echo "the source was not retired"; false; }

  rm -f "$LOCK" "$DST"; mv "$SRC.handed-off" "$SRC"
  run env CLAUDE_CODE_SESSION_ID="$SID" bash "$LRT" --sid "$SID" --from "$T/from" --to "$T/to"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *'"source_retired":0'* ]] || { echo "$output"; false; }
  [ -f "$SRC" ] || { echo "the LIVE session's own transcript was renamed under it"; false; }
}

# ── THE LOCK'S CONSUMER: lr-ingest-verify clause C3 ───────────────────────────────────────────────
# C3 asserts the lock names the bundle's target by exact string equality. Rewriting `to` in place on
# a hop fails the FIRST hop's bundle forever — a bundle that was correct when it was cut. The clause
# is extracted and run in isolation rather than through a whole bundle fixture: tests/lr-ingest-
# verify.bats owns the bundle-level cases and this wave owns C3 alone. The extraction is asserted
# non-empty, so a refactor of that block fails loudly here instead of silently testing nothing.
_c3() { # $1 = the manifest's target_cfg → the clause line the SHIPPED C3 block prints for $LOCK
  {
    echo 'clause() { printf "%s %s %s\n" "$1" "$2" "$3"; }'
    printf 'LOCK=%q\nTCFG_M=%q\n' "$LOCK" "$1"
    sed -n '/^if \[ ! -r "\$LOCK" \]; then clause FAIL C3/,/^fi$/p' "$IV"
  } > "$T/c3.sh"
  [ "$(grep -c . "$T/c3.sh")" -ge 8 ] || { echo "the C3 extraction from $IV came back empty or truncated"; return 1; }
  bash "$T/c3.sh"
}

@test "C3: the FIRST hop's bundle still verifies after the session moves on — the chain is the key" {
  _transplant; [ "$status" -eq 0 ] || { echo "$output"; false; }
  _hop2;       [ "$status" -eq 0 ] || { echo "$output"; false; }
  run _c3 "$T/to"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == PASS\ C3\ * ]] || { echo "$output"; false; }
  [[ "$output" == *"EARLIER hop"* ]] || { echo "$output"; false; }
}

@test "C3 CONTROL: a store the session was NEVER on is still the split brain C3 exists to catch" {
  _transplant; [ "$status" -eq 0 ] || { echo "$output"; false; }
  _hop2;       [ "$status" -eq 0 ] || { echo "$output"; false; }
  run _c3 "$T/other"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == FAIL\ C3\ * ]] || { echo "$output"; false; }
  [[ "$output" == *"says to="* ]] || { echo "the FAIL text tests/lr-ingest-verify.bats pins has changed: $output"; false; }
}

@test "C3 CONTROL: the CURRENT owner still passes on the plain equality arm, not the chain arm" {
  _transplant; [ "$status" -eq 0 ] || { echo "$output"; false; }
  _hop2;       [ "$status" -eq 0 ] || { echo "$output"; false; }
  run _c3 "$T/third"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == PASS\ C3\ * ]] || { echo "$output"; false; }
  [[ "$output" != *"EARLIER hop"* ]] || { echo "the plain arm was bypassed: $output"; false; }
}
