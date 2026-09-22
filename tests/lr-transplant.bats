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
# `<sid>.jsonl.handed-off` once a caller has asserted the source is quiesced, so the glob finds
# nothing and the run dies at "no transcript". That is the case test 2 pins, and it is the one that
# matters.
#
# ══ VOLUNTARY ACCOUNT SWITCH — D2 / D3 / DEC-3 (2026-09-22) ══════════════════════════════════════
# Three behaviours were added and TWO PINS WERE DELIBERATELY REMOVED. Both removed pins asserted the
# defect D3 names, so they could not survive its fix and were un-pinned rather than worked around:
#
#   1. "the first run moves it and retires the source" asserted `$SRC.handed-off` after a plain run
#      driven by the test harness — i.e. by a driver that is not the subject. That is exactly the
#      rename D3 forbids. The case is REPLACED IN PLACE by the D3 red proof, which asserts the
#      opposite on the same invocation.
#   2. "the source is retired even with CLAUDE_CODE_SESSION_ID UNSET — SF-j refuted" pinned the
#      DRIVER-identity guard as correct. Its measurement was true and its conclusion has been
#      overtaken: the guard answers "is the driver the subject", and D3 is the finding that this is
#      not the question. The case is rewritten to pin what survives — the LIVE-SELF arm, which still
#      keeps the source — and its history is kept in the body.
#
# Two further assertions were dropped for the same reason, each inside a case whose real subject is
# custody, not retirement: `-f "$DST.handed-off"` in the second-hop case, and the two `mv
# …handed-off …` lines that restored a source for the --force cases (there is nothing to restore
# now, because nothing was renamed).
#
# ONLY D2 AND D3 ADMIT RED PROOFS. Every custody/idempotence case below passes against both the
# pre-fix and the post-fix subject and is labelled EQUIVALENCE GUARD where it sits; a test green on
# both a subject and its mutant proves nothing about either.

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
_admit()   { run bash "$LRT" --phase admit   --sid "$SID" --from "$T/from" --to "$T/to"; }
_confirm() { run bash "$LRT" --phase confirm --sid "$SID" --from "$T/from" --to "$T/to" "$@"; }
# the SECOND hop: off the store the first one landed on
_hop2() { run bash "$LRT" --sid "$SID" --from "$T/to" --to "$T/third"; }
_lockf() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$LOCK" "$1"; }
_lockchain() { python3 -c 'import json,sys;print(" ".join(json.load(open(sys.argv[1])).get("chain") or []))' "$LOCK"; }

# A PRIVATE fixture per arm, so the three runs of the cause-invariance case cannot see each other's
# lock — two arms sharing a state dir would make the second one the IDEMPOTENT path and the
# comparison would be between a real move and a no-op (and would pass for the wrong reason).
_cause_artifacts() { # <label> [args…] → the receipt, the lock and the tombstone this move produced
  local label="$1"; shift
  local d="$T/cz-$label"
  mkdir -p "$d/from/projects/slug" "$d/to/projects/slug" "$d/state/locks"
  printf '{"type":"assistant","message":{"role":"assistant"}}\n' > "$d/from/projects/slug/$SID.jsonl"
  LR_STATE_DIR="$d/state" bash "$LRT" --sid "$SID" --from "$d/from" --to "$d/to" "$@"
  cat "$d/state/locks/$SID.lock"
  cat "$d/from/projects/slug/$SID.HANDOFF.json"
}
_cause_normalise() { # strip the arm's own fixture path and the three fields that are volatile BY DESIGN
  sed -e "s#$T/cz-[a-z]*#FIXTURE#g" \
      -e 's/"ts":"[^"]*"/"ts":"T"/g' \
      -e 's/"ts_first":"[^"]*"/"ts_first":"T"/g' \
      -e 's/"pid":[0-9]*/"pid":0/g' \
      -e 's/,"cause":"[a-z]*"//g'
}

