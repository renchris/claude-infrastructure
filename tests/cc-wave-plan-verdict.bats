#!/usr/bin/env bats
# cc-wave-plan — S3 trichotomous evidenced wall verdicts + S4 bounded oracle
# (docs/plans/AUTONOMY_DISPATCH_V2.md §3 S3/S4, §5 F4/F5/F6/F8, §7 A4/A5/A6/A8).
#
# WHAT THIS SUITE EXISTS TO PROVE. Before this change every wall collapsed into one `exit 4 /
# quota-cliff` with no evidence, so three structurally different states were indistinguishable and
# two of them aimed the operator at the wrong problem: a hung oracle and a fleet of logged-out
# accounts both paged `/limit-recover`. The suite's spine is therefore a set of PAIRS — two runs of
# the same harness differing in exactly one variable, which must produce DIFFERENT verdicts. A
# single-sided assertion here would pass against a tool that always said the same thing.
#
# RED-PROOF. Every test below was run against the pristine pre-change binary recovered with
#   git archive origin/main bin/cc-wave-plan | tar -x -C <tmpdir>
# via the CC_WAVE_PLAN_UNDER_TEST seam, and every one FAILS there (see the header of each pair).
# The seam is kept so the proof is re-runnable, not a claim.
#
# HERMETIC: $HOME is fixtured (this suite is not on the test-hermeticity-lint ratchet and must not
# be added to it). The stubs mirror the REAL producer's contract, not a convenient approximation:
# `claude-accounts --rank general` emits `<acct> <score>` lines and, when nothing is routable,
# prints the sentinel `none` and exits 2 (policy refused) / 3 (data unavailable).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WP="${CC_WAVE_PLAN_UNDER_TEST:-$REPO/bin/cc-wave-plan}"
  C="$BATS_TEST_TMPDIR/case"
  mkdir -p "$C/bin" "$C/home"
  export HOME="$C/home"                       # hermetic: never the operator's ~/.claude state

  # accounts stub — FIXTURE-SHAPE PARITY with bin/claude-accounts (memory:
  # fixture-shape-parity-with-real-producer). `--rank` answers "who has HEADROOM"; `--json` answers
  # "what accounts EXIST and what is their state" — different questions, so the --json universe
  # does NOT empty when the headroom set does. Rows carry the CLI-OWNED verdict fields
  # (auth_actionable / login_fixable, claude-accounts:717-723) that the subject decides on.
  cat > "$C/bin/claude-accounts" <<'STUB'
#!/bin/bash
[ -n "${STUB_SLEEP:-}" ] && sleep "$STUB_SLEEP"
case "${1:-}" in
  --rank)
    [ -n "${STUB_RANK_RC:-}" ] && { echo "claude-accounts: rank probe failed" >&2; exit "$STUB_RANK_RC"; }
    [ -n "${STUB_RANK_GARBAGE:-}" ] && { printf '   \n<html>rate limited</html>\n'; exit 0; }
    i=0; for n in ${STUB_RANK-next next4 next3 next2}; do printf '%s 0.%06d\n' "$n" $((900-i)); i=$((i+1)); done
    [ -z "${STUB_RANK-x}" ] && { echo none; echo "claude-accounts: no routable account for general" >&2; exit "${STUB_RANK_NONE_RC:-2}"; }
    : ;;
  --json)
    [ -n "${STUB_JSON_RC:-}" ] && { echo "claude-accounts: json probe failed" >&2; exit "$STUB_JSON_RC"; }
    m="${STUB_WIN_MIN:-600}"
    dl="$(date -u -v+"${m}"M +%Y-%m-%dT%H:%M:%S+00:00 2>/dev/null || date -u -d "+${m} minutes" +%Y-%m-%dT%H:%M:%S+00:00)"
    if [ -n "${STUB_ROWS:-}" ]; then rows="$STUB_ROWS"
    else
      rows='['; sep=''
      for n in ${STUB_ACCTS-next next4 next3 next2}; do
        rows="$rows$sep{\"acct\":\"$n\",\"k\":0,\"auth\":\"${STUB_AUTH:-ok}\""
        rows="$rows,\"auth_actionable\":${STUB_ACTIONABLE:-false},\"login_fixable\":${STUB_FIXABLE:-false}"
        rows="$rows,\"session_pct\":${STUB_SESSION_PCT:-97},\"weekly_pct\":${STUB_WEEKLY_PCT:-96}}"
        sep=','
      done
      rows="$rows]"
    fi
    printf '{"window":{"active":true,"deadline":"%s"},"rows":%s}\n' "$dl" "$rows" ;;
  *) exit 2 ;;
