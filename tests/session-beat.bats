#!/usr/bin/env bats
# session-beat.bats — the presence BEAT: producer (hooks/session-beat.sh) + reader (hooks/lib/cc-beat.sh).
#
# The beat exists so "who drove the last turn" is ATTESTED once, at the instant it is known, instead
# of re-derived from multi-MB transcripts by every closer on every sweep. Its correctness is what the
# act-time re-take and the 60s freshness lease both rest on.
#
# `[ ]` throughout — a non-final `[[ ]]` is errexit-EXEMPT under bats and therefore a DEAD assertion.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # Fixture $HOME FIRST: the producer and reader both default CC_BEAT_DIR to $HOME/.claude/cc-beats,
  # so an unfixtured suite would write beats into the operator's LIVE registry — and a live beat is
  # exactly what the reaper reads to decide a close. Hermetic by construction, not by convention.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  BEAT="$REPO/hooks/session-beat.sh"
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats"
  # shellcheck source=/dev/null
  . "$REPO/hooks/lib/cc-beat.sh"
}

emit() { # <json-stdin> <kind>
  printf '%s' "$1" | /bin/bash "$BEAT" "${2:-prompt}"
}

@test "an operator prompt is attested who=operator and sets operatorT" {
  emit '{"session_id":"s1","cwd":"/tmp","prompt":"please fix the reaper"}' prompt
  [ "$(jq -r '.who' "$CC_BEAT_DIR/s1.json")" = "operator" ]
  [ "$(jq -r '.operatorT != null' "$CC_BEAT_DIR/s1.json")" = "true" ]
}

@test "AUTO-TRAFFIC is not presence: a Stop-hook re-prompt reads who=auto with NO operatorT" {
  # Load-bearing, not cosmetic: our own auto-drive arrives through UserPromptSubmit. A presence
  # signal that counted its own auto-drive would hold every self-driving session open forever and
  # deadlock every recycle — the exact reason the shared auto-traffic regex exists.
  emit '{"session_id":"s2","cwd":"/tmp","prompt":"Stop hook feedback: keep going"}' prompt
  [ "$(jq -r '.who' "$CC_BEAT_DIR/s2.json")" = "auto" ]
  [ "$(jq -r '.operatorT' "$CC_BEAT_DIR/s2.json")" = "null" ]
  run cb_operator_age s2
  [ "$status" -ne 0 ]        # UNKNOWN, never "0 seconds ago"
  [ -z "$output" ]
}

@test "task-notification traffic is also not presence (second auto-traffic form)" {
  emit '{"session_id":"s2b","cwd":"/tmp","prompt":"<task-notification>done</task-notification>"}' prompt
  [ "$(jq -r '.who' "$CC_BEAT_DIR/s2b.json")" = "auto" ]
}

# ── `src` — WHICH auto-traffic (backlog b60eb29e97dd) ────────────────────────────────────────────
# `who` collapses every non-operator prompt into one answer, which is right for presence and wrong
# for the one consumer that must tell a session's own close cascade from a wake: cc-await-ping
# --idle-scoped stood itself down on the `Stop hook feedback:` re-prompt of the very turn that armed
# it. Only this hook ever sees the prompt text, so the distinction has to be attested here.

@test "src separates a session's OWN auto-drive from auto traffic that is a wake" {
  emit '{"session_id":"t1","cwd":"/tmp","prompt":"Stop hook feedback: keep going"}' prompt
  [ "$(jq -r '.src' "$CC_BEAT_DIR/t1.json")" = "stopfeedback" ]
  emit '{"session_id":"t2","cwd":"/tmp","prompt":"⚑ boundary — persist and hand off"}' prompt
  [ "$(jq -r '.src' "$CC_BEAT_DIR/t2.json")" = "advisory" ]
  emit '{"session_id":"t3","cwd":"/tmp","prompt":"<task-notification>done</task-notification>"}' prompt
  [ "$(jq -r '.src' "$CC_BEAT_DIR/t3.json")" = "tasknote" ]
  emit '{"session_id":"t4","cwd":"/tmp","prompt":"[Request interrupted by user]"}' prompt
  [ "$(jq -r '.src' "$CC_BEAT_DIR/t4.json")" = "interrupt" ]
}

@test "src is SUBORDINATE to who — it partitions the auto side and never contradicts presence" {
  emit '{"session_id":"t5","cwd":"/tmp","prompt":"please fix the reaper"}' prompt
  [ "$(jq -r '.who' "$CC_BEAT_DIR/t5.json")" = "operator" ]
  [ "$(jq -r '.src' "$CC_BEAT_DIR/t5.json")" = "operator" ]
  emit '{"session_id":"t5","cwd":"/tmp"}' stop
  [ "$(jq -r '.src' "$CC_BEAT_DIR/t5.json")" = "stop" ]
  # The CC_CLASSIFY_AUTO_RX seam still governs the split, and src follows it rather than second-
  # guessing it: a pattern removed from the regex reads operator on BOTH fields.
  printf '%s' '{"session_id":"t6","cwd":"/tmp","prompt":"Stop hook feedback: keep going"}' \
    | env CC_CLASSIFY_AUTO_RX='^<task-notification>' /bin/bash "$BEAT" prompt
  [ "$(jq -r '.who' "$CC_BEAT_DIR/t6.json")" = "operator" ]
  [ "$(jq -r '.src' "$CC_BEAT_DIR/t6.json")" = "operator" ]
}

