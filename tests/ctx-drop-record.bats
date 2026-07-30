#!/usr/bin/env bats
# ctx-drop-record.bats — row 8 (CONTEXT_ECONOMY_V2.md §4.2 / §7 AC-5). Proves the fill-drop event is
# RECORDED BEFORE ce_sample destroys the only evidence of it, and that the record is self-describing.
#
# THE DEFECT THIS PINS. A fill drop > 2 points is the only signal this system has that a context was
# compacted or replaced. For its whole life ce_sample detected that event and immediately TRUNCATED
# the history file — the sole trace — with no counter, no log and no IDL line. The truncation is
# correct (the prior slope is poisoned); discarding the event was not.
#
# PROOF DISCIPLINE:
#   · Every absence assertion has a POSITIVE CONTROL beside it.
#   · Non-final `[[ ]]` / `(( ))` carry `|| false` — they are errexit-EXEMPT and otherwise DEAD
#     (memory bats-dead-assertions-errexit-exemptions).
#   · Hermetic: the IDL path and the telemetry dir are both behind env seams and fixtured, so a run
#     can never append to the operator's live IDL nor be decided by ambient state.
#   · Sourced and run under /bin/bash — the Bash tool runs zsh, and this lib ships to hook context.
#
# RED-PROOF, run against a pristine tree from `git archive` at a DERIVED rev (a29473c0 at the time
# of writing; derived, never hardcoded, because a rebased sha turns the proof into a skip and a skip
# reads as a pass). Result: 8 RED / 5 green-on-both, and the split is NAMED rather than glossed —
#
#   RED (these pin the NEW behaviour): 1, 3, 5, 6, 7, 8, 9, 10
#   GREEN ON BOTH — contract-preservation, and correctly so: 2 (no record on a RISE), 4 (the >2pt
#     boundary is unchanged), 11 (kill switch), 12 (fail-soft), 13 (ce_burn's answer is untouched).
#     These assert that the change did NOT alter behaviour that was already correct, so a pristine
#     green is the expected result, not a weak test.
#
# The STRONG proof is test 8, which inverts the one behaviour that matters — an absent window
# becoming 0 instead of null — and requires the suite to notice. A test that survives its own
# mutation pins nothing.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  LIB="$REPO/hooks/lib/context-econ.sh"
  TMP="$BATS_TEST_TMPDIR"
  export HOME="$TMP/home"
  mkdir -p "$HOME/.claude/autonomy" "$TMP/tel"
  export CC_CE_IDL="$TMP/idl.jsonl"
  : > "$CC_CE_IDL"
  TEL="$TMP/tel/sidX.json"
  HIST="$TMP/tel/sidX.hist"
}

# Emit telemetry at a given ts/used, with or without a window, then sample it.
mk_tel() { # $1=ts $2=used [$3=window]
  if [ -n "${3:-}" ]; then
    printf '{"ts":%s,"used_pct":%s,"input_tokens":%s,"window":%s}\n' "$1" "$2" "$(( $2 * 1000 ))" "$3" > "$TEL"
  else
    printf '{"ts":%s,"used_pct":%s,"input_tokens":%s}\n' "$1" "$2" "$(( $2 * 1000 ))" > "$TEL"
  fi
}

sample() { /bin/bash -c ". '$LIB'; ce_sample '$TEL'"; }

@test "the lib sources and exposes ce_log_drop under /bin/bash" {
  run /bin/bash -c ". '$LIB'; command -v ce_log_drop"
  [ "$status" -eq 0 ] || false
}

@test "a normal RISING sample writes NO drop record (positive control for the detector)" {
  mk_tel 1000 40 200000; sample
  mk_tel 1200 55 200000; sample
  run bash -c "grep -c 'fill-drop' '$CC_CE_IDL' 2>/dev/null || true"
  [ "$output" -eq 0 ] || false
  # POSITIVE CONTROL that sampling actually happened at all — else the zero above is vacuous
  run bash -c "wc -l < '$HIST' | tr -d ' '"
  [ "$output" -eq 2 ] || false
}

@test "a fill DROP > 2 points writes exactly one drop record" {
  mk_tel 1000 80 200000; sample
  mk_tel 1200 12 200000; sample
  run bash -c "grep -c 'fill-drop' '$CC_CE_IDL'"
  [ "$output" -eq 1 ] || false
}

@test "a drop of exactly 2 points does NOT record (the boundary is unchanged)" {
  mk_tel 1000 40 200000; sample
  mk_tel 1200 38 200000; sample
  run bash -c "grep -c 'fill-drop' '$CC_CE_IDL' 2>/dev/null || true"
  [ "$output" -eq 0 ] || false
}

@test "the record is emitted BEFORE the truncation it survives" {
  mk_tel 1000 80 200000; sample
  mk_tel 1200 12 200000; sample
  # the history was truncated to the single new sample — the evidence in .hist is GONE
  run bash -c "wc -l < '$HIST' | tr -d ' '"
  [ "$output" -eq 1 ] || false
  # ...and yet the event survives, in the IDL, with both endpoints intact
  run bash -c "jq -r 'select(.reason==\"fill-drop\")|\"\(.from_pct) \(.to_pct) \(.drop_pct)\"' '$CC_CE_IDL'"
  [ "$output" = "80 12 68" ] || false
}

