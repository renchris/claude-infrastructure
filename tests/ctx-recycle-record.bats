#!/usr/bin/env bats
# ctx-recycle-record.bats — row 8 (CONTEXT_ECONOMY_V2.md §4.3 / §7 AC-4). Proves the recycle-outcome
# record exists, is self-describing, and — the load-bearing part — that its four verdicts are
# DISTINCT tokens.
#
# THE DEFECT THIS PINS. waiting-recycle logged `disposition:"fired"` from FOUR different branches:
# the Stage-1 advisory, the Stage-2 live exec, the Stage-2 shadow would-fire, and the busy nudge.
# Measured across the entire live IDL: 3 `fired` records, of which TWO were advisory nudges and one
# was a Stage-1 advisory. Executed recycles: ZERO, in 32,075 evaluations. One overloaded token made a
# mechanism that has never once executed indistinguishable from a working one.
#
# PROOF DISCIPLINE:
#   · Every absence assertion has a POSITIVE CONTROL beside it.
#   · Non-final `[[ ]]` / `(( ))` carry `|| false` (errexit-exempt ⇒ otherwise DEAD).
#   · Hermetic: $HOME and both store seams are fixtured; a run cannot touch the operator's live
#     recycle store or IDL.
#   · Run under /bin/bash — this lib ships to hook context and the Bash tool runs zsh.
#
# RED-PROOF: the pristine tree has no ce_record_recycle, so the behaviour tests fail at
# "command not found". The STRONG proof is the `mutation:` test, which collapses the enum back to a
# single token and requires the distinctness test to go RED.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  LIB="$REPO/hooks/lib/context-econ.sh"
  AUDIT="$REPO/bin/cc-ctx-audit"
  TMP="$BATS_TEST_TMPDIR"
  export HOME="$TMP/home"
  mkdir -p "$HOME/.claude/autonomy" "$TMP/tel"
  export CC_RECYCLE_EVENTS="$TMP/recycle-events.jsonl"
  : > "$CC_RECYCLE_EVENTS"
  TEL="$TMP/tel/sidR.json"
  printf '{"ts":1785000000,"session_id":"sidR","used_pct":74,"input_tokens":148000,"window":200000}\n' > "$TEL"
}

rec() { /bin/bash -c ". '$LIB'; ce_record_recycle '$TEL' '$1' '${2:-74}' '${3:-threshold}' '${4:-idle}'"; }
field() { jq -r "$1" "$CC_RECYCLE_EVENTS" | tail -1; }

@test "the lib exposes ce_record_recycle under /bin/bash" {
  run /bin/bash -c ". '$LIB'; command -v ce_record_recycle"
  [ "$status" -eq 0 ] || false
}

@test "one call appends exactly one record" {
  rec executed
  run bash -c "wc -l < '$CC_RECYCLE_EVENTS' | tr -d ' '"
  [ "$output" -eq 1 ] || false
}

@test "the record carries the WINDOW — the denominator, not a bare percentage" {
  rec executed
  run bash -c "jq -r '.window' '$CC_RECYCLE_EVENTS' | tail -1"
  [ "$output" = "200000" ] || false
  run bash -c "jq -r '.used_pct' '$CC_RECYCLE_EVENTS' | tail -1"
  [ "$output" = "74" ] || false
  run bash -c "jq -r '.input_tokens' '$CC_RECYCLE_EVENTS' | tail -1"
  [ "$output" = "148000" ] || false
}

@test "an ABSENT window lands as JSON null — never 0, never a string" {
  printf '{"ts":1785000000,"session_id":"sidR","used_pct":74}\n' > "$TEL"
  rec executed
  run bash -c "jq -r '.window|type' '$CC_RECYCLE_EVENTS' | tail -1"
  [ "$output" = "null" ] || false
  run bash -c "jq -r '.window' '$CC_RECYCLE_EVENTS' | tail -1"
  [ "$output" != "0" ] || false
}

@test "THE CORE FIX: the four verdicts are DISTINCT tokens, countable independently" {
  rec advised; rec shadow-would-fire; rec executed; rec nudged
  run bash -c "jq -r '.verdict' '$CC_RECYCLE_EVENTS' | sort -u | tr '\n' ' '"
  [ "$output" = "advised executed nudged shadow-would-fire " ] || false
  # the question the incumbent could not answer: how many recycles ACTUALLY executed?
  run bash -c "jq -r 'select(.verdict==\"executed\")' '$CC_RECYCLE_EVENTS' | jq -s length"
  [ "$output" -eq 1 ] || false
  # and it must NOT be 4 — which is what counting the overloaded `fired` token gave
  [ "$output" -ne 4 ] || false
}