@test "operatorT is STICKY: a later auto beat must never lower it" {
  # Presence, once shown, decays only by the clock. A Stop beat landing after an operator prompt
  # must not erase the very evidence that protects the pane from being reaped.
  emit '{"session_id":"s3","cwd":"/tmp","prompt":"do the thing"}' prompt
  before="$(jq -r '.operatorT' "$CC_BEAT_DIR/s3.json")"
  emit '{"session_id":"s3","cwd":"/tmp"}' stop
  [ "$(jq -r '.kind' "$CC_BEAT_DIR/s3.json")" = "stop" ]
  [ "$(jq -r '.who'  "$CC_BEAT_DIR/s3.json")" = "auto" ]
  [ "$(jq -r '.operatorT' "$CC_BEAT_DIR/s3.json")" = "$before" ]
  [ "$(jq -r '.seq' "$CC_BEAT_DIR/s3.json")" -eq 2 ]
}

@test "cb_operator_age reports the age against a pinned clock" {
  emit '{"session_id":"s4","cwd":"/tmp","prompt":"hello"}' prompt
  t="$(jq -r '.operatorT' "$CC_BEAT_DIR/s4.json")"
  CC_BEAT_NOW="$(( t + 300 ))" run cb_operator_age s4
  [ "$status" -eq 0 ]
  [ "$output" -eq 300 ]
}

@test "a backwards clock cannot forge a huge age (which would read as 'operator long gone')" {
  emit '{"session_id":"s5","cwd":"/tmp","prompt":"hello"}' prompt
  t="$(jq -r '.operatorT' "$CC_BEAT_DIR/s5.json")"
  CC_BEAT_NOW="$(( t - 5000 ))" run cb_operator_age s5
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]        # clamped to the SAFE direction (present), never a large stale age
}

@test "a torn/partial beat reads as ABSENT, never as a malformed 'no operator' answer" {
  mkdir -p "$CC_BEAT_DIR"
  printf '{"sid":"s6","who":"oper' > "$CC_BEAT_DIR/s6.json"     # truncated write
  run cb_last_beat s6
  [ "$status" -ne 0 ]
  run cb_operator_age s6
  [ "$status" -ne 0 ]        # UNKNOWN ⇒ the caller fails CLOSED
}

@test "EXISTENCE GATE: cb_system_live is false with no beat dir, true with a fresh beat" {
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/absent-beats"
  run cb_system_live
  [ "$status" -ne 0 ]
  # positive control beside the absence assertion — proves the gate can say LIVE, so the negative
  # above is attributable to absence and not to a predicate that never returns 0.
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats2"
  emit '{"session_id":"s7","cwd":"/tmp","prompt":"hi"}' prompt
  run cb_system_live
  [ "$status" -eq 0 ]
}

@test "EXISTENCE GATE: only STALE beats ⇒ not live (the producer stopped)" {
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats3"; mkdir -p "$CC_BEAT_DIR"
  printf '{"sid":"s8","t":1000000000,"who":"auto","operatorT":null,"seq":1}\n' > "$CC_BEAT_DIR/s8.json"
  run cb_system_live
  [ "$status" -ne 0 ]
  CC_BEAT_LIVE_MAX_S=999999999 run cb_system_live
  [ "$status" -eq 0 ]        # differential: the same beat IS live under a wide window
}

@test "kill switch CC_BEAT=off writes nothing — and with it ON the same call writes (differential)" {
  CC_BEAT=off emit '{"session_id":"s9","cwd":"/tmp","prompt":"hi"}' prompt
  [ ! -f "$CC_BEAT_DIR/s9.json" ]
  emit '{"session_id":"s9","cwd":"/tmp","prompt":"hi"}' prompt
  [ -f "$CC_BEAT_DIR/s9.json" ]
}

@test "FAIL-OPEN producer: garbage stdin and a missing sid still exit 0 (a beat must never cost a session)" {
  run emit 'not json at all' prompt
  [ "$status" -eq 0 ]
  run emit '{"cwd":"/tmp","prompt":"no sid here"}' prompt
  [ "$status" -eq 0 ]
}

@test "a path-hostile sid is refused, never written outside the beat dir" {
  emit '{"session_id":"../../escape","cwd":"/tmp","prompt":"hi"}' prompt
  [ ! -e "$BATS_TEST_TMPDIR/escape.json" ]
  [ ! -e "$CC_BEAT_DIR/../../escape.json" ]
}
