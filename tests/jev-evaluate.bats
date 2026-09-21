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
# 🚨 IT USES `choice`, NOT `score` — AND THE REASON WRITTEN HERE UNTIL 2026-09-21 WAS FALSE.
# It claimed `score` was "rejected invalid-response … so the runtime schema is stricter than the
# published type", i.e. a fact about the vendor. That round trip never left 127.0.0.1: the SDK's
# client-side validateEvaluationAnswers demands a COMPLETE probability distribution over every
# level index, and this file's own mock emitted ONE key for score while emitting the full map for
# choice. A local A/B settles it — one key -> invalid-response, complete map -> ok, through
# evaluate.mjs unmodified. `score` is not blocked; our test double was.
# `choice` stays anyway, and for a reason that survives: the score QUESTION shape (criteria as an
# ARRAY) has still never been sent to the real route, while `choice` over an ordered MAP is what
# 198 real calls have exercised. The ordering lives in rank_order() either way, never in the model.
# Receipt: docs/research/jev-100p-2026-09-21/a9-operating-envelope.md §5.
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
  # CC_JEV_ZDR=0 is REQUIRED here now, and that is the point of the guard added 2026-09-21: with
  # ZDR at its default the run refuses before the first call rather than scoring nothing 146 times.
  run env AI_GATEWAY_API_KEY=dummy CC_JEV_BASE_URL="http://127.0.0.1:$PORT" \
      CC_JEV_ZDR=0 CC_JEV_RANK_GAP=0 "$REPO/bin/cc-jev" rank --mem "$MEMD" --yes
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

# THE GUARDS THAT THE FIRST REAL RUN EARNED. `cc-jev rank --yes` was shipped and run against the
# live index with ZDR at its default: every one of 146 calls returned HTTP 403, `lvl` came back
# empty, and each was counted as a SILENT skip. It would have run ~70 minutes and printed
# "SCORED 0 of 146" — a well-formatted verdict over a path that never worked, and unreadable
# against "Jev had no opinion". Killed at 224 calls, 0 rows. Both arms below are that incident.
@test "cc-jev rank: ZDR on refuses BEFORE the first call and names the exact command" {
  mkmem
  run env AI_GATEWAY_API_KEY=dummy "$REPO/bin/cc-jev" rank --mem "$MEMD" --yes
  [ "$status" -eq 4 ]
  grep -qF "REFUSING before the first call" <<<"$output"
  grep -qF "CC_JEV_ZDR=0 cc-jev rank --yes" <<<"$output"   # the command, runnable as printed
  grep -qF "Nothing has been sent" <<<"$output"
}

# The static guard names ONE known blocker; this catches every other way the route can be dead —
# revoked key, gateway down, allowlist change — by ASKING once instead of assuming.
@test "cc-jev rank: a dead route aborts at the preflight, naming the reason" {
  mkmem
  run env AI_GATEWAY_API_KEY=dummy CC_JEV_ZDR=0 CC_JEV_BASE_URL="http://127.0.0.1:1" \
      CC_JEV_RANK_GAP=0 "$REPO/bin/cc-jev" rank --mem "$MEMD" --yes
  [ "$status" -eq 4 ]
  grep -qF "preflight call produced no verdict" <<<"$output"
  grep -qF "reason: http" <<<"$output"      # the reason, not a generic failure
  grep -qF "Nothing has been sent" <<<"$output"
}

# ── the BREADTH question, added 2026-09-21 ───────────────────────────────────────────────────
# WHY A THIRD QUESTION RATHER THAN A REPLACEMENT RUBRIC. The first real run scored 140 rules and
# put 118 of them (84%) in `often`, with `superseded` at p90 0.39 and 2 rows above 0.70. Every
# verdict was defensible and the RANKING was worthless: a question returning one answer for 84% of
# a population has not ranked it. Swapping `bite` out for a new rubric would have traded one
# unvalidated question for another, so `breadth` runs BESIDE it and the run reports the max-bucket
# share of each — one pass measures whether the fix worked. Same disease as Addendum 4's arm
# (a property of the population, not of the model), caught this time by the run itself.
mkmem5() {  # 5 entries, so a 4-key rotation produces a real spread
  MEMD="$BATS_TEST_TMPDIR/mem5"; mkdir -p "$MEMD"; : > "$MEMD/MEMORY.md"
  for n in a b c d e; do
    printf -- '- [%s](%s.md) — hook for %s\n' "$n" "$n" "$n" >> "$MEMD/MEMORY.md"
    printf 'body of %s\n' "$n" > "$MEMD/$n.md"
  done
}

