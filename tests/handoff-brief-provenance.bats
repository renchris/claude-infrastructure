#!/usr/bin/env bats
# handoff-fire.sh — THE BRIEF'S OWN PATH ON EVERY FIRE ROW (item 4a11a0ac850a), 2026-08-17.
#
# WHY THIS SUITE EXISTS. A lead ANNOUNCED a recycle, WROTE the successor brief, and died before
# firing it; succession was lost in silence. The detector for that class has to answer exactly one
# question — "was a fire ever made FROM this brief?" — and before this change it could not be asked:
# measured over the live ledger on 2026-08-17, 1005 rows across every class carried ZERO field
# naming a prompt-file path. A brief sitting on disk and a brief that was fired were
# byte-indistinguishable from the ledger's side, so the only sweep buildable was a heuristic alarm
# over an attention budget. `prompt_file` is the linking primitive that makes it exact.
#
# The four properties pinned here are each a way the primitive could exist and still be useless:
#
#   1. IT IS THE CALLER-NAMED PATH, NOT THE COPY. handoff-fire REWRITES PROMPT_FILE to a
#      back-channel copy (:7416-7417). Recording that would name a temp file the lead never heard
#      of and the join would miss on every single fire — a field that is present, populated, and
#      answers nothing. This is the load-bearing case.
#   2. A REFUSAL CARRIES IT TOO. Otherwise the sweep conflates "never attempted" (the lost class)
#      with "attempted and refused by a gate" (already recorded, already has a culprit), and
#      convicts the second as the first.
#   3. UNMEASURED READS null, NEVER "". The consumer is an ABSENCE test, so an empty string is a
#      path that matches nothing while looking measured (R9).
#   4. THE jq-LESS FALLBACK CARRIES IT. An absence test inherits every hole in its input as a
#      POSITIVE finding: a real fire written down the degraded path would be reported as a lost
#      succession — the field manufacturing the very alarm it exists to make trustworthy.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  # Hermeticity seams (scripts/test-hermeticity-lint.sh). Nothing here fires, but a fixtured $HOME
  # does NOT redirect an absolute default or a bare name resolved off the operator's PATH — so each
  # is pinned to an ABSENT path under BATS_TEST_TMPDIR, where the sensor reading it fails open.
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  {
    # _iso_now is a ONE-LINER (:464) so grep extracts it whole; _iso_delta_s (:786) is multi-line
    # and needs the range form. Extracting it with grep leaves an unclosed brace, and the resulting
    # `unexpected end of file` reds every case in this file for a reason that has nothing to do with
    # its subject — which is exactly why the `bash -n` guard below runs before anything is sourced.
    grep '^_iso_now() {' "$HF" || true
    sed -n '/^_iso_delta_s() {/,/^}/p'           "$HF"
    sed -n '/^_under_test() {/,/^}/p'            "$HF"
    sed -n '/^_resolved_prompt_file() {/,/^}/p'  "$HF"
    sed -n '/^emit_fire_event() {/,/^}/p'        "$HF"
    sed -n '/^_fire_gate_of() {/,/^}/p'          "$HF"
    sed -n '/^emit_fire_refusal() {/,/^}/p'      "$HF"
    sed -n '/^emit_recycle_event() {/,/^}/p'     "$HF"
    sed -n '/^  emit_handoff_telemetry() {/,/^  }$/p' "$HF"
  } > "$BATS_TEST_TMPDIR/units.sh"
  bash -n "$BATS_TEST_TMPDIR/units.sh" || { echo "extraction from $HF is not valid bash" >&2; return 1; }
  # shellcheck disable=SC1091
  . "$BATS_TEST_TMPDIR/units.sh"
  LOG="$HOME/.claude/logs/handoffs.jsonl"
  BRIEF="$BATS_TEST_TMPDIR/fire-successor.txt"; printf 'brief body\n' > "$BRIEF"
  # Read by the extracted emitters, which shellcheck cannot follow into.
  # shellcheck disable=SC2034
  PROMPT_FILE="" PROMPT_FILE_ORIG="" FIRING_SID="sid-under-test" CHOSEN="next" FIRE_GOAL=""
}

_last() { tail -1 "$LOG"; }

# ── 1. the caller-named path, not the back-channel copy ────────────────────────────────────────
# THE LOAD-BEARING CASE. Pre-fix this is a plain "field absent" red; post-fix it discriminates
# between the two paths that both exist at emit time, which is the property the join depends on.
@test "an admit row records the brief the LEAD named, not the back-channel copy it was rewritten to" {
  PROMPT_FILE_ORIG="$BRIEF"
  PROMPT_FILE="$BATS_TEST_TMPDIR/fire-successor.nb-copy.txt"   # what :7417 substitutes
  emit_fire_event admitted capacity "ok" admit capacity
  run jq -r '.prompt_file' <<<"$(_last)"
  [ "$status" -eq 0 ]
  [ "$output" = "$BRIEF" ]
}