@test "transplant: D3 RED PROOF — a driver that is not the subject must NOT rename the source" {
  # A RED PROOF, not an equivalence guard. Against the PRE-FIX subject this case fails on the
  # `[ -f "$SRC" ]` line: the guard read the DRIVER's CLAUDE_CODE_SESSION_ID, which under bats is
  # unset and therefore != $SID, so `mv "$SRC" "$SRC.handed-off"` ran. A third pane moving a HEALTHY
  # session takes that same branch and renames, by path, a transcript the harness is still appending
  # to. The copy, the lock and the tombstone are all still produced — only the rename is withheld.
  _transplant
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$DST" ] || { echo "target copy missing"; false; }
  [ -f "$LOCK" ] || { echo "no lock"; false; }
  [ -f "$T/from/projects/slug/$SID.HANDOFF.json" ] || { echo "no tombstone"; false; }
  [ -f "$SRC" ] || { echo "the source transcript was RENAMED by a driver that is not the subject"; false; }
  [ ! -e "$SRC.handed-off" ] || { echo "the source was retired with nothing asserting it is quiesced"; false; }
  [[ "$output" == *'"source_retired":0'* ]] || { echo "$output"; false; }
  [[ "$output" == *'"source_retired_reason":"unasserted-quiesce"'* ]] || { echo "$output"; false; }
  # and it SAYS so — a silent skip is how the opposite defect went unnoticed for as long as it did
  [[ "$output" == *"NOT retired"* ]] || { echo "the skip is not reported: $output"; false; }
  [[ "$output" == *"--phase confirm"* ]] || { echo "the report names no way forward: $output"; false; }
}

@test "transplant: D2 RED PROOF — bytes appended between admit and confirm reach the destination" {
  # A RED PROOF. Against the PRE-FIX subject there is no `--phase`, so the confirm call is rejected
  # at the argument parser; with the phase flags stubbed out of the brief entirely, the equivalent
  # single-shot run copies at admit time and the appended line never reaches the target — which is
  # the defect: the sha check passes because it already ran, and the successor resumes a transcript
  # whose tail is orphaned in the retired store.
  _admit
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$SRC" ] || { echo "admit retired the source — admit must NEVER retire"; false; }
  [[ "$output" == *'"source_retired_reason":"admit-phase"'* ]] || { echo "$output"; false; }

  # the source keeps working, exactly as a healthy session does until /exit lands
  printf '{"type":"assistant","message":{"role":"assistant","content":"THE TAIL"}}\n' >> "$SRC"

  _confirm
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q 'THE TAIL' "$DST" \
    || { echo "the destination holds only the pre-append content: $(cat "$DST")"; false; }
  [ "$(shasum -a 256 "$SRC.handed-off" | cut -d' ' -f1)" = "$(shasum -a 256 "$DST" | cut -d' ' -f1)" ] \
    || { echo "the retired source and the destination are not byte-identical"; false; }
  [[ "$output" == *'"source_retired":1'* ]] || { echo "$output"; false; }
  [[ "$output" == *'"source_retired_reason":"confirm"'* ]] || { echo "$output"; false; }
  [[ "$output" == *'"phase":"confirm"'* ]] || { echo "the receipt does not name its phase: $output"; false; }
}

@test "transplant: confirm is IDEMPOTENT — a source it already retired is rc 0, not a lost transcript" {
  # Confirm's own success renames the source, so a re-run finds no `<sid>.jsonl` at all. That is the
  # exact shape the W11 retry trap has, one phase later, and it must not be an error: the state the
  # caller asked for is the state on disk.
  _admit;   [ "$status" -eq 0 ] || { echo "$output"; false; }
  _confirm; [ "$status" -eq 0 ] || { echo "$output"; false; }
  _confirm
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *'"already_confirmed":true'* ]] || { echo "$output"; false; }
  [[ "$output" == *'"source_retired":1'* ]] || { echo "$output"; false; }
  [ -f "$SRC.handed-off" ] || { echo "the retired source went missing"; false; }
}