esac
STUB

  cat > "$C/bin/cc-route" <<'STUB'
#!/bin/bash
[ -n "${STUB_ROUTE_SLEEP:-}" ] && sleep "$STUB_ROUTE_SLEEP"
[ -n "${STUB_ROUTE_CLIFF:-}" ] && { echo "cc-route: cliff" >&2; exit 4; }
case "$1" in
  lead|transcription) model=claude-opus-4-8; eff=max ;;
  judgment-dense|adversarial) model=claude-fable-5; eff=xhigh ;;
  *) echo "unknown slot" >&2; exit 2 ;;
esac
jq -cn --arg s "$1" --arg m "$model" --arg e "$eff" \
   '{slot:$s,model:$m,account:"stub",lead_effort:$e,reason:"stub route"}'
STUB
  chmod +x "$C/bin/claude-accounts" "$C/bin/cc-route"

  export CC_WAVE_ACCOUNTS_BIN="$C/bin/claude-accounts" CC_WAVE_ROUTE_BIN="$C/bin/cc-route" \
         CC_WAVE_IDL="$C/idl.jsonl"
  IT1='[{"id":"a","slot":"lead"}]'
  # Resolved the same way the subject does — absolute paths only. Every bound-dependent test skips
  # LOUDLY rather than silently passing when no timeout(1) exists (a silent pass would be the
  # fixtured void this repo keeps getting bitten by).
  TMO=""
  for p in /usr/bin/timeout /opt/homebrew/bin/timeout /usr/local/bin/timeout \
           /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -x "$p" ] && { TMO="$p"; break; }
  done
}

last_idl() { tail -1 "$CC_WAVE_IDL"; }

# ── (1) THE DISCRIMINATING PAIR ───────────────────────────────────────────────────────────────────
# One harness, one variable: does the oracle ANSWER? If these two ever agree the change is worthless.
# RED against pristine: (a) exits 0 (no bound — it waits out the sleep and plans normally),
# (b) exits 0 (it parses the `none` sentinel as an account and plans a wave onto `--account none`).

@test "DISCRIMINATOR a: an oracle that sleeps past the bound → exit 6 unknown, never capped" {
  [ -n "$TMO" ] || skip "no absolute-path timeout(1) on this box — the S4 bound cannot be exercised"
  export STUB_SLEEP=3 CC_WAVE_ORACLE_TIMEOUT_S=1
  run "$WP" --items "$IT1"
  [ "$status" -eq 6 ]
  last_idl | jq -e 'select(.verdict=="unknown" and .evidence.oracle_rc==124)'
}

@test "DISCRIMINATOR b: the SAME harness, oracle answers 'nothing routable' → exit 4 capped" {
  export STUB_RANK='' CC_WAVE_ORACLE_TIMEOUT_S=1
  run "$WP" --items "$IT1"
  [ "$status" -eq 4 ]
  last_idl | jq -e 'select(.verdict=="capped" and .evidence.oracle_rc==0)'
}

# ── (2) S4 — the bound, and that it is never silently skipped (A8) ────────────────────────────────

@test "S4: every claude-accounts / cc-route call site is wrapped (zero unwrapped sites)" {
  # A8's disk-truth read. Both oracles resolve through run_oracle, the single chokepoint; a new
  # unwrapped call site is what this catches.
  # An invocation is `"$bin" --…` or `"$(route_bin)" "…`; the `[ -n "$(route_bin)" ]` availability
  # guards are deliberately not matched (they execute nothing).
  run bash -c "grep -nE '\"\\\$bin\" --|\"\\\$\\(route_bin\\)\" \"' '$WP' | grep -v run_oracle"
  [ -z "$output" ]
  # ...and the positive control: the chokepoint is actually used, so an empty result above cannot
  # mean "no oracle calls exist at all".
  run bash -c "grep -cE '^ *[A-Z_]*=?\"?\\\$\\(run_oracle|run_oracle \"' '$WP'"
  [ "$output" -ge 3 ]
}

@test "S4: a bounded cc-route that hangs is unknown (6), NOT a config-fail (3)" {
  [ -n "$TMO" ] || skip "no absolute-path timeout(1) on this box"
  export STUB_ROUTE_SLEEP=3 CC_WAVE_ORACLE_TIMEOUT_S=1
  run "$WP" --items "$IT1"
  [ "$status" -eq 6 ]
}