@test "cc-jev rank: breadth is asked BESIDE bite and both land in the row, steered apart" {
  mkmem
  # Disjoint key sets are the point: a single global MOCK_CHOICE would match bite and silently
  # fall back to keys[0] for breadth, so this asserts the per-question knob really separates them.
  export MOCK_CHOICE_BITE=nearly-always MOCK_CHOICE_BREADTH=one-tool
  start_mock ok
  run env AI_GATEWAY_API_KEY=dummy CC_JEV_BASE_URL="http://127.0.0.1:$PORT" \
      CC_JEV_ZDR=0 CC_JEV_RANK_GAP=0 "$REPO/bin/cc-jev" rank --mem "$MEMD" --yes
  [ "$status" -eq 0 ]
  ROWS_FILE=$(grep -o '/.*jev-rank-.*\.jsonl' <<<"$output" | tail -1)
  [ -s "$ROWS_FILE" ]
  # BOTH fields, with the values each was steered to — not one value appearing twice.
  [ "$(jq -r '.breadth' "$ROWS_FILE" | sort -u)" = "one-tool" ]
  [ "$(jq -r '.level'   "$ROWS_FILE" | sort -u)" = "nearly-always" ]
}

@test "cc-jev rank: a NEAR-CONSTANT question is named as such in the output" {
  mkmem5
  export MOCK_CHOICE_BITE=often MOCK_CHOICE_BREADTH=one-domain     # 100% one bucket, both
  start_mock ok
  run env AI_GATEWAY_API_KEY=dummy CC_JEV_BASE_URL="http://127.0.0.1:$PORT" \
      CC_JEV_ZDR=0 CC_JEV_RANK_GAP=0 "$REPO/bin/cc-jev" rank --mem "$MEMD" --yes
  [ "$status" -eq 0 ]
  grep -qF "RUBRIC DISCRIMINATION" <<<"$output"
  [ "$(grep -c 'NEAR-CONSTANT' <<<"$output")" -ge 3 ]   # breadth, bite AND superseded, all flat
  ! grep -qF "<- discriminates" <<<"$output" || { echo "flat run claimed discrimination"; false; }
  # RED-PROOF for the field-mapping bug: `bite`'s answer is stored as `level`, and a report that
  # reads `.bite` finds null on every row and prints "no answers" over perfectly good verdicts.
  ! grep -q 'bite .*no answers' <<<"$output" || { echo "bite read the wrong JSONL field"; false; }
}

# THE OTHER ARM. Without it the `discriminates` branch would ship having never executed, and the
# section could only ever say one thing — the vacuous control this file already names twice.
@test "cc-jev rank: a SPREAD question is reported as discriminating, not near-constant" {
  mkmem5
  export MOCK_CHOICE_ROTATE=1
  start_mock ok
  run env AI_GATEWAY_API_KEY=dummy CC_JEV_BASE_URL="http://127.0.0.1:$PORT" \
      CC_JEV_ZDR=0 CC_JEV_RANK_GAP=0 "$REPO/bin/cc-jev" rank --mem "$MEMD" --yes
  [ "$status" -eq 0 ]
  # Assert on the BREADTH line, not on any line: `superseded` sits in this output too and a bare
  # grep would pass on its verdict while breadth was flat — the assertion would then be about a
  # question this test is not testing.
  grep -qE '^ +breadth .*discriminates' <<<"$output"
  # 5 rows over 4 rotating keys: max bucket is 2/5 = 40%, well under the 80% flat threshold.
  ! grep -q 'breadth.*NEAR-CONSTANT' <<<"$output" || { echo "spread called near-constant"; false; }
}

@test "cc-jev rank: the demotion list sorts on breadth FIRST, and the run states its disagreement" {
  mkmem5
  export MOCK_CHOICE_ROTATE=1
  start_mock ok
  run env AI_GATEWAY_API_KEY=dummy CC_JEV_BASE_URL="http://127.0.0.1:$PORT" \
      CC_JEV_ZDR=0 CC_JEV_RANK_GAP=0 "$REPO/bin/cc-jev" rank --mem "$MEMD" --yes
  [ "$status" -eq 0 ]
  grep -qF "narrowest scope first" <<<"$output"
  # The narrowest key leads the list — the ordinal lives in rank_order(), not in the model.
  grep -A2 'DEMOTION CANDIDATES' <<<"$output" | grep -q 'one-tool'
  # One run must SAY whether the new question changed anything, rather than leaving it to a later
  # read of the JSONL. This is the line that makes a single pass a test of the fix.
  grep -qE "DISAGREEMENT with the old bite-only rule: [0-9]+ row" <<<"$output"
}

