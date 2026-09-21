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
  # 0.85 sits below the measured 0.90 default. This case used to pin 0.97, which was only
  # "below threshold" while the default was the unreachable 0.98 — the constant and its own
  # test moved together, so neither could catch that the arm could never fire.
  run jev_bool_confident '{"answers":{"q":{"type":"boolean","probability":0.85}}}' q
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
  # Compare PHYSICAL paths. The resolver uses `cd -P`, and a checkout under /tmp reaches it via
  # /private/tmp on macOS — so a literal string compare fails on a correct resolution. Comparing
  # logical paths here would make this guard fire on the harness rather than on the subject.
  [ "$output" = "$(cd -P "$REPO" && pwd)" ]
  [ -d "$output/node_modules/ai" ]
}

# ── THE SECRET SOURCE ────────────────────────────────────────────────────────────────────────
# This machine keeps secrets in `agent-secrets` (sops + age, names-only), whose golden rule 3 is
# "to use a secret, inject it — don't read it". An `export AI_GATEWAY_API_KEY=…` in a shell
# profile is the exact plaintext-on-disk leak that tool exists to prevent, so the library has to
# resolve a key it will never see. These pin which path it picks, because picking the wrong one
# is silent: `none` just reads as "not configured yet".
# A stub `agent-secrets` whose `list` prints exactly what we want the resolver to see. Built as
# a real file in the test body rather than inside a nested bash -c string: the nesting is what
# broke the first draft of these two tests, and a fixture that is hard to read is a fixture whose
# failures get misread.
mkstub() {   # $1 = dir, $2 = the line `list` prints
  mkdir -p "$1"
  printf '#!/usr/bin/env bash\necho %s\n' "$(printf '%q' "$2")" > "$1/agent-secrets"
  chmod +x "$1/agent-secrets"
}

@test "secret source: an env var already present is used directly — no extra fork" {
  run bash -c ". '$REPO/hooks/lib/jev.sh'; export AI_GATEWAY_API_KEY=dummy; jev_secret_source"
  [ "$output" = "env" ]
}

@test "secret source: none when there is no env var and no store entry" {
  run env -u AI_GATEWAY_API_KEY PATH=/usr/bin:/bin bash -c ". '$REPO/hooks/lib/jev.sh'; jev_secret_source"
  [ "$output" = "none" ]
}

@test "secret source: agent-secrets is chosen when the store HOLDS the name" {
  mkstub "$BATS_TEST_TMPDIR/sb" "  * AI_GATEWAY_API_KEY"
  run env -u AI_GATEWAY_API_KEY "PATH=$BATS_TEST_TMPDIR/sb:/usr/bin:/bin" \
      bash -c ". '$REPO/hooks/lib/jev.sh'; jev_secret_source"
  [ "$output" = "agent-secrets" ]
}

# The negative arm, and it is the one that matters: a store that exists but does NOT carry this
# name must resolve to `none`, not to agent-secrets. Otherwise every call would pay the ~230 ms
# wrapper and then abstain `no-key` anyway — a silent tax on a path that can never succeed.
@test "secret source: a store WITHOUT the name is none, not agent-secrets" {
  mkstub "$BATS_TEST_TMPDIR/sb2" "  * SOMETHING_ELSE"
  run env -u AI_GATEWAY_API_KEY "PATH=$BATS_TEST_TMPDIR/sb2:/usr/bin:/bin" \
      bash -c ". '$REPO/hooks/lib/jev.sh'; jev_secret_source"
  [ "$output" = "none" ]
}

# ── `cc-jev status` — CONFIGURED IS NOT ANSWERING ────────────────────────────────────────────
# Added 2026-09-20 after the arm was found 100% inert in production while every status field read
# healthy. The old ENABLED branch asserted "the semantic arm ... is live" from CONFIGURATION alone,
# and on a hobby plan that sentence was false on every call: ZDR is Pro/Enterprise-only and fails
# closed, so the gateway returned HTTP 403 and the arm abstained every time. These pin the two
# halves the fix added — the reachability verdict, and a free-window line that EXPIRES instead of
# asserting a past date forever. Status must stay a STATIC read, so none of this spends egress.
# REACHING THE ENABLED BRANCH IS THE WHOLE DIFFICULTY, and getting it wrong makes these vacuous.
# setup() fixtures $HOME, so `agent-secrets` is absent, jev_secret_source returns `none`, and the
# DISABLED branch renders. A first draft of these ran there: the "block is present" case failed
# honestly, but the "block is ABSENT" case PASSED — a branch that renders nothing satisfies every
# absence assertion. That is this repo's vacuous-control shape exactly, caught here only because
# its sibling failed loudly. The seam is AI_GATEWAY_API_KEY, which jev_secret_source reads FIRST;
# `status` makes no call, so a dummy value sends nothing anywhere. Every case below asserts the
# ENABLED marker as a POSITIVE CONTROL, so falling back into DISABLED now FAILS instead of passing.
# EVERY DATE HERE IS SEEDED RELATIVE TO NOW. The wall-clock ratchet refused this file's first
# version for defaulting to the literal 2026-09-25, and it was right: the subject re-derives the
# remaining days from that stamp, so an absolute future date silently changes what the fixture
# MEANS as the clock advances, and the suite flips branch on a calendar boundary with no code
# change. A past date is safe (it stays past); a future one must be computed.
status_out() {
  AI_GATEWAY_API_KEY=dummy-not-a-real-key \
  CC_JEV_FREE_UNTIL="${CC_JEV_FREE_UNTIL:-$(date -u -v+30d +%Y-%m-%d)}" \
  "$REPO/bin/cc-jev" status 2>&1
}