@test "S4: the timeout binary is recorded, and 'absent' is recorded rather than skipped" {
  # Absence assertion + its positive control, side by side: with a bound the record names a real
  # absolute path; with none it says "absent" out loud instead of quietly running unbounded.
  export STUB_RANK=''
  export CC_WAVE_TIMEOUT_BIN=''                      # set-but-empty ⇒ force the no-bound path
  run "$WP" --items "$IT1"
  [ "$status" -eq 4 ]
  last_idl | jq -e '.evidence.timeout_bin=="absent"'
  unset CC_WAVE_TIMEOUT_BIN
  [ -n "$TMO" ] || skip "no absolute-path timeout(1) on this box for the positive control"
  run "$WP" --items "$IT1"
  [ "$status" -eq 4 ]
  last_idl | jq -e '.evidence.timeout_bin|test("^/")'
}

@test "S4: the bound resolves absolutely — it still fires with Homebrew off PATH" {
  # The subject is reached from a launchd job. Resolving timeout(1) through PATH would make the
  # bound evaporate under a minimal PATH; absolute resolution is what stops that. jq is symlinked
  # into the fixture because it is a hard dependency the tool resolves via PATH (exit 3 without it),
  # so a bare PATH=/usr/bin:/bin would prove nothing about the bound.
  [ -n "$TMO" ] || skip "no absolute-path timeout(1) on this box"
  ln -sf "$(command -v jq)" "$C/bin/jq"
  export STUB_SLEEP=3 CC_WAVE_ORACLE_TIMEOUT_S=1
  run env PATH="$C/bin:/usr/bin:/bin" /bin/bash "$WP" --items "$IT1"
  [ "$status" -eq 6 ]
}

# ── (3) S3 auth (F5) — the wrong-operator-action wall ─────────────────────────────────────────────
# RED against pristine: exits 0 (phantom `none` account) and names no action at all.

@test "auth: all accounts logged out → exit 5, /relogin, and NEVER /limit-recover" {
  export STUB_RANK='' STUB_AUTH=logged-out STUB_ACTIONABLE=true STUB_FIXABLE=true
  run "$WP" --items "$IT1"
  [ "$status" -eq 5 ]
  run bash -c "'$WP' --items '$IT1' 2>&1 1>/dev/null"
  printf '%s' "$output" | grep -q relogin
  # the absence assertion...
  ! printf '%s' "$output" | grep -q limit-recover || false
  last_idl | jq -e 'select(.verdict=="auth" and .evidence.action=="/relogin")'
}

@test "auth: positive control — the capped path DOES name /limit-recover" {
  # ...and its control. Without this the assertion above would pass against a tool whose stderr is
  # empty on every path.
  export STUB_RANK=''
  run bash -c "'$WP' --items '$IT1' 2>&1 1>/dev/null"
  printf '%s' "$output" | grep -q limit-recover
  last_idl | jq -e '.evidence.action=="/limit-recover"'
}

@test "auth: ONE healthy account among logged-out ones is a quota wall (4), not auth (5)" {
  # The auth verdict requires that NO account is healthy. A healthy account with no headroom is
  # exactly what `capped` means, and mis-routing it to /relogin would be the mirror-image defect.
  export STUB_RANK='' STUB_ROWS='[{"acct":"a","auth":"logged-out","auth_actionable":true,"login_fixable":true,"k":0},{"acct":"b","auth":"ok","auth_actionable":false,"login_fixable":false,"k":0}]'
  run "$WP" --items "$IT1"
  [ "$status" -eq 4 ]
  last_idl | jq -e '.verdict=="capped"'
}

@test "auth: rc=3 caused by logged-out accounts is still auth (5), not unknown (6)" {
  # An all-logged-out fleet exits 3 ("data unavailable") because a logged-out row carries an
  # `error` and reason_class maps that to "data" (claude-accounts:846-848). Ordering the auth check
  # before the rc-3 check is what keeps F5 fixed.
  export STUB_RANK='' STUB_RANK_NONE_RC=3 STUB_AUTH=logged-out STUB_ACTIONABLE=true STUB_FIXABLE=true
  run "$WP" --items "$IT1"
  [ "$status" -eq 5 ]
}

# ── (4) S3 unknown (F4) — an absent answer is not a wall ──────────────────────────────────────────
# RED against pristine: every one of these exits 0 or 4; none is distinguishable.