@test "cc-jev rank: rank_order names every key the rubric can return, in both directions" {
  # A key the model returns that rank_order does not know sorts to 99 and silently lands at the
  # BOTTOM of a demotion list — the worst direction for a wrong answer. Pin both sets equal.
  for pair in "bite:almost-never occasionally often nearly-always" \
              "breadth:one-tool one-domain cross-domain universal"; do
    q="${pair%%:*}"; want="${pair#*:}"
    got=$(bash -c '. '"$REPO"'/scripts/jev/rank-memory.sh --help >/dev/null 2>&1; true'; \
          sed -n "/^rank_order()/,/^}/p" "$REPO/scripts/jev/rank-memory.sh" \
            | grep -F "$q)" | sed "s/.*printf '//;s/'.*//")
    [ "$got" = "$want" ] || { echo "$q: rank_order has [$got], rubric expects [$want]"; false; }
    # and the criteria block in the spec must carry exactly those keys
    for k in $want; do
      grep -qF "\"$k\":" "$REPO/scripts/jev/rank-memory.sh" \
        || { echo "$q key $k missing from the spec criteria"; false; }
    done
  done
}

@test "cc-jev rank --report: re-reads a past run with no key, no route and no call" {
  R="$BATS_TEST_TMPDIR/rows.jsonl"
  printf '%s\n' \
    '{"file":"a.md","level":"often","breadth":"one-tool","superseded":0.2,"hook":"- [A](a.md) — h"}' \
    '{"file":"b.md","level":"often","breadth":"one-domain","superseded":0.3,"hook":"- [B](b.md) — h"}' \
    '{"file":"c.md","level":"often","breadth":"cross-domain","superseded":0.2,"hook":"- [C](c.md) — h"}' > "$R"
  # No AI_GATEWAY_API_KEY and an unroutable base URL: a local re-read must not touch either.
  run env -u AI_GATEWAY_API_KEY CC_JEV_BASE_URL="http://127.0.0.1:1" \
      "$REPO/bin/cc-jev" rank --report "$R"
  [ "$status" -eq 0 ]
  grep -qF "No call is made" <<<"$output"
  grep -qE '^ +bite +100% in \[often\]' <<<"$output"        # flat, and named as such
  grep -qE '^ +breadth .*discriminates' <<<"$output"      # 3 distinct keys over 3 rows
}

# TWO DIFFERENT NOTHINGS. A run that never ASKED a question and a run whose model never ANSWERED it
# both leave the field absent, and they demand opposite reactions — re-run vs escalate. Reporting a
# pre-breadth JSONL as "the model returned none" would indict the route for our own schema change.
@test "cc-jev rank --report: a pre-breadth run says NOT ASKED, not 'the model returned none'" {
  R="$BATS_TEST_TMPDIR/old.jsonl"
  printf '%s\n' '{"file":"a.md","level":"often","superseded":0.2,"hook":"- [A](a.md) — h"}' > "$R"
  run env -u AI_GATEWAY_API_KEY "$REPO/bin/cc-jev" rank --report "$R"
  [ "$status" -eq 0 ]
  grep -qF "not asked in this run" <<<"$output"
  ! grep -qF "the model returned no answer" <<<"$output" \
    || { echo "blamed the route for our own schema change"; false; }
}

@test "cc-jev rank --report: an empty or missing rows file refuses rather than reporting on nothing" {
  run env -u AI_GATEWAY_API_KEY "$REPO/bin/cc-jev" rank --report "$BATS_TEST_TMPDIR/nope.jsonl"
  [ "$status" -eq 3 ]
  grep -qF "no rows at" <<<"$output"
}

# 🚨 THE `score` CORRECTION, pinned so it cannot silently revert (2026-09-21).
# Three places in this repo recorded that `score` is "rejected invalid-response by the runtime, so
# the published type is a lie" — a claim about the VENDOR, traced to a round trip that never left
# 127.0.0.1. The cause was this suite's own mock: its score branch emitted ONE probability key
# while its choice branch emitted the complete map, and the SDK's client-side
# validateEvaluationAnswers requires hasExactKeys over every level index. One branch of a test
# double failing while its sibling passes indicts the double, not the subject.
@test "score round-trips through evaluate.mjs unmodified — the mock was the blocker, not the route" {
  start_mock ok
  run env AI_GATEWAY_API_KEY=dummy CC_JEV_BASE_URL="http://127.0.0.1:$PORT" CC_JEV_ZDR=0 \
      node "$REPO/scripts/jev/evaluate.mjs" <<<'{"state":"x","questions":{"s":{"type":"score","instructions":"lvl","criteria":["a","b","c","d"]}}}'
  [ "$status" -eq 0 ]
  [ "$(jq -r '.ok' <<<"$output")" = "true" ]
  [ "$(jq -r '.answers.s.type' <<<"$output")" = "score" ]
  # The red-proof: a COMPLETE distribution is what the SDK validates on. Assert every level index
  # is present — reverting the mock to one key puts this back to 1 and fails here rather than
  # re-minting a finding about the vendor.
  [ "$(jq -r '.answers.s.probabilities | keys | length' <<<"$output")" -eq 4 ]
}

