#!/usr/bin/env bats
# stop-failure-marker — the StopFailure consumer must collapse N deaths of ONE cause into ONE
# operator-visible fact, and must never make a noise on the death path.
#
# WHAT THIS PINS, and why each property is a test rather than a comment:
#   · COLLAPSE. One account hitting its cap or login cliff kills ~30 sessions at once. The marker is
#     keyed on the CAUSE (error × account), never the session, so 30 deaths write 30 lines into ONE
#     file. The CONTROL at the bottom mutates exactly that key to a session-keyed one and requires
#     this suite to go RED — without it, a suite asserting "1 file" proves nothing, because a script
#     that wrote nothing at all would also never write 30.
#   · CONCURRENCY. The 30 deaths are simultaneous. Every line must survive and none may interleave
#     into a malformed one — a single malformed line makes a reader's `jq -rs` slurp read as EMPTY,
#     which is the alarm going green over a live outage.
#   · SILENCE. Exit 0 and an EMPTY stdout on every path, including malformed input and no input.
#     This is Stop-family: a stray byte is not merely untidy, it can be read as a directive.
#   · IT IS NOT A PAGER. The hook must not notify anyone — paging stays with the reader that
#     consumes these markers. Asserted by pinning its whole write footprint.
#
# Hermetic: HOME is redirected into BATS_TEST_TMPDIR and CLAUDE_CONFIG_DIR is UNSET (on this box it
# points at a live account dir, which the subject reads to name the account). Nothing here touches
# ~/.claude.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/stop-failure-marker.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset CLAUDE_CONFIG_DIR
  export STOP_FAILURE_MARKER_DIR="$BATS_TEST_TMPDIR/markers"
  export STOP_FAILURE_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export STOP_FAILURE_ACCOUNTS="$BATS_TEST_TMPDIR/accounts.json"
  cat > "$STOP_FAILURE_ACCOUNTS" <<'JSON'
{"accounts":[{"name":"next","config_dir":"~/.claude"},{"name":"next4","config_dir":"~/.claude-quaternary"}]}
JSON
}

# The payload shape captured verbatim from 2.1.220 (/tmp/hs/log/stopfail.tsv, HOOK_SURFACE_100P W1).
real_payload() {   # $1 = session id  $2 = error (default authentication_failed)
  local sid="${1:-s1}" err="${2:-authentication_failed}"
  cat <<JSON
{"session_id":"${sid}","transcript_path":"/tmp/hs/${sid}.jsonl","cwd":"/private/tmp/hs/scratch",
 "prompt_id":"67784c16","effort":{"level":"high"},"hook_event_name":"StopFailure",
 "error":"${err}","last_assistant_message":"Not logged in · Please run /login"}
JSON
}

