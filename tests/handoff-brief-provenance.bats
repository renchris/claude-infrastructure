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
  # shellcheck disable=SC2034  # read by _resolved_prompt_file, sourced from units.sh
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
  # All five are read by the emitters sourced from units.sh, which shellcheck cannot follow into;
  # they are also re-set inside the subshell below, which is the arm that actually runs the
  # fallback. A shellcheck directive must be a SINGLE line — wrapping the reason onto a second
  # comment line makes it unparseable (SC1073) and silently costs the whole file its analysis.
  # shellcheck disable=SC2034
  PROMPT_FILE_ORIG="$BRIEF"
  # shellcheck disable=SC2034
  SPAWNED_PANE="pane-9" WANT_SELF_RETIRE=0 SESSION_ID="sid-under-test"
  # shellcheck disable=SC2016
  # $1/$2 are the INNER shell's positionals (passed after `_` below), not this shell's.
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
  # shellcheck disable=SC2016
  # $1 is the INNER shell's positional (passed after `_` below), not this shell's.
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

# ── 8-10. the fallback's ONE free-form field is escaped, so it cannot poison the ledger ────────
#
# WHY THESE EXIST (2026-09-09, recovering the value of stranded branch
# claude/fire-20260818T031629Z-40497-1, whose own suite could not be re-landed against this
# implementation). Every other %s on the fallback's printf line is a constrained token — an ISO
# stamp, a pane uuid, an account name, a class. `prompt_file` is a filesystem PATH the caller
# chose, and on POSIX every byte but `/` and NUL is legal in one. Interpolated raw it emitted
# INVALID JSON, and the blast radius is not one lost key: scripts/unfired-brief-sweep.sh reads this
# ledger with `jq -rs` — SLURP, the whole file as one document — so ONE malformed line empties
# EPOCH and the sweep answers `not-armed — no ledger row carries prompt_file yet` over a fully
# armed ledger. Measured end-to-end before the fix: a `swept` verdict became `not-armed`.
#
# That verdict is ALSO what a correct pre-primitive ledger says, so no consumer can tell a
# disarmed detector from a young one — the fail-safe-default-mimics-the-healthy-state class,
# reaching the sweep through its PRODUCER rather than through any line of its own code. The three
# cases below are each a distinct way the raw interpolation broke, and each was red-proved
# individually against the pre-fix emitter: quote/backslash INVALID, tab INVALID, and newline
# INVALID *and split into two ledger rows*, which poisons the slurp even harder than a bad quote.
#
# Asserted by ROUND-TRIP (jq parses the line AND gives the path back byte-identical), not by
# substring: an escaper that merely produces parseable JSON while mangling the path would satisfy
# a text match and still miss every join, which is the failure mode `prompt_file` exists to close.

_fallback_roundtrip() { # $1=brief path → echoes the path jq reads back, or nothing
  run env PATH="/usr/bin:/bin" HOME="$HOME" bash -c '
    . "$1"
    PROMPT_FILE_ORIG="$2"; SPAWNED_PANE=pane-9; WANT_SELF_RETIRE=0
    FIRING_SID=sid-under-test; CHOSEN=next; FIRE_GOAL=""
    jq() { return 127; }        # force the fallback without removing the real binary from the box
    emit_handoff_telemetry 1
  ' _ "$BATS_TEST_TMPDIR/units.sh" "$1"
  [ "$status" -eq 0 ]
  # ONE row, always. A raw newline in the path splits the record, and a suite that only read the
  # LAST line would see a well-formed fragment and pass over a ledger it had just corrupted.
  [ "$(wc -l < "$LOG" | tr -d ' ')" -eq 1 ]
  jq -r '.prompt_file' < "$LOG"
}

@test "a brief path holding a quote and a backslash still writes ONE parseable row" {
  got="$(_fallback_roundtrip '/tmp/fire-a"b\c.txt')"
  [ "$got" = '/tmp/fire-a"b\c.txt' ]
}

# 🚨 THE LITERALS BELOW ARE $'...' AND MUST STAY THAT WAY. The first draft of the newline case
# built its path as "/tmp/fire-x$(printf '\n')y.txt" and PASSED against pristine trunk — command
# substitution strips trailing newlines, so `$(printf '\n')` is the EMPTY STRING and the path under
# test held no newline at all. The case was green because it was vacuous, on the very axis it
# names. ANSI-C quoting embeds the byte without a subshell; the tab case is rewritten the same way
# for the same reason even though its own substitution happened to survive.
@test "a brief path holding a tab still writes ONE parseable row" {
  got="$(_fallback_roundtrip $'/tmp/fire-a\tb.txt')"
  [ "$got" = $'/tmp/fire-a\tb.txt' ]
}

@test "a brief path holding a newline is escaped, not split across two ledger rows" {
  got="$(_fallback_roundtrip $'/tmp/fire-x\ny.txt')"
  [ "$got" = $'/tmp/fire-x\ny.txt' ]
}

# ── 11. CONTROL: the ordinary path is untouched by the escaper ─────────────────────────────────
# The escaper runs on EVERY fallback row, so its no-op case is the one that would break every
# existing join if the substitution order were wrong (backslash after quote double-escapes).
@test "CONTROL: an ordinary brief path is passed through the escaper byte-identically" {
  got="$(_fallback_roundtrip "$BRIEF")"
  [ "$got" = "$BRIEF" ]
}
