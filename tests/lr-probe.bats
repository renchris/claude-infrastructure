#!/usr/bin/env bats
# scripts/limit-recover/lr-probe.sh — D5's connectivity control (T6/W2-C, probe half).
#
# Hermetic: every case drives a STUB curl through LR_PROBE_CURL. Nothing here touches
# the network, so the suite is a statement about the probe's LOGIC, which is where
# every failure mode below actually lives.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PROBE="$REPO/scripts/limit-recover/lr-probe.sh"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export LR_PROBE_LOG="$BATS_TEST_TMPDIR/probe.log"
  export LR_PROBE_GAP_S=0          # the gap is tested explicitly; elsewhere it is dead time
  export LR_PROBE_CURL="$BATS_TEST_TMPDIR/curl"
  # EXPORTED, because stub_curl_seq's body is a QUOTED heredoc and reads these at
  # run time rather than having them baked in. Unexported, its counter wrote
  # nowhere and `calls` reported 0 samples for a stub that had run twice.
  export COUNT="$BATS_TEST_TMPDIR/count"; : > "$COUNT"
}

# A curl stub that answers with $1 (the http_code it should print) and exits $2.
stub_curl() { # $1=code $2=exit
  cat > "$LR_PROBE_CURL" <<SH
#!/bin/bash
echo x >> "$COUNT"
printf '%s' "$1"
exit $2
SH
  chmod +x "$LR_PROBE_CURL"
}

# A stub whose answer CHANGES between calls, from a scripted list.
stub_curl_seq() { # $@ = "code:exit" per call, last one repeats
  printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/seq"
  cat > "$LR_PROBE_CURL" <<'SH'
#!/bin/bash
echo x >> "$COUNT"
n=$(wc -l < "$COUNT" | tr -d ' ')
line="$(sed -n "${n}p" "$SEQ")"
[ -n "$line" ] || line="$(tail -1 "$SEQ")"
printf '%s' "${line%%:*}"
exit "${line##*:}"
SH
  chmod +x "$LR_PROBE_CURL"
  export SEQ="$BATS_TEST_TMPDIR/seq"
}

calls() { wc -l < "$COUNT" | tr -d ' '; }

# ════════════════════════════════════════════════════════════════════════════════
# THE CENTRAL CLAIM: any HTTP status is green, because the request is unauthenticated
# ════════════════════════════════════════════════════════════════════════════════

@test "P-a: a 401 is GREEN — an unauthenticated request is SUPPOSED to be refused, and a refusal that travelled the whole path proves the path works" {
  stub_curl 401 0
  run bash "$PROBE" --once
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -q 'GREEN' || { echo "$output"; false; }
}

@test "P-a2: 403, 404, 405 and 200 are ALL green — the STATUS is not the question" {
  # THE TRAP THIS PINS: keying green on 200 would build a gate with NO ACCEPTING
  # PATH. The probe sends no credentials, so 200 is the one answer it will never
  # get in production — the stall policy would be unreachable by construction and
  # the failure would read as "the network is still down", forever.
  for c in 200 204 400 401 403 404 405 429 500 503; do
    : > "$COUNT"; stub_curl "$c" 0
    run bash "$PROBE" --once
    [ "$status" -eq 0 ] || { echo "http $c was not green: $output"; false; }
  done
}

@test "P-b: a TRANSPORT failure is RED — curl exit 6 (DNS) with no response" {
  stub_curl 000 6
  run bash "$PROBE" --once
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'RED' || { echo "$output"; false; }
}

@test "P-b2: connect-refused, timeout and TLS failures are all RED" {
  for rc in 7 28 35; do
    : > "$COUNT"; stub_curl 000 "$rc"
    run bash "$PROBE" --once
    [ "$status" -eq 1 ] || { echo "curl rc $rc was not red: $output"; false; }
  done
}

@test "P-b3: a NON-ZERO curl exit is RED even if a status somehow printed — the two conditions are AND, not OR" {
  stub_curl 401 28
  run bash "$PROBE" --once
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "P-b4: http_code 000 with curl exit 0 is RED — 000 is curl's 'no response received'" {
  stub_curl 000 0
  run bash "$PROBE" --once
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

# ════════════════════════════════════════════════════════════════════════════════
# HYSTERESIS, and its deliberate asymmetry
# ════════════════════════════════════════════════════════════════════════════════

@test "P-c: the default needs TWO greens — one green alone is not a verdict" {
  stub_curl 401 0
  run bash "$PROBE"
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 2 ] || { echo "expected 2 samples, got $(calls)"; false; }
  echo "$output" | grep -q '2/2' || { echo "$output"; false; }
}

@test "P-c2: green then RED is RED — a link that flaps has not recovered" {
  # This is the whole reason for hysteresis: one green is a coin flip on a link
  # that is coming back up.
  stub_curl_seq '401:0' '000:7'
  run bash "$PROBE"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(calls)" -eq 2 ] || { echo "expected 2 samples, got $(calls)"; false; }
}

@test "P-c3: red FIRST returns immediately — it never sleeps out the gap for a link already known down" {
  # The asymmetry: a red already answers the question, so waiting buys nothing.
  # Measured, because a 'return immediately' claim that is not timed is an assertion.
  stub_curl 000 7
  export LR_PROBE_GAP_S=8
  t0=$(date +%s)
  run bash "$PROBE"
  t1=$(date +%s)
  [ "$status" -eq 1 ]
  [ "$(calls)" -eq 1 ] || { echo "a red took $(calls) samples; it should stop at 1"; false; }
  [ $(( t1 - t0 )) -lt 5 ] || { echo "a red slept the gap: $(( t1 - t0 ))s"; false; }
}

@test "P-c4 CONTROL: two greens DO wait the gap — so the previous test measured the asymmetry, not a probe that never sleeps" {
  # Without this arm, P-c3 passes for a probe with no hysteresis at all.
  stub_curl 401 0
  export LR_PROBE_GAP_S=3
  t0=$(date +%s)
  run bash "$PROBE"
  t1=$(date +%s)
  [ "$status" -eq 0 ]
  [ $(( t1 - t0 )) -ge 3 ] || { echo "the gap was not waited: $(( t1 - t0 ))s"; false; }
}

@test "P-c5: --once takes exactly ONE sample and no gap, whatever --samples says" {
  stub_curl 401 0
  run bash "$PROBE" --once --samples 5
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 1 ] || { echo "--once took $(calls) samples"; false; }
}