@test "unknown: --rank exits non-zero → exit 6, and the oracle's own diagnostic is on the record" {
  export STUB_RANK_RC=5
  run "$WP" --items "$IT1"
  [ "$status" -eq 6 ]
  last_idl | jq -e 'select(.verdict=="unknown" and .evidence.oracle_rc==5)'
  last_idl | jq -e '.evidence.stderr_excerpt|test("rank probe failed")'
}

@test "unknown: no-candidate rc=3 (data unavailable) → 6, while rc=2 (policy) → 4" {
  # The producer distinguishes these itself: 3 = "we could not SEE the data, degrade to a proxy",
  # 2 = "data was fine and policy refused" (claude-accounts:836-838). Asserting a quota wall on data
  # nobody could read is the false cliff; both halves run so the pair cannot collapse.
  export STUB_RANK='' STUB_RANK_NONE_RC=3
  run "$WP" --items "$IT1"
  [ "$status" -eq 6 ]
  export STUB_RANK_NONE_RC=2
  run "$WP" --items "$IT1"
  [ "$status" -eq 4 ]
}

@test "unknown: rank empty + --json unavailable → 6 (no per-account state to verdict on)" {
  export STUB_RANK='' STUB_JSON_RC=1
  run "$WP" --items "$IT1"
  [ "$status" -eq 6 ]
  last_idl | jq -e '.evidence.reason=="accounts-json-unavailable"'
}

@test "unknown: the oracle answers but knows about NO account → 6 (absence of evidence)" {
  export STUB_RANK='' STUB_ROWS='[]'
  run "$WP" --items "$IT1"
  [ "$status" -eq 6 ]
}

@test "unknown: an unknown verdict never emits a plan and never names a quota cliff" {
  export STUB_RANK_RC=5
  run bash -c "'$WP' --items '$IT1' --json 2>/dev/null"     # stdout only: `run` merges stderr
  [ -z "$output" ]
  run bash -c "'$WP' --items '$IT1' 2>&1 1>/dev/null"
  ! printf '%s' "$output" | grep -qi 'quota cliff' || false
  ! printf '%s' "$output" | grep -q limit-recover || false
  printf '%s' "$output" | grep -qi 'retry next pass'
}

# ── (5) The `none` sentinel — a phantom account is worse than a wrong wall ────────────────────────
# RED against pristine: it plans a wave onto an account literally named `none` and exits 0, so the
# no-headroom branch was unreachable against the real CLI in the first place.

@test "sentinel: 'none' never becomes an account — no plan is emitted" {
  export STUB_RANK=''
  run bash -c "'$WP' --items '$IT1' --json 2>/dev/null"     # stdout only: `run` merges stderr
  [ -z "$output" ]
  ! printf '%s' "$output" | grep -q none || false
  run "$WP" --items "$IT1" --json
  [ "$status" -eq 4 ]
}

@test "sentinel: a rank line without a numeric score is unparseable, not an account" {
  export STUB_RANK_GARBAGE=1
  run "$WP" --items "$IT1"
  [ "$status" -eq 6 ]
  last_idl | jq -e '.evidence.reason=="oracle-unparseable"'
}

@test "sentinel: positive control — a well-formed '<acct> <score>' line still ranks and places" {
  export STUB_RANK='acctA'
  run "$WP" --items "$IT1" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].account=="acctA"'
}

# ── (6) Evidence (F6) — A4 is not readable without it ─────────────────────────────────────────────

@test "evidence: a capped record carries oracle_rc, ranked_n and per-account {acct,state,k}" {
  export STUB_RANK=''
  run "$WP" --items "$IT1"
  [ "$status" -eq 4 ]
  last_idl | jq -e 'select(.action=="wall" and .verdict=="capped")'
  last_idl | jq -e 'select(.evidence.oracle_rc==0 and .evidence.ranked_n==0)'
  last_idl | jq -e '(.evidence.accounts|length)==4'
  last_idl | jq -e '.evidence.accounts|all(has("acct") and has("state") and has("k"))'
  # the A4 read itself: no capped record may show an account with quota headroom
  last_idl | jq -e 'select(.verdict=="capped") | [.evidence.accounts[] | select(.session_pct < 90)] | length == 0'
}