# ── `cc-jev status`: is there more of the promotion pass to do? ──────────────────────────────
# A batch run's own output cannot answer this. A PARTIAL pass prints exactly the summary a
# complete one prints — same DECIDED line, same distributions, same swap list, just over fewer
# orphans — so without this the only way to tell is counting JSONL rows by hand, and the honest
# default answer to "did it finish?" would be a round-trip. Local files only: no key, no call.
pass_home() {   # → an isolated HOME whose autonomy dir holds exactly the rows the caller writes
  PH="$BATS_TEST_TMPDIR/ph-$RANDOM"; mkdir -p "$PH/.claude/autonomy"; printf '%s' "$PH"
}
pstatus() { env HOME="$1" AI_GATEWAY_API_KEY=dummy CC_JEV_ARM_FILE="$1/.claude/autonomy/jev-batch.arm" \
                 CC_JEV_FREE_UNTIL="$(date -u -v+30d +%Y-%m-%d)" "$REPO/bin/cc-jev" status 2>&1; }

@test "cc-jev status: no promotion rows at all says NEVER RUN and names the lever" {
  H="$(pass_home)"
  run pstatus "$H"
  grep -qF "promotion   never run" <<<"$output"
  grep -qF "cc-jev arm" <<<"$output"
}

@test "cc-jev status: a PARTIAL pass says so, and says arming again resumes it" {
  H="$(pass_home)"
  { printf '%s\n' '{"id":"meta","round":"meta","orphans":278,"seed":"20260921","plan":133,"anchors":22}'
    for i in 1 2 3; do printf '{"id":"h%s","round":"heat","winner":"a.md"}\n' "$i"; done
  } > "$H/.claude/autonomy/jev-promote-20260921T010101Z.jsonl"
  run pstatus "$H"
  grep -qF "promotion   PARTIAL — 3 of 133" <<<"$output"
  grep -qF "RESUMES it" <<<"$output"
}

@test "cc-jev status: a COMPLETE pass says so, and offers the free re-read" {
  H="$(pass_home)"
  { printf '%s\n' '{"id":"meta","round":"meta","orphans":10,"seed":"s","plan":2,"anchors":1}'
    printf '%s\n' '{"id":"h1","round":"heat","winner":"a.md"}' '{"id":"r2-1","round":"h2h","winner":"a"}'
  } > "$H/.claude/autonomy/jev-promote-20260921T020202Z.jsonl"
  run pstatus "$H"
  grep -qF "promotion   COMPLETE — 2 of 2" <<<"$output"
  grep -qF "cc-jev promote --report" <<<"$output"
}

# An UNKNOWN denominator must be ADMITTED, never guessed. A run predating the plan stamp cannot
# say how much of itself is left, and inventing a completeness would be a confident wrong answer
# in the direction of "nothing more to do" — the one direction that costs the operator the corpus.
@test "cc-jev status: an UNSTAMPED run reports UNKNOWN rather than guessing a denominator" {
  H="$(pass_home)"
  printf '%s\n' '{"id":"h1","round":"heat","winner":"a.md"}' \
    > "$H/.claude/autonomy/jev-promote-20260921T030303Z.jsonl"
  run pstatus "$H"
  grep -qF "completeness UNKNOWN" <<<"$output"
  ! grep -qE 'promotion +(COMPLETE|PARTIAL)' <<<"$output" \
    || { echo "guessed a completeness for an unstamped run"; false; }
}

@test "cc-jev status: reports whether a window is armed, and its terms" {
  H="$(pass_home)"
  run pstatus "$H"
  grep -qF "armed       no" <<<"$output"
  jq -n '{created:"x", expires:"2099-01-01T00:00:00Z", max_calls:133, cap_b:1200, corpus:"memory-orphans"}' \
    > "$H/.claude/autonomy/jev-batch.arm"
  run pstatus "$H"
  grep -qF "armed       YES" <<<"$output"
  grep -qF "133 call(s)" <<<"$output"
}