@test "the record carries the WINDOW — it is self-describing, not a bare percentage" {
  mk_tel 1000 80 200000; sample
  mk_tel 1200 12 200000; sample
  run bash -c "jq -r 'select(.reason==\"fill-drop\")|.window' '$CC_CE_IDL'"
  [ "$output" = "200000" ] || false
}

@test "an ABSENT window lands as JSON null — never 0, never the string '-'" {
  mk_tel 1000 80; sample
  mk_tel 1200 12; sample
  run bash -c "jq -r 'select(.reason==\"fill-drop\")|.window|type' '$CC_CE_IDL'"
  [ "$output" = "null" ] || false
  # the two wrong answers, asserted explicitly: 0 would read as a real window, "-" would break jq
  run bash -c "jq -r 'select(.reason==\"fill-drop\")|.window' '$CC_CE_IDL'"
  [ "$output" != "0" ] || false
  [ "$output" != "-" ] || false
}

@test "mutation: emitting 0 instead of null for an absent window turns the null test RED" {
  # THE STRONG RED-PROOF — invert exactly one behaviour and require the suite to catch it.
  cp "$LIB" "$TMP/mutlib"
  sed -i.bak 's|case "$win" in ..|-|\*\[!0-9\]\*) win=null ;; esac|case "$win" in ""\|-\|*[!0-9]*) win=0 ;; esac|' "$TMP/mutlib" 2>/dev/null || true
  # portable fallback: the sed above is fragile across seds, so patch by the unique token instead
  if ! grep -q 'win=0 ;; esac' "$TMP/mutlib"; then
    perl -pi -e 's/win=null ;; esac/win=0 ;; esac/' "$TMP/mutlib"
  fi
  # ASSERT THE PATCH APPLIED — an unapplied patch leaves the ORIGINAL program under test and the
  # test then passes while proving nothing (memory source-patching-test-makes-the-line-an-api)
  run grep -c 'win=0 ;; esac' "$TMP/mutlib"
  [ "$status" -eq 0 ] || false
  [ "$output" -ge 1 ] || false
  mk_tel 1000 80; /bin/bash -c ". '$TMP/mutlib'; ce_sample '$TEL'"
  mk_tel 1200 12; /bin/bash -c ". '$TMP/mutlib'; ce_sample '$TEL'"
  # the mutant must now claim a window of 0 where the truth is "unknown"
  run bash -c "jq -r 'select(.reason==\"fill-drop\")|.window' '$CC_CE_IDL'"
  [ "$output" = "0" ] || false
}

@test "the record uses its own hook namespace and a parseable reason token" {
  mk_tel 1000 80 200000; sample
  mk_tel 1200 12 200000; sample
  run bash -c "jq -r 'select(.reason==\"fill-drop\")|.hook' '$CC_CE_IDL'"
  [ "$output" = "context-econ" ] || false
  # must NOT masquerade as either consuming hook's namespace
  run bash -c "jq -r 'select(.reason==\"fill-drop\")|.hook' '$CC_CE_IDL'"
  [ "$output" != "waiting-recycle" ] || false
  [ "$output" != "boundary-handoff" ] || false
}

@test "every emitted line is valid JSON — one malformed line aborts a slurping consumer" {
  mk_tel 1000 80 200000; sample
  mk_tel 1200 12 200000; sample
  run bash -c "jq -e -s 'length >= 1' '$CC_CE_IDL' >/dev/null"
  [ "$status" -eq 0 ] || false
}

@test "kill switch CC_CE_DROP_LOG=off suppresses the record but NOT the sample" {
  mk_tel 1000 80 200000
  CC_CE_DROP_LOG=off /bin/bash -c ". '$LIB'; ce_sample '$TEL'"
  mk_tel 1200 12 200000
  CC_CE_DROP_LOG=off /bin/bash -c ". '$LIB'; ce_sample '$TEL'"
  run bash -c "grep -c 'fill-drop' '$CC_CE_IDL' 2>/dev/null || true"
  [ "$output" -eq 0 ] || false
  # the sample itself must be untouched by the kill switch — it restores logging, not behaviour
  run bash -c "wc -l < '$HIST' | tr -d ' '"
  [ "$output" -eq 1 ] || false
}

@test "an unwritable IDL path costs the hook nothing (fail-soft contract)" {
  mk_tel 1000 80 200000; sample
  mk_tel 1200 12 200000
  run env CC_CE_IDL=/proc/nonexistent/idl.jsonl /bin/bash -c ". '$LIB'; ce_sample '$TEL'; echo rc=\$?"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"rc=0"* ]] || false
}

@test "ce_burn is unaffected — the drop still resets the slope to 'unknown'" {
  mk_tel 1000 80 200000; sample
  mk_tel 1200 12 200000; sample
  run /bin/bash -c ". '$LIB'; ce_burn '$TEL'"
  [ "$status" -eq 0 ] || false
  # one post-drop sample cannot span the trust gate, so the honest answer is "no forecast"
  [ "$output" = "0 -1" ] || false
}
