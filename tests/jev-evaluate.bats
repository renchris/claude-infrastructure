#!/usr/bin/env bats
# jev-evaluate — the exit-code contract of scripts/jev/evaluate.mjs and hooks/lib/jev.sh.
#
# WHAT THIS SUITE IS FOR. The whole safety case for wiring Jev into a Stop hook rests on ONE
# property: every way the call can fail produces ABSTAIN, and abstain is distinguishable from
# an answer. If a network fault could be read as "Jev says false", a hook would act on a dead
# gateway's silence. This repo has two standing lessons about precisely that collapse —
# `null-result-must-not-use-the-error-channel` and
# `predicate-error-exit-is-indistinguishable-from-false` (20 of 20 rows lied) — so the contract
# is tested branch by branch rather than asserted in a comment.
#
# 🚨 THE LIMIT, STATED SO IT CANNOT BE MISREAD AS COVERAGE: these tests run against a LOCAL mock
# built to @ai-sdk/gateway's own request/response shape. They prove OUR half — request assembly,
# ZDR propagation, answer parsing, classification, thresholding. They prove NOTHING about Jev's
# real behaviour or accuracy. Zero Jev calls have been made from this machine
# (docs/research/jev-at-cost-api-2026-09-18.md §5). A green suite here is "the plumbing is
# correct", never "Jev works for this task".

setup() {
  # Fixture $HOME before anything else. The subject reads and writes under ~/ (state dirs,
  # the IDL, decision packets), so an unfixtured suite would run against the operator's live
  # tree and make every result in this file untrustworthy — the land gate's
  # test-hermeticity ratchet refuses the land for exactly this, and it was right to.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  EVAL="$REPO/scripts/jev/evaluate.mjs"
  MOCK="$REPO/tests/fixtures/jev-mock-gateway.mjs"
  SPEC='{"state":"s","questions":{"q":{"type":"boolean","instructions":"ok?"}}}'
  command -v node >/dev/null || skip "node not installed"
  [ -d "$REPO/node_modules/ai" ] || skip "deps not installed (npm install) — runtime degrades to abstain, which is tested separately"
}

# Boot the mock and export PORT at SHELL level. An env-prefix assignment would bind only to the
# command it prefixes, and a later "$PORT" would read EMPTY — the empty-selector shape this repo
# already lost a fleet to (memory empty-selector-is-a-universal-selector).
start_mock() {
  PORTF="$BATS_TEST_TMPDIR/port.$$"
  MOCK_ECHO="${MOCK_ECHO:-}" node "$MOCK" "$1" > "$PORTF" &
  MPID=$!
  local _
  for _ in $(seq 1 25); do [ -s "$PORTF" ] && break; sleep 0.2; done
  PORT="$(tr -d '[:space:]' < "$PORTF")"
  [ -n "$PORT" ] || { echo "mock failed to bind"; return 1; }
}
# `|| true` guards the STATUS, not just the noise: under bats' errexit a kill whose target
# was already reaped returns 1 and aborts the body, so a test that passed on its own merits
# goes red under load — and only under load. A trailing `; return 0` does not shield it.
teardown() { [ -n "${MPID:-}" ] && { kill "$MPID" 2>/dev/null || true; }; return 0; }

# Args are OPTIONAL env-prefix overrides (e.g. CC_JEV_TIMEOUT_MS=700); most callers pass none,
# which is the intended use, not an omission.
# shellcheck disable=SC2120
ask() { printf '%s' "$SPEC" | env AI_GATEWAY_API_KEY=dummy CC_JEV_BASE_URL="http://127.0.0.1:$PORT" "$@" node "$EVAL"; }

@test "answered: exit 0 and a typed answer" {
  start_mock ok
  run ask
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok":true'* ]] || false
  [[ "$output" == *'"probability":0.99'* ]]
}

@test "ZDR is on the wire, not just in the source" {
  export MOCK_ECHO="$BATS_TEST_TMPDIR/echo.json"
  start_mock ok
  ask >/dev/null
  run jq -r '.providerOptions.gateway.zeroDataRetention' "$MOCK_ECHO"
  [ "$output" = "true" ]
}

@test "CC_JEV_ZDR=0 is the ONLY way retention is given up, and it is explicit" {
  export MOCK_ECHO="$BATS_TEST_TMPDIR/echo0.json"
  start_mock ok
  printf '%s' "$SPEC" | env AI_GATEWAY_API_KEY=dummy CC_JEV_ZDR=0 \
    CC_JEV_BASE_URL="http://127.0.0.1:$PORT" node "$EVAL" >/dev/null
  # providerOptions itself arrives as {} — the SDK defaults it — so the flag, not the
  # container, is what must be absent. Asserting on the container passed for the wrong reason.
  run jq -r '.providerOptions.gateway.zeroDataRetention // "absent"' "$MOCK_ECHO"
  [ "$output" = "absent" ]
}

@test "no key: abstain 10, and it costs no node-side work" {
  run bash -c "printf '%s' '$SPEC' | env -u AI_GATEWAY_API_KEY node '$EVAL'"
  [ "$status" -eq 10 ]
  [[ "$output" == *'"reason":"no-key"'* ]]
}