@test "P-c6: --samples N requires N greens" {
  stub_curl 401 0
  run bash "$PROBE" --samples 4
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 4 ] || { echo "expected 4, got $(calls)"; false; }
}

# ════════════════════════════════════════════════════════════════════════════════
# It spends nothing, it can never hang, and its refusals are auditable
# ════════════════════════════════════════════════════════════════════════════════

@test "P-d: the request carries NO credential of any kind and asks for no body" {
  cat > "$LR_PROBE_CURL" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$ARGV_LOG"
printf '401'
SH
  chmod +x "$LR_PROBE_CURL"
  export ARGV_LOG="$BATS_TEST_TMPDIR/argv"; : > "$ARGV_LOG"
  run bash "$PROBE" --once
  [ "$status" -eq 0 ]
  # Nothing authenticating: a probe that needed the account could not tell a quota
  # wall from an unreachable network, which is the distinction it exists to make.
  # NOT the bare word "anthropic" — that is in the URL by construction, and an
  # earlier draft of this list reddened on the endpoint it is supposed to probe.
  for bad in '-H' '--header' '--user' '-u' '--netrc' 'Authorization' 'x-api-key' \
             'API_KEY' 'OAUTH_TOKEN' 'sk-ant' 'Bearer'; do
    if grep -qi -- "$bad" "$ARGV_LOG"; then
      echo "the probe passed '$bad': $(cat "$ARGV_LOG")"; false
    fi
  done
  # And no request BODY: a HEAD with a payload would be a request the API could bill.
  for bad in '--data' '-d ' '--json'; do
    if grep -q -- "$bad" "$ARGV_LOG"; then
      echo "the probe sent a body via '$bad': $(cat "$ARGV_LOG")"; false
    fi
  done
  # HEAD, and a hard timeout — an outage looks exactly like a hung TLS handshake.
  grep -q -- '-I' "$ARGV_LOG" || { cat "$ARGV_LOG"; false; }
  grep -q -- '--max-time' "$ARGV_LOG" || { cat "$ARGV_LOG"; false; }
}

@test "P-e: EVERY sample is logged, green and red alike" {
  # A control whose firings are invisible cannot have its precision computed later:
  # a ledger holding only the passes can never answer "how often did this refuse,
  # and was it right?"
  stub_curl 401 0
  run bash "$PROBE"
  grep -q 'verdict=green' "$LR_PROBE_LOG" || { cat "$LR_PROBE_LOG"; false; }
  : > "$LR_PROBE_LOG"; : > "$COUNT"; stub_curl 000 7
  run bash "$PROBE" --once
  grep -q 'verdict=RED' "$LR_PROBE_LOG" || { cat "$LR_PROBE_LOG"; false; }
}

@test "P-f: a MISSING probe binary is RED but is reported as UNMEASURED, never as 'the network is down'" {
  # Withholding the green is the safe direction — but the reason must be the
  # instrument, not the subject. A refusal that names the wrong cause becomes the
  # next reader's hypothesis.
  export LR_PROBE_CURL="$BATS_TEST_TMPDIR/definitely-not-here"
  run bash "$PROBE" --once
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'UNMEASURED' || { echo "$output"; false; }
  echo "$output" | grep -q "do not read this as 'the network is down'" || { echo "$output"; false; }
}

@test "P-g: --json emits one parseable object with the verdict and the sample count" {
  stub_curl 401 0
  run bash "$PROBE" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["verdict"]=="green", d
assert d["greens"]==2 and d["needed"]==2, d
assert d["http_code"]=="401", d
'
}

@test "P-g2: --json on a red is also parseable, and says red" {
  stub_curl 000 7
  run bash "$PROBE" --json
  [ "$status" -eq 1 ]
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["verdict"]=="red", d
assert d["curl_rc"]==7, d
'
}

@test "P-h: the GREEN message says the probe is NECESSARY and NOT SUFFICIENT" {
  # A green must not read as permission to re-fire. The wait verdicts still forbid
  # touching a unit a live process holds, and this text is where a reader meets that.
  stub_curl 401 0
  run bash "$PROBE"
  echo "$output" | grep -q 'NOT SUFFICIENT' || { echo "$output"; false; }
  echo "$output" | grep -q 'UNSETTLED-INFLIGHT' || { echo "$output"; false; }
  echo "$output" | grep -q 'zero quota' || { echo "$output"; false; }
}

@test "P-i: a bad --samples is a usage error (exit 2), not a silent default" {
  stub_curl 401 0
  run bash "$PROBE" --samples 0
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  run bash "$PROBE" --samples abc
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  run bash "$PROBE" --nonsense
  [ "$status" -eq 2 ] || { echo "$output"; false; }
}