@test "transplant: confirm runs UNDER the admit's lock — it re-acquires nothing and refuses nothing" {
  # The two refusal sites admit itself arms ("$DST already exists", "lock exists") would each refuse
  # the confirm call if it took the ordinary path. It must not, and it must not be made to pass by
  # --force either, which would also override the split-brain protection this lock exists for.
  _admit; [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$LOCK" ] || { echo "admit wrote no lock"; false; }
  local lock_before; lock_before="$(cat "$LOCK")"
  _confirm
  [ "$status" -eq 0 ] || { echo "confirm was refused under its own admit's lock: $output"; false; }
  [[ "$output" != *"REFUSED"* ]] || { echo "$output"; false; }
  [ "$(cat "$LOCK")" = "$lock_before" ] || { echo "confirm rewrote the custody lock"; false; }
}

@test "transplant: confirm REFUSES when the source vanished between the phases" {
  # The other half of the idempotence arm, and the reason it cannot simply return ok on an absent
  # source: no transcript AND no retired copy is a source that disappeared mid-flight, which is a
  # FATAL a caller must not read as "the move completed".
  _admit; [ "$status" -eq 0 ] || { echo "$output"; false; }
  rm -f "$SRC"
  _confirm
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"vanished"* ]] || { echo "$output"; false; }
}

@test "transplant: --phase and --cause answer the USAGE rc (3), not the REFUSED rc (2)" {
  # rc 3 is usage, rc 2 is REFUSED-with-nothing-created (A07 item 11). A mistyped flag value is the
  # former; conflating them would tell a caller its request was declined when it was never made.
  run bash "$LRT" --phase bogus --sid "$SID" --from "$T/from" --to "$T/to"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  run bash "$LRT" --cause bogus --sid "$SID" --from "$T/from" --to "$T/to"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  run bash "$LRT" --sid "$SID" --from "$T/from" --to "$T/to" --phase
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ ! -e "$LOCK" ] || { echo "a usage error left a lock behind"; false; }
  [ ! -e "$DST" ] || { echo "a usage error left a target copy behind"; false; }
}

@test "transplant: --keep-source still keeps the source through a confirm" {
  # --keep-source is the OTHER explicit caller assertion, and confirm must not outrank it: the phase
  # says "the subject is quiesced", the flag says "leave the source where it is". Both are the
  # caller's, and the narrower one wins.
  _admit;  [ "$status" -eq 0 ] || { echo "$output"; false; }
  _confirm --keep-source
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$SRC" ] || { echo "confirm retired a source the caller asked to keep"; false; }
  [[ "$output" == *'"source_retired_reason":"keep-source"'* ]] || { echo "$output"; false; }
}

# ══ DEC-3 — `cause` is a FIELD, never a state token ══════════════════════════════════════════════

@test "cause: the field lands on the receipt, the lock and the tombstone — and is OMITTED when unasked" {
  _transplant --cause voluntary
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *'"cause":"voluntary"'* ]] || { echo "$output"; false; }
  grep -q '"cause":"voluntary"' "$LOCK" || { echo "lock: $(cat "$LOCK")"; false; }
  grep -q '"cause":"voluntary"' "$T/from/projects/slug/$SID.HANDOFF.json" \
    || { echo "tombstone: $(cat "$T/from/projects/slug/$SID.HANDOFF.json")"; false; }
  # ABSENT, not defaulted. This is what keeps every record byte-identical to the pre-change shape for
  # the callers that pass no cause — and three readers in the fleet match this lock by literal string.
  rm -f "$LOCK" "$DST" "$T/from/projects/slug/$SID.HANDOFF.json"
  _transplant
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *'"cause"'* ]] || { echo "the receipt defaulted a cause: $output"; false; }
  if grep -q '"cause"' "$LOCK"; then echo "the lock defaulted a cause: $(cat "$LOCK")"; false; fi
  if grep -q '"cause"' "$T/from/projects/slug/$SID.HANDOFF.json"; then
    echo "the tombstone defaulted a cause"; false
  fi
}

@test "cause: NEGATIVE INVARIANT — nothing branches on it, so limit and voluntary are the same run" {
  # THE INVARIANT DEC-3 IS FOR. `cause` exists to gate D1 in another file and to make an artifact
  # readable weeks later; a STATE value would fall into klass()'s permissive `return "run"` default
  # and render as in-flight forever. The behavioural form is the strong one: run the same move three
  # times under three causes into private fixtures, strip the field itself, and require every
  # remaining byte of the receipt, the lock and the tombstone to match. A mutant that branches on
  # cause anywhere — a different chain, a different retirement, a different refusal — dies here.
  local a b c
  a="$(_cause_artifacts limitcz --cause limit | _cause_normalise)"
  b="$(_cause_artifacts voluncz --cause voluntary | _cause_normalise)"
  c="$(_cause_artifacts nonecz | _cause_normalise)"
  [ -n "$a" ] || { echo "the artifact capture came back empty"; false; }
  [ "$a" = "$b" ] || { echo "limit vs voluntary:"; diff <(echo "$a") <(echo "$b") || true; false; }
  [ "$a" = "$c" ] || { echo "cause vs no cause:"; diff <(echo "$a") <(echo "$c") || true; false; }
}