@test "cc-jev status: ZDR on never claims the arm is live, and names the plan as the blocker" {
  run status_out
  [ "$status" -eq 0 ]
  grep -qF "CONFIGURED —" <<<"$output"   # positive control: we really are in the ENABLED branch
  # The exact false sentence the fix removed. Its return is the regression this test exists for.
  ! grep -qF "is live" <<<"$output" || { echo "status claimed liveness from configuration"; false; }
  grep -qF "CONFIGURED IS NOT ANSWERING" <<<"$output"
  grep -qF "403" <<<"$output"
  # 2026-09-21: this case used to require the TWO REMEDIES be named — "buy Pro" and "run with
  # CC_JEV_ZDR=0". Both were removed deliberately, and the removal is the point: they were the
  # options of decision packet c3752f5fca96, which the pilot ANSWERED and which is now actioned.
  # A status offering a closed decision's options is the stale-guidance defect the verdict block
  # below was added to fix, so asserting their presence would pin the bug in place. The remaining
  # assertions are the durable ones: no liveness claim, and the blocker named with its symptom.
}

@test "cc-jev status: CC_JEV_ZDR=0 removes the not-answering block (the blocker is gone)" {
  CC_JEV_ZDR=0 run status_out
  [ "$status" -eq 0 ]
  grep -qF "CONFIGURED —" <<<"$output"   # positive control — without it this case is vacuous
  ! grep -qF "CONFIGURED IS NOT ANSWERING" <<<"$output" \
    || { echo "warned about a blocker that ZDR=0 removes"; false; }
}

@test "cc-jev status: the free window counts DOWN while it is open" {
  local open; open="$(date -u -v+45d +%Y-%m-%d)"   # relative, per the wall-clock ratchet
  CC_JEV_FREE_UNTIL="$open" run status_out
  [ "$status" -eq 0 ]
  grep -qF "Free on the Gateway until $open" <<<"$output"
  grep -qF "day(s) left" <<<"$output"
}

# THE ARM THE OLD SENTENCE COULD NOT HAVE: a hardcoded "free until <date>" goes on claiming free
# after the date passes. This is the falsifier for that whole class.
@test "cc-jev status: a LAPSED free window says CLOSED and prices the metered rate" {
  CC_JEV_FREE_UNTIL="2000-01-01" run status_out
  [ "$status" -eq 0 ]
  grep -qF "Free window CLOSED" <<<"$output"
  ! grep -qF "day(s) left" <<<"$output" || { echo "counted down a window already closed"; false; }
  grep -qF '$0.042/MTok' <<<"$output"
}

# ── `cc-jev status` — THE VERDICT, and why a stale "next step" is a real defect ───────────────
# Added 2026-09-21. The 2026-09-20 fix stopped `status` asserting liveness it had not checked.
# Within a day the same command was advertising "Next: cc-jev pilot (score it on real closes)" and
# citing decision packet c3752f5fca96 as a live trade — after the pilot had run TWICE over 198 real
# closes and the packet had been actioned. The operator ran it and was handed a closed decision as
# an open one. Stale GUIDANCE is the same family as a stale ASSERTION, so it gets the same pinning.
@test "cc-jev status: states the RETIRED verdict and stops advertising the pilot as next" {
  run status_out
  [ "$status" -eq 0 ]
  grep -qF "CONFIGURED —" <<<"$output"                       # positive control: ENABLED branch
  grep -qF "THE ARM IS RETIRED" <<<"$output"
  grep -qF "Addendum 4" <<<"$output"                          # the receipt, not just the claim
  # The exact stale guidance this test exists to keep out.
  ! grep -qF "then cc-jev pilot" <<<"$output" \
    || { echo "still advertising a pilot that has already run twice"; false; }
}