@test "server error: abstain 10, NEVER a false answer" {
  start_mock err500
  run ask
  [ "$status" -eq 10 ]
  [[ "$output" == *'"ok":false'* ]]
}

@test "auth rejection is classified as no-key, not as a network blip" {
  start_mock err401
  run ask
  [ "$status" -eq 10 ]
  [[ "$output" == *'"reason":"no-key"'* ]]
}

@test "unparseable response: abstain 10, never a partial answer" {
  start_mock garbage
  run ask
  [ "$status" -eq 10 ]
  [[ "$output" != *'"ok":true'* ]]
}

@test "hang: the caller's clock wins, and it is ONE clock not three" {
  start_mock slow
  local t0 t1
  t0=$(date +%s)
  run ask CC_JEV_TIMEOUT_MS=700
  t1=$(date +%s)
  [ "$status" -eq 10 ]
  [[ "$output" == *'"reason":"timeout"'* ]] || false
  # maxRetries:0 is the point — with the SDK's default of 2 this is ~3x the budget.
  [ $((t1 - t0)) -lt 3 ]
}

@test "bad spec is exit 2, distinct from abstain: the caller is wrong, not the network" {
  run bash -c "echo 'not json' | env AI_GATEWAY_API_KEY=dummy node '$EVAL'"
  [ "$status" -eq 2 ]
  run bash -c "echo '{\"state\":\"s\",\"questions\":{}}' | env AI_GATEWAY_API_KEY=dummy node '$EVAL'"
  [ "$status" -eq 2 ]
}

# ── hooks/lib/jev.sh ────────────────────────────────────────────────────────────────────────
@test "jev_available is false with no key, so a hook never forks node for nothing" {
  run bash -c ". '$REPO/hooks/lib/jev.sh'; unset AI_GATEWAY_API_KEY; jev_available"
  [ "$status" -ne 0 ]
}

@test "CC_JEV=0 kills it even with a key present" {
  run bash -c ". '$REPO/hooks/lib/jev.sh'; export AI_GATEWAY_API_KEY=dummy CC_JEV=0; jev_available"
  [ "$status" -ne 0 ]
}

# THE SUBSHELL REGRESSION GUARD. jev_ask is called on the right of a PIPE here deliberately:
# that is the shape that runs it in a subshell, and the first draft of jev.sh reported its
# abstain class through a global that the subshell discarded. Keep the pipe.
@test "jev_ask reports its reason THROUGH THE PIPE, not via a global a subshell eats" {
  run bash -c ". '$REPO/hooks/lib/jev.sh'; unset AI_GATEWAY_API_KEY
               out=\$(printf '%s' '$SPEC' | jev_ask); rc=\$?
               echo \"rc=\$rc reason=\$(jev_reason \"\$out\")\""
  [[ "$output" == *"rc=1"* ]] || false
  [[ "$output" == *"reason=unavailable"* ]]
}

@test "oversize state is refused BEFORE the network, mechanically not by prose" {
  run bash -c ". '$REPO/hooks/lib/jev.sh'; export AI_GATEWAY_API_KEY=dummy CC_JEV_MAX_STATE_B=10
               out=\$(printf '%s' '$SPEC' | jev_ask); echo \"reason=\$(jev_reason \"\$out\")\""
  [[ "$output" == *"reason=oversize"* ]]
}

@test "jev_bool_confident fires only in the calibrated tail" {
  . "$REPO/hooks/lib/jev.sh"
  run jev_bool_confident '{"answers":{"q":{"type":"boolean","probability":0.99}}}' q
  [ "$status" -eq 0 ]
  # 0.5 is MAXIMUM UNCERTAINTY, not a weak yes — the type says "P(true), not confidence".
  run jev_bool_confident '{"answers":{"q":{"type":"boolean","probability":0.5}}}' q
  [ "$status" -ne 0 ]
  run jev_bool_confident '{"answers":{"q":{"type":"boolean","probability":0.97}}}' q
  [ "$status" -ne 0 ]
  # a missing answer is not a yes
  run jev_bool_confident '{"answers":{}}' q
  [ "$status" -ne 0 ]
}

# THE LIVE-LAYER GUARD. ~/.claude is a per-file symlink farm over this checkout, so every hook
# sources this library through a symlink. The first draft resolved its root with a plain
# dirname/../.. and therefore pointed at ~/.claude, which has no node_modules — `jev_available`
# would have returned false forever in production, silently, because "unavailable" is a
# legitimate state that logs nothing alarming. Caught only by resolving the link.
@test "root resolution follows the symlink, so deps are visible from the live layer" {
  local link="$BATS_TEST_TMPDIR/live/hooks/lib"
  mkdir -p "$link"
  ln -s "$REPO/hooks/lib/jev.sh" "$link/jev.sh"
  run bash -c ". '$link/jev.sh'; echo \"\$CC_JEV_LIB_ROOT\""
  [ "$output" = "$REPO" ]
  [ -d "$output/node_modules/ai" ]
}