@test "cause: NEGATIVE INVARIANT — the state predicate klass() does not read it" {
  # The other half, at the consumer. bin/cc-lr's klass() is the state predicate A06 names: it maps a
  # state token to ok/bad/run and defaults to "run". This asserts the extraction is non-empty first,
  # so a refactor of klass() fails LOUDLY here instead of silently testing nothing.
  local repo; repo="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  sed -n '/function klass(/,/^    }$/p' "$repo/bin/cc-lr" > "$T/klass.txt"
  [ "$(grep -c . "$T/klass.txt")" -ge 4 ] \
    || { echo "klass() could not be extracted from bin/cc-lr — re-anchor this control"; false; }
  grep -q 'return "run"' "$T/klass.txt" \
    || { echo "the extracted block is not klass(): $(cat "$T/klass.txt")"; false; }
  if grep -qi 'cause' "$T/klass.txt"; then
    echo "a state predicate reads cause — DEC-3 says it is a FIELD, never a state token"
    cat "$T/klass.txt"
    false
  fi
}

@test "transplant: a SAME-TARGET retry is rc 0 and moves nothing — the rc-4 retry path" {
  # EQUIVALENCE GUARD — green against the pre-fix subject too; it pins custody/idempotence, not D2 or D3.
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
  # EQUIVALENCE GUARD — green against the pre-fix subject too; it pins custody/idempotence, not D2 or D3.
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
  # EQUIVALENCE GUARD — passes against the pre-fix and post-fix subject alike. (The `mv
  # "$SRC.handed-off" "$SRC"` that used to restore a source here is gone: under D3 a plain run
  # retires nothing, so the source was never renamed and there is nothing to put back.)
  _transplant
  [ "$status" -eq 0 ]
  _transplant --force
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *'"already_transplanted":true'* ]] || { echo "--force took the idempotent path: $output"; false; }
}

@test "transplant: a TRUNCATED target is not a finished transplant — no ok over a short copy" {
  # EQUIVALENCE GUARD — green against the pre-fix subject too; it pins custody/idempotence, not D2 or D3.
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
  # EQUIVALENCE GUARD — the subject here is CUSTODY, and every assertion below held before D3 too.
  # UN-PINNED: `[ -f "$DST.handed-off" ]` ("the intermediate source was not retired"). A hop driven
  # by a third party is precisely the case D3 forbids from renaming, and the retirement it asserted
  # now belongs to `--phase confirm`, which the D2 red proof owns.
  _transplant
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  _hop2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$THIRD" ] || { echo "the second hop copied nothing"; false; }
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
  # EQUIVALENCE GUARD — green against the pre-fix subject too; it pins custody/idempotence, not D2 or D3.
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
  # EQUIVALENCE GUARD — green against the pre-fix subject too; it pins custody/idempotence, not D2 or D3.
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
  # EQUIVALENCE GUARD — green against the pre-fix subject too; it pins custody/idempotence, not D2 or D3.
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
  # EQUIVALENCE GUARD — green against the pre-fix subject too; it pins custody/idempotence, not D2 or D3.
  # Not theoretical: ~/.claude-next/projects is a symlink to ~/.claude/projects on this box, so a
  # LOGICAL --from compared against the realpathed lock target misses and the hop is refused.
  _transplant
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  ln -s "$T/to" "$T/to-link"
  run bash "$LRT" --sid "$SID" --from "$T/to-link" --to "$T/third"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$THIRD" ] || { echo "the hop through the symlink copied nothing"; false; }
  # AND the custody record must not keep the alias. The chain is compared BY STRING — by the hop
  # test on the next move, and by lr-ingest-verify's C3 — so an alias recorded here is a store the
  # next reader cannot match. This is the assertion that makes `pwd -P` at :30 load-bearing: the
  # comparison itself is already sound (both sides go through lrt_rp), so without this the binding
  # could be reverted and the whole suite would stay green.
  [ "$(_lockf from)" = "$(cd "$T/to" && pwd -P)" ] \
    || { echo "the lock recorded a symlink alias as the source store: $(_lockf from)"; false; }
}