# ── 2. a refusal carries it too ────────────────────────────────────────────────────────────────
@test "a refused fire records its brief, so never-attempted and attempted-then-refused stay apart" {
  PROMPT_FILE_ORIG="$BRIEF"
  emit_fire_refusal capacity "box is full"
  run jq -r '[.class, .verdict, .prompt_file] | @tsv' <<<"$(_last)"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'refused\trefuse\t%s' "$BRIEF")" ]
}

# ── 3. a relative argv path is absolutised ─────────────────────────────────────────────────────
# A sweep scanning a brief directory compares absolute paths; a bare `fire-x.txt` matches nothing.
@test "a relative --prompt-file is recorded absolute, so a sweep can compare it at all" {
  cd "$BATS_TEST_TMPDIR"
  PROMPT_FILE_ORIG="fire-successor.txt"
  emit_fire_event admitted capacity "ok" admit capacity
  run jq -r '.prompt_file' <<<"$(_last)"
  [ "$status" -eq 0 ]
  [ "$output" = "$BATS_TEST_TMPDIR/fire-successor.txt" ]
}

# ── 4. unmeasured reads null, never "" ─────────────────────────────────────────────────────────
# R9. An empty string is a path that matches nothing while LOOKING measured — the worst value for
# a field whose consumer is an absence test.
# The assertion is `has("prompt_file")` AND the value, deliberately. The first version asserted
# only `.prompt_file | type == "null"` and PASSED against pristine origin/main, where the key does
# not exist at all — jq answers "null" for an ABSENT key exactly as it does for a null-valued one,
# so the oracle could not fail and certified nothing. `has()` is the half that separates
# "measured, and the answer is nothing" from "never written down", which is the entire distinction
# this field exists to make.
@test "a row with no brief in scope emits a PRESENT key valued null, not an empty string" {
  PROMPT_FILE_ORIG="" PROMPT_FILE=""
  emit_fire_event admitted capacity "ok" admit capacity
  run jq -r 'has("prompt_file") as $p | [$p, (.prompt_file | type)] | @tsv' <<<"$(_last)"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'true\tnull')" ]
}

# ── 5. the recycle-intent row — the one that witnesses the lost class ──────────────────────────
# The lost-succession class is a lead that announced a recycle and died before firing. recycle-intent
# is the only row emitted early enough to witness the attempt, and it runs in the PARENT where
# PROMPT_FILE is set.
@test "the recycle-intent row names the successor brief" {
  PROMPT_FILE_ORIG="$BRIEF"
  emit_recycle_event recycle-intent "" "pane-9" "recycle ATTEMPTED"
  run jq -r '[.class, .prompt_file] | @tsv' <<<"$(_last)"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'recycle-intent\t%s' "$BRIEF")" ]
}

# ── 6. the jq-less fallback carries it ─────────────────────────────────────────────────────────
# An absence test inherits every hole in its input as a POSITIVE finding. A real fire written down
# the degraded path and missing this field is reported as a lost succession — the field
# manufacturing the exact alarm it exists to make trustworthy. `jq` is removed from PATH rather
# than mocked, so the fallback is reached the same way production would reach it.
@test "the jq-less telemetry fallback still names the brief, so a degraded write is not a false alarm" {
  PROMPT_FILE_ORIG="$BRIEF"
  SPAWNED_PANE="pane-9" WANT_SELF_RETIRE=0 SESSION_ID="sid-under-test"
  run env PATH="/usr/bin:/bin" HOME="$HOME" bash -c '
    . "$1"
    PROMPT_FILE_ORIG="$2"; SPAWNED_PANE=pane-9; WANT_SELF_RETIRE=0
    FIRING_SID=sid-under-test; CHOSEN=next; FIRE_GOAL=""
    jq() { return 127; }        # force the fallback without removing the real binary from the box
    emit_handoff_telemetry 1
  ' _ "$BATS_TEST_TMPDIR/units.sh" "$BRIEF"
  [ "$status" -eq 0 ]
  line="$(_last)"
  # Asserted as TEXT, deliberately: the fallback's contract is the literal printf shape, and parsing
  # it with jq would pass on a line jq had to repair.
  [[ "$line" == *"\"prompt_file\":\"$BRIEF\""* ]]
}

# ── 7. the fallback spells absence as null, not as an empty JSON string ────────────────────────
@test "the jq-less fallback emits null for an absent brief, keeping the absence test honest" {
  run env PATH="/usr/bin:/bin" HOME="$HOME" bash -c '
    . "$1"
    PROMPT_FILE_ORIG=""; PROMPT_FILE=""; SPAWNED_PANE=pane-9; WANT_SELF_RETIRE=0
    FIRING_SID=sid-under-test; CHOSEN=next; FIRE_GOAL=""
    jq() { return 127; }
    emit_handoff_telemetry 0
  ' _ "$BATS_TEST_TMPDIR/units.sh"
  [ "$status" -eq 0 ]
  line="$(_last)"
  [[ "$line" == *'"prompt_file":null'* ]]
}