@test "cc-jev status: RETIRED is not OFF — it names the per-close cost and the lever" {
  run status_out
  [ "$status" -eq 0 ]
  grep -qF "RETIRED IS NOT OFF" <<<"$output"
  grep -qF "CC_JEV=0" <<<"$output"
}

# THE REVIVAL ARM. Without it the verdict text is unconditional and a future session that revives
# the arm would have to DELETE a block rather than flip a switch — and would likely leave it.
@test "cc-jev status: CC_JEV_RETIRED=0 restores the pilot guidance and drops the verdict" {
  CC_JEV_RETIRED=0 run status_out
  [ "$status" -eq 0 ]
  grep -qF "CONFIGURED —" <<<"$output"                       # positive control
  grep -qF "then cc-jev pilot" <<<"$output"
  ! grep -qF "THE ARM IS RETIRED" <<<"$output" \
    || { echo "claimed retired while revived"; false; }
}

# ── `cc-jev rank` — the memory-index ranker ──────────────────────────────────────────────────
# Added 2026-09-21. This is the FIRST consumer of Jev that is not the retired deference arm, and
# it exists because MEMORY.md is at a hard cap where the loader silently drops the newest entries,
# so every append is already an eviction decision — taken today on structural proxies because
# nothing could read the entries themselves.
#
# 🚨 IT USES `choice`, NOT `score`, AND THAT IS A MEASURED CONSTRAINT. `score` is declared in the
# SDK's own types with exactly the answer shape tests/fixtures/jev-mock-gateway.mjs returns
# ({type:'score', score:<index>}), and the round trip is STILL rejected `invalid-response` while a
# boolean through the identical path succeeds — so the runtime schema is stricter than the
# published type. `choice` over ORDERED keys carries the same ordinal and is the primitive already
# exercised by 198 real calls. If `score` ever starts validating, the ordering must stay in the
# script rather than move into the model.
mkmem() {  # → a throwaway memory dir; nothing real is ever read or sent
  MEMD="$BATS_TEST_TMPDIR/mem"; mkdir -p "$MEMD"
  printf -- '- [Alpha](alpha.md) — durable\n- [Beta](beta.md) — one-off\n' > "$MEMD/MEMORY.md"
  printf 'alpha body\n' > "$MEMD/alpha.md"; printf 'beta body\n' > "$MEMD/beta.md"
}

@test "cc-jev rank: refuses to send without --yes, and sends nothing" {
  mkmem
  run env AI_GATEWAY_API_KEY=dummy "$REPO/bin/cc-jev" rank --mem "$MEMD"
  [ "$status" -eq 3 ]
  grep -qF "Re-run with --yes" <<<"$output"
  grep -qF "Nothing has been sent" <<<"$output"
}

@test "cc-jev rank: ranks every resolvable entry and writes rows" {
  mkmem
  # MOCK_CHOICE must be exported BEFORE start_mock: it steers the MOCK PROCESS, and a first draft
  # passed it to the CLIENT instead, where it did nothing. The run still printed "SCORED 2 of 2",
  # so only the level assertion caught it — a fixture knob set on the wrong side of the wire fails
  # silently, in the direction of "the default was fine".
  export MOCK_CHOICE=occasionally
  start_mock ok
  run env AI_GATEWAY_API_KEY=dummy CC_JEV_BASE_URL="http://127.0.0.1:$PORT" \
      CC_JEV_RANK_GAP=0 "$REPO/bin/cc-jev" rank --mem "$MEMD" --yes
  [ "$status" -eq 0 ]
  grep -qF "SCORED 2 of 2" <<<"$output"
  grep -qF "occasionally" <<<"$output"
  # It must never edit the index — the whole safety case is that eviction stays a human read.
  grep -qF "Nothing was edited" <<<"$output"
  run grep -c 'alpha.md' "$MEMD/MEMORY.md"
  [ "$output" = "1" ]
}

@test "cc-jev rank: an index whose targets are all MISSING refuses rather than ranking nothing" {
  MEMD="$BATS_TEST_TMPDIR/mem2"; mkdir -p "$MEMD"
  printf -- '- [Ghost](ghost.md) — target does not exist\n' > "$MEMD/MEMORY.md"
  run env AI_GATEWAY_API_KEY=dummy "$REPO/bin/cc-jev" rank --mem "$MEMD" --yes
  [ "$status" -eq 3 ]
  grep -qF "REFUSING" <<<"$output"
}