@test "transplant: a STRANGER --from is still refused, and the refusal names the hop that would work" {
  # EQUIVALENCE GUARD — green against the pre-fix subject too; it pins custody/idempotence, not D2 or D3.
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
  # EQUIVALENCE GUARD — green against the pre-fix subject too; it pins custody/idempotence, not D2 or D3.
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
  # EQUIVALENCE GUARD — green against the pre-fix subject too; it pins custody/idempotence, not D2 or D3.
  # lr-lib.sh:511, lr-fire-resume.sh:244, lr-fleet.sh:69, bin/cc-limited:88 and
  # hooks/recover-inject.sh:55 all resolve this directory through LR_STATE_DIR. The WRITER was the
  # one place that hardcoded $HOME, so a fleet run with LR_STATE_DIR set wrote locks nothing read.
  LR_STATE_DIR="$T/altstate" run bash "$LRT" --sid "$SID" --from "$T/from" --to "$T/to"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$T/altstate/locks/$SID.lock" ] || { echo "no lock under LR_STATE_DIR"; false; }
  [ ! -e "$LOCK" ] || { echo "the lock also landed in the hardcoded HOME path"; false; }
}

@test "transplant: the LIVE session driving its own move still keeps its transcript" {
  # EQUIVALENCE GUARD — green against the pre-fix subject too; it pins custody/idempotence, not D2 or D3.
  # ⚠️ UN-PINNED AND REWRITTEN. This case was "the source is retired even with
  # CLAUDE_CODE_SESSION_ID UNSET — SF-j refuted": it ran `env -u CLAUDE_CODE_SESSION_ID`, asserted
  # `source_retired:1`, and recorded the measurement that refuted PLAN_DRAFT § W5's SF-j. The
  # MEASUREMENT was right and is kept here; its CONCLUSION has been overtaken. The guard it
  # certified answers "is the driver the subject", and D3 is the finding that this is not the
  # question a rename may rest on — an unset driver id says nothing at all about whether the SUBJECT
  # is still writing. The retired-under-an-unset-driver arm is now the D3 red proof at the top of
  # this file, asserting the opposite on the same invocation.
  #
  # What survives untouched is the arm below: a session driving its OWN move keeps its transcript.
  # That is the one case where the driver identity is a sound read, and it is now one of four
  # reasons the receipt can give rather than the only branch in the guard.
  run env CLAUDE_CODE_SESSION_ID="$SID" bash "$LRT" --sid "$SID" --from "$T/from" --to "$T/to"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *'"source_retired":0'* ]] || { echo "$output"; false; }
  [[ "$output" == *'"source_retired_reason":"live-self"'* ]] || { echo "$output"; false; }
  [ -f "$SRC" ] || { echo "the LIVE session's own transcript was renamed under it"; false; }
}

# ── --force AND CUSTODY: the hop test is a fact about the lock, --force is a claim about staleness
# The two are deliberately independent (lr-transplant.sh, the comment above SECOND_HOP), and the
# pair below is what makes that decision falsifiable rather than a preference in a comment.

@test "transplant: --force off a store the lock does NOT name rebuilds custody from this move" {
  # Here the lock and the invocation disagree — it says the session is at the third store, the
  # caller says it is moving off the second. --force overrides the refusal, and the custody record
  # is rebuilt from what this move actually knows rather than extended from a record just
  # contradicted. The cost is real and is the reason it is pinned: a bundle cut at an earlier hop
  # goes back to failing lr-ingest-verify C3, exactly as it did before W5-B.
  # EQUIVALENCE GUARD — custody, not retirement. (The `mv "$DST.handed-off" "$DST"` that used to
  # restore the intermediate source is gone for the same reason as above.)
  _transplant; [ "$status" -eq 0 ] || { echo "$output"; false; }
  _hop2;       [ "$status" -eq 0 ] || { echo "$output"; false; }
  run bash "$LRT" --sid "$SID" --from "$T/to" --to "$T/third" --force
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(_lockchain)" != *"/from"* ]] \
    || { echo "custody was extended from a lock this move contradicts: $(_lockchain)"; false; }
  [[ "$(_lockchain)" == *"/to "*"/third" ]] || { echo "chain: $(_lockchain)"; false; }
}