@test "evidence: A4's read flags a capped verdict built on a broken oracle (there are none)" {
  # Run every wall path, then apply A4 verbatim across the whole journal.
  export STUB_RANK=''; run "$WP" --items "$IT1"
  export STUB_RANK_RC=5; run "$WP" --items "$IT1"; unset STUB_RANK_RC
  export STUB_AUTH=logged-out STUB_ACTIONABLE=true; run "$WP" --items "$IT1"
  run bash -c "jq -s '[.[] | select(.verdict==\"capped\" and .evidence.oracle_rc != 0)] | length' '$CC_WAVE_IDL'"
  [ "$output" -eq 0 ]
  run bash -c "jq -s '[.[] | select(.verdict==\"unknown\")] | length' '$CC_WAVE_IDL'"
  [ "$output" -ge 1 ]
}

@test "evidence: a route-cliff is capped with oracle_rc 0 and route_rc 4" {
  # cc-route's exit 4 is its ANSWER — "general route none, every account capped" (bin/cc-route:29,
  # 264, itself derived from claude-accounts' policy-refused rc 2) — not a failure of the oracle.
  # Recording it as oracle_rc would make A4 flag every genuine route-propagated cliff as false.
  export STUB_ROUTE_CLIFF=1
  run "$WP" --items "$IT1"
  [ "$status" -eq 4 ]
  last_idl | jq -e 'select(.verdict=="capped" and .evidence.oracle_rc==0 and .evidence.route_rc==4)'
}

@test "order: the account wall is decided before any cc-route call (frontier waves too)" {
  # Ranking after the straddle block meant a frontier wave resolved the lead model FIRST, so an
  # all-logged-out fleet surfaced as cc-route's config-fail (3) and the S3 states were unreachable
  # for exactly the wave shapes that use them most. Both halves run so the pair cannot collapse.
  export STUB_RANK='' STUB_AUTH=logged-out STUB_ACTIONABLE=true STUB_FIXABLE=true
  run "$WP" --items '[{"id":"j","slot":"judgment-dense"}]'
  [ "$status" -eq 5 ]
  unset STUB_AUTH STUB_ACTIONABLE STUB_FIXABLE
  run "$WP" --items '[{"id":"j","slot":"judgment-dense"}]'
  [ "$status" -eq 4 ]
}

@test "evidence: wave overflow verdicts 'capacity', never 'capped' (A4 stays readable)" {
  # Wave sizing is not a quota wall — the accounts have headroom (memory:
  # dispatch-false-cliff-wave-sizing). Exit 4 is retained for the cc-dispatch contract, but a
  # distinct verdict keeps it out of A4's capped population.
  export STUB_RANK='acctA acctB' CC_WAVE_MAX_PER_ACCT=1
  run "$WP" --items '[{"id":"1","slot":"lead"},{"id":"2","slot":"lead"},{"id":"3","slot":"lead"}]'
  [ "$status" -eq 4 ]
  last_idl | jq -e 'select(.verdict=="capacity" and .evidence.ranked_n==2)'
}

# ── (7) Kill switch (§6) — reversible by env, never by revert ─────────────────────────────────────

@test "lane v1: every new verdict reverts to the single unevidenced exit 4" {
  export CC_WAVE_VERDICT_LANE=v1
  export STUB_RANK='' STUB_AUTH=logged-out STUB_ACTIONABLE=true STUB_FIXABLE=true
  run "$WP" --items "$IT1"
  [ "$status" -eq 4 ]
  last_idl | jq -e 'select(.action=="failed" and (has("verdict")|not) and (has("evidence")|not))'
  unset STUB_AUTH STUB_ACTIONABLE STUB_FIXABLE
  export STUB_RANK_RC=5
  run "$WP" --items "$IT1"
  [ "$status" -eq 4 ]
}

@test "lane v1: the happy path and the placement algorithm are untouched by the switch" {
  export CC_WAVE_VERDICT_LANE=v1 STUB_RANK='acctA acctB'
  run "$WP" --items '[{"id":"1","slot":"lead"},{"id":"2","slot":"lead"}]' --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.[0].account=="acctA") and (.[1].account=="acctB")'
}

# ── (8) Contract with cc-dispatch — 0 and 4 keep their meaning ────────────────────────────────────

@test "contract: exit 0 still emits a plan; 5 and 6 are new codes, not repurposed ones" {
  run "$WP" --items "$IT1" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].fire_line|test("handoff-fire.sh")'
  run "$WP" --items '[]'
  [ "$status" -eq 2 ]
  run "$WP" --items 'not-json'
  [ "$status" -eq 3 ]
  export STUB_ROUTE_CLIFF=1
  run "$WP" --items "$IT1"
  [ "$status" -eq 4 ]
}

@test "contract: the in-script selftest still passes with zero failures" {
  run "$WP" selftest
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q '^  FAIL' || false
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -ge 55 ]
}