@test "mutation: collapsing the enum to one token turns the distinctness test RED" {
  # THE STRONG RED-PROOF. Force every verdict to the same string, as the incumbent effectively did.
  cp "$LIB" "$TMP/mutlib"
  perl -pi -e 's/local tel="\$\{1:-\}" verdict="\$\{2:-\}"/local tel="\${1:-}" verdict="fired"/' "$TMP/mutlib"
  # ASSERT THE PATCH APPLIED — an unapplied patch silently leaves the ORIGINAL under test and the
  # test passes while proving nothing (memory source-patching-test-makes-the-line-an-api)
  run grep -c 'verdict="fired"' "$TMP/mutlib"
  [ "$status" -eq 0 ] || false
  [ "$output" -ge 1 ] || false
  for v in advised shadow-would-fire executed nudged; do
    /bin/bash -c ". '$TMP/mutlib'; ce_record_recycle '$TEL' '$v' 74 threshold idle"
  done
  # the mutant collapses all four to one token — exactly the defect
  run bash -c "jq -r '.verdict' '$CC_RECYCLE_EVENTS' | sort -u | tr '\n' ' '"
  [ "$output" = "fired " ] || false
  # and the "how many executed" question becomes unanswerable
  run bash -c "jq -r 'select(.verdict==\"executed\")' '$CC_RECYCLE_EVENTS' | jq -s length"
  [ "$output" -eq 0 ] || false
}

@test "an empty verdict is refused — a record with no meaning is worse than none" {
  rec ""
  run bash -c "wc -l < '$CC_RECYCLE_EVENTS' | tr -d ' '"
  [ "$output" -eq 0 ] || false
  # POSITIVE CONTROL: a real verdict on the same fixture DOES write
  rec executed
  run bash -c "wc -l < '$CC_RECYCLE_EVENTS' | tr -d ' '"
  [ "$output" -eq 1 ] || false
}

@test "every line is valid JSON — one malformed line aborts a slurping consumer" {
  rec advised; rec executed
  run bash -c "jq -e -s 'length == 2' '$CC_RECYCLE_EVENTS' >/dev/null"
  [ "$status" -eq 0 ] || false
}

@test "kill switch CC_RECYCLE_LOG=off writes nothing and still returns 0" {
  run env CC_RECYCLE_LOG=off /bin/bash -c ". '$LIB'; ce_record_recycle '$TEL' executed 74 t idle; echo rc=\$?"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"rc=0"* ]] || false
  run bash -c "wc -l < '$CC_RECYCLE_EVENTS' | tr -d ' '"
  [ "$output" -eq 0 ] || false
}

@test "an unwritable store costs the caller nothing (fail-soft contract)" {
  run env CC_RECYCLE_EVENTS=/proc/nonexistent/x.jsonl /bin/bash -c \
    ". '$LIB'; ce_record_recycle '$TEL' executed 74 t idle; echo rc=\$?"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"rc=0"* ]] || false
}

@test "the store is BOUNDED — it prunes rather than growing without limit" {
  for i in $(seq 1 12); do
    CC_RECYCLE_MAX=10 /bin/bash -c ". '$LIB'; ce_record_recycle '$TEL' advised $i t idle"
  done
  run bash -c "wc -l < '$CC_RECYCLE_EVENTS' | tr -d ' '"
  # pruned to max/2 == 5, then appended to; must be well under the 12 written
  [ "$output" -lt 12 ] || false
  [ "$output" -gt 0 ] || false
}

@test "the reader accepts this store as a denominator source (M-1 ↔ M-3 integration)" {
  # This is the seam that makes AC-1 computable for a session whose /tmp telemetry is long gone.
  mkdir -p "$TMP/projects/p"
  printf '%s\n' '{"type":"assistant","sessionId":"sidR","timestamp":"2026-07-20T10:00:00.000Z","message":{"usage":{"input_tokens":148000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}' \
    > "$TMP/projects/p/sidR.jsonl"
  rec executed
  run env CC_CTX_ROOTS="$TMP/projects" CC_CTX_TELEMETRY_DIR="$TMP/empty-tel" \
      CC_CTX_EVENTS="$CC_RECYCLE_EVENTS" /bin/bash "$AUDIT" --p95-recycle-fill --since all
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"n=1"* ]] || false
  # 148000/200000 = 74%
  [[ "$output" == *"74"* ]] || false
}