markers() { find "$STOP_FAILURE_MARKER_DIR" -type f -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' '; }
all_lines() { cat "$STOP_FAILURE_MARKER_DIR"/*.jsonl 2>/dev/null | wc -l | tr -d ' '; }

# ---- the fact it records ------------------------------------------------------------------------
@test "one death opens one marker carrying the error and the resolved account" {
  real_payload s1 | bash "$HOOK"
  [ "$(markers)" -eq 1 ] || false
  local f; f="$(find "$STOP_FAILURE_MARKER_DIR" -name '*.jsonl' | head -1)"
  jq -e '.error == "authentication_failed"' "$f" >/dev/null || false
  jq -e '.session_id == "s1"' "$f" >/dev/null || false
  jq -e '.last_assistant_message | test("Please run /login")' "$f" >/dev/null || false
  # the account is NOT in the payload — it is resolved from the config dir through the SSOT
  jq -e '.account == "next"' "$f" >/dev/null || false
}

@test "the marker FILENAME carries the cause, so a reader needs no parse to see which" {
  real_payload s1 | bash "$HOOK"
  find "$STOP_FAILURE_MARKER_DIR" -name 'authentication_failed__next.jsonl' | grep -q . || false
}

@test "an account outside the SSOT still resolves — to its config-dir basename, never to blank" {
  CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/.claude-unlisted" real_payload s1 | true
  printf '%s' "$(real_payload s1)" | CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/.claude-unlisted" bash "$HOOK"
  find "$STOP_FAILURE_MARKER_DIR" -name 'authentication_failed__.claude-unlisted.jsonl' | grep -q . || false
}

# ---- THE POINT: collapse -----------------------------------------------------------------------
@test "30 CONCURRENT deaths of one cause collapse to ONE marker holding 30 lines" {
  local i
  for i in $(seq 1 30); do real_payload "s$i" | bash "$HOOK" & done
  wait
  [ "$(markers)" -eq 1 ] || false
  [ "$(all_lines)" -eq 30 ] || false
}

@test "no line is lost or interleaved under that concurrency — every line parses" {
  local i
  for i in $(seq 1 30); do real_payload "s$i" | bash "$HOOK" & done
  wait
  local f; f="$(find "$STOP_FAILURE_MARKER_DIR" -name '*.jsonl' | head -1)"
  # -e over the whole file: ONE malformed line makes a reader's slurp read as EMPTY, which is the
  # alarm going green over a live outage.
  jq -e -s 'length == 30 and all(.[]; .error == "authentication_failed")' "$f" >/dev/null || false
  # POSITIVE CONTROL for that assertion: it can see a malformed line when one is there.
  printf 'not json\n' >> "$f"
  run jq -e -s 'length == 30' "$f"
  [ "$status" -ne 0 ] || false
}

@test "a DIFFERENT cause is a different fact — two markers, not one" {
  real_payload s1 authentication_failed | bash "$HOOK"
  real_payload s2 usage_limit_reached  | bash "$HOOK"
  [ "$(markers)" -eq 2 ] || false
}

@test "the same error on a DIFFERENT account is also a different fact" {
  real_payload s1 | bash "$HOOK"
  printf '%s' "$(real_payload s2)" | CLAUDE_CONFIG_DIR="$HOME/.claude-quaternary" bash "$HOOK"
  [ "$(markers)" -eq 2 ] || false
  find "$STOP_FAILURE_MARKER_DIR" -name 'authentication_failed__next4.jsonl' | grep -q . || false
}

@test "a runaway cause is bounded, and the capped marker does NOT look resolved" {
  local i
  for i in $(seq 1 6); do real_payload "s$i" | STOP_FAILURE_CAP=3 bash "$HOOK"; done
  [ "$(all_lines)" -eq 3 ] || false
  [ "$(markers)" -eq 1 ] || false          # the FACT survives the cap; only the census stops
  grep -q '"disposition":"passed","reason":"marker-capped"' "$STOP_FAILURE_IDL" || false
}

@test "a cause that stopped recurring self-retires at the TTL" {
  real_payload s1 | bash "$HOOK"
  [ "$(markers)" -eq 1 ] || false
  local f; f="$(find "$STOP_FAILURE_MARKER_DIR" -name '*.jsonl' | head -1)"
  touch -t 202501010000 "$f"
  real_payload s2 usage_limit_reached | STOP_FAILURE_TTL_MIN=60 bash "$HOOK"
  ! find "$STOP_FAILURE_MARKER_DIR" -name 'authentication_failed__next.jsonl' | grep -q . || false
  find "$STOP_FAILURE_MARKER_DIR" -name 'usage_limit_reached__next.jsonl' | grep -q . || false
}

# ---- silence on the death path -----------------------------------------------------------------
@test "exit 0 and EMPTY stdout on every input shape — Stop-family, never a gate" {
  local shape
  for shape in '{"hook_event_name":"StopFailure","error":"authentication_failed"}' \
               'not json at all' '{}' '' '{"error":""}'; do
    run bash -c "printf '%s' '$shape' | bash '$HOOK'"
    [ "$status" -eq 0 ] || false
    [ -z "$output" ] || false
  done
}

@test "it emits NOTHING on stderr either — including the very first death" {
  rm -rf "$STOP_FAILURE_MARKER_DIR"
  run bash -c "printf '%s' '$(real_payload s1 | tr -d '\n')' | bash '$HOOK' 2>&1 1>/dev/null"
  [ -z "$output" ] || false
}

@test "a payload with no error field abstains — it is LOGGED, never silent" {
  printf '%s' '{"session_id":"s","hook_event_name":"StopFailure"}' | bash "$HOOK"
  [ "$(markers)" -eq 0 ] || false
  grep -q '"disposition":"abstained","reason":"no-error-field"' "$STOP_FAILURE_IDL" || false
}

@test "IT IS NOT A PAGER: its entire write footprint is the marker and the IDL" {
  local before after
  before="$BATS_TEST_TMPDIR/before"; after="$BATS_TEST_TMPDIR/after"
  find "$HOME" -type f 2>/dev/null | sort > "$before"
  real_payload s1 | bash "$HOOK"
  find "$HOME" -type f 2>/dev/null | sort > "$after"
  # nothing written under HOME at all: markers + IDL are on their own env seams here
  diff -q "$before" "$after" >/dev/null || false
  # POSITIVE CONTROL: the detector can see a write under HOME when there is one.
  : > "$HOME/canary"
  find "$HOME" -type f 2>/dev/null | sort > "$after"
  run diff -q "$before" "$after"
  [ "$status" -ne 0 ] || false
}

# ---- the control that must be able to FAIL ------------------------------------------------------
@test "ANCHOR: the cause-key line the control mutates still exists in the subject" {
  # If this goes to 0, the subject moved out from under the control below and the collapse
  # assertions have quietly stopped testing the thing they were written for.
  [ "$(grep -c 'ANCHOR: cause-keyed, never session-keyed' "$HOOK")" -eq 1 ] || false
}

@test "CONTROL session_keyed_is_red: a session-keyed mutant fails the collapse test" {
  # The whole value of this hook is the KEY. A mutant that keys on the session — the naive
  # page-per-death shape — must make "30 deaths ⇒ 1 marker" go RED. If it does not, the collapse
  # assertions are vacuous and this suite is decoration.
  local mutant="$BATS_TEST_TMPDIR/mutant.sh"
  sed 's|^CAUSE_KEY=.*ANCHOR: cause-keyed, never session-keyed$|CAUSE_KEY="$(_sf_slug "$SID")"|' \
    "$HOOK" > "$mutant"
  grep -q 'CAUSE_KEY="$(_sf_slug "$SID")"' "$mutant" || false     # the mutation actually applied
  local i
  for i in $(seq 1 30); do real_payload "s$i" | bash "$mutant" & done
  wait
  # RED under the mutant: 30 separate markers, which is 30 operator-visible facts for one event.
  [ "$(markers)" -eq 30 ] || false
}