@test "transplant: --force off the store the lock DOES name keeps the chain — nothing disagreed" {
  # EQUIVALENCE GUARD — green against the pre-fix subject too; it pins custody/idempotence, not D2 or D3.
  # The other half, and the one the mutation pass found missing. A forced move off the store the
  # lock already names is a hop the caller happened to force; discarding the chain there would drop
  # the earlier hops' bundles out of C3 for no safety gained, because nothing the lock says was
  # contradicted. --force still does what --force does (it overrides both refusals and the
  # idempotence path); it just has no opinion about custody history.
  _transplant; [ "$status" -eq 0 ] || { echo "$output"; false; }
  run bash "$LRT" --sid "$SID" --from "$T/to" --to "$T/third" --force
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(_lockchain)" == *"/from "*"/to "*"/third" ]] \
    || { echo "--force dropped a chain that agreed with it: $(_lockchain)"; false; }
}

# ── THE LOCK'S CONSUMER: lr-ingest-verify clause C3 ───────────────────────────────────────────────
# C3 asserts the lock names the bundle's target by exact string equality. Rewriting `to` in place on
# a hop fails the FIRST hop's bundle forever — a bundle that was correct when it was cut. The clause
# is extracted and run in isolation rather than through a whole bundle fixture: tests/lr-ingest-
# verify.bats owns the bundle-level cases and this wave owns C3 alone. The extraction is asserted
# non-empty, so a refactor of that block fails loudly here instead of silently testing nothing.
_c3() { # $1 = the manifest's target_cfg → the clause line the SHIPPED C3 block prints for $LOCK
  {
    # shellcheck disable=SC2028  # the \n is the GENERATED STUB's own printf escape and must reach the file literally; expanding it here would emit a real newline into the stub's source
    echo 'clause() { printf "%s %s %s\n" "$1" "$2" "$3"; }'
    printf 'LOCK=%q\nTCFG_M=%q\n' "$LOCK" "$1"
    sed -n '/^if \[ ! -r "\$LOCK" \]; then clause FAIL C3/,/^fi$/p' "$IV"
  } > "$T/c3.sh"
  [ "$(grep -c . "$T/c3.sh")" -ge 8 ] || { echo "the C3 extraction from $IV came back empty or truncated"; return 1; }
  bash "$T/c3.sh"
}

@test "C3: the FIRST hop's bundle still verifies after the session moves on — the chain is the key" {
  # EQUIVALENCE GUARD — green against the pre-fix subject too; it pins custody/idempotence, not D2 or D3.
  _transplant; [ "$status" -eq 0 ] || { echo "$output"; false; }
  _hop2;       [ "$status" -eq 0 ] || { echo "$output"; false; }
  run _c3 "$T/to"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == PASS\ C3\ * ]] || { echo "$output"; false; }
  [[ "$output" == *"EARLIER hop"* ]] || { echo "$output"; false; }
}

@test "C3 CONTROL: a store the session was NEVER on is still the split brain C3 exists to catch" {
  # EQUIVALENCE GUARD — green against the pre-fix subject too; it pins custody/idempotence, not D2 or D3.
  _transplant; [ "$status" -eq 0 ] || { echo "$output"; false; }
  _hop2;       [ "$status" -eq 0 ] || { echo "$output"; false; }
  run _c3 "$T/other"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == FAIL\ C3\ * ]] || { echo "$output"; false; }
  [[ "$output" == *"says to="* ]] || { echo "the FAIL text tests/lr-ingest-verify.bats pins has changed: $output"; false; }
}

@test "C3 CONTROL: the CURRENT owner still passes on the plain equality arm, not the chain arm" {
  # EQUIVALENCE GUARD — green against the pre-fix subject too; it pins custody/idempotence, not D2 or D3.
  _transplant; [ "$status" -eq 0 ] || { echo "$output"; false; }
  _hop2;       [ "$status" -eq 0 ] || { echo "$output"; false; }
  run _c3 "$T/third"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == PASS\ C3\ * ]] || { echo "$output"; false; }
  [[ "$output" != *"EARLIER hop"* ]] || { echo "the plain arm was bypassed: $output"; false; }
}
