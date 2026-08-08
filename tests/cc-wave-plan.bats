#!/usr/bin/env bats
# T-P7-6 cc-wave-plan — quota-aware wave placement. The tool's `selftest` RED-proves every edge against
# stubbed accounts + cc-route; these bats add (a) the selftest exit-code + check-count contract and
# (b) independent real-CLI `--items … --json` runs through the override surface — proving placement,
# the Fable-window straddle guard, the ≤N/account cap, and the quota-cliff STOP outside the selftest.

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. handoff-fire.sh's
  # capacity_gate reads the box's live loadavg AND (M10) its memory headroom, exiting 9 when either is
  # past its bar, so an unpinned suite goes RED purely because the box is busy — the corpus deciding a
  # verdict on machine state instead of on the tree. Both terms are pinned off here (they are the two
  # TERMS of one exit 9, handoff-fire.sh:4487); tests/handoff-fire-capacity-gate.bats is the ONE place
  # the gate runs ON, against synthetic inputs.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WP="$REPO/bin/cc-wave-plan"
  C="$BATS_TEST_TMPDIR/case"
  mkdir -p "$C/bin"

  # accounts stub — --rank general (STUB_RANK space-list; set-but-empty = nothing routable) · --json
  # (window deadline = now + STUB_WIN_MIN minutes, default 600 = wide open; rows).
  #
  # FIXTURE-SHAPE PARITY with bin/claude-accounts (memory: fixture-shape-parity-with-real-producer).
  # Two corrections, both of which the old fixture got wrong in the same direction — claiming LESS
  # than the producer emits, which hid a defect rather than exposing one:
  #   · `--rank` prints the sentinel `none` and exits 2 (policy refused) / 3 (data unavailable) when
  #     nothing is routable (claude-accounts:1678-1685). It never returns empty stdout.
  #   · `--json` emits a row per CONFIGURED account regardless of headroom, carrying the CLI-owned
  #     auth_actionable / login_fixable verdicts (claude-accounts:694-723) — so its universe does
  #     not empty along with the headroom set. STUB_ROWS still overrides it explicitly.
  cat > "$C/bin/claude-accounts" <<'STUB'
#!/bin/bash
case "${1:-}" in
  --rank)
    i=0; for n in ${STUB_RANK-next next4 next3 next2}; do printf '%s 0.%06d\n' "$n" $((900-i)); i=$((i+1)); done
    [ -z "${STUB_RANK-x}" ] && { echo none; echo "claude-accounts: no routable account for general" >&2; exit "${STUB_RANK_NONE_RC:-2}"; }
    : ;;
  --json) m="${STUB_WIN_MIN:-600}"
    dl="$(date -u -v+"${m}"M +%Y-%m-%dT%H:%M:%S+00:00 2>/dev/null || date -u -d "+${m} minutes" +%Y-%m-%dT%H:%M:%S+00:00)"
    if [ -n "${STUB_ROWS:-}" ]; then rows="$STUB_ROWS"
    else
      rows='['; sep=''
      for n in ${STUB_ACCTS-next next4 next3 next2}; do
        rows="$rows$sep{\"acct\":\"$n\",\"k\":0,\"auth\":\"ok\",\"auth_actionable\":false,\"login_fixable\":false,\"session_pct\":97,\"weekly_pct\":96}"
        sep=','
      done
      rows="$rows]"
    fi
    printf '{"window":{"active":true,"deadline":"%s"},"rows":%s}\n' "$dl" "$rows" ;;
  *) exit 2 ;;
esac
STUB

  # cc-route stub — mirrors the real slot table + edges (STUB_ROUTE_CLIFF → exit 4; STUB_FABLE_NONE → Opus).
  cat > "$C/bin/cc-route" <<'STUB'
#!/bin/bash
[ -n "${STUB_ROUTE_CLIFF:-}" ] && { echo "cc-route: cliff" >&2; exit 4; }
slot="$1"
case "$slot" in
  lead)          model=claude-opus-4-8; eff=max;  reason="general route" ;;
  transcription) model=claude-opus-4-8; eff=high; reason="general route" ;;
  judgment-dense|adversarial)
    if [ -n "${STUB_FABLE_NONE:-}" ]; then
      model=claude-opus-4-8; reason="frontier unavailable -> designed Opus fallback"
      [ "$slot" = adversarial ] && eff=xhigh || eff=max
    else model=claude-fable-5; eff=xhigh; reason="frontier window open"; fi ;;
  *) echo "unknown slot" >&2; exit 2 ;;
esac
jq -cn --arg s "$slot" --arg m "$model" --arg a stub --arg e "$eff" --arg r "$reason" \
   '{slot:$s,model:$m,account:$a,lead_effort:$e,reason:$r}'
STUB
  chmod +x "$C/bin/claude-accounts" "$C/bin/cc-route"

  export CC_WAVE_ACCOUNTS_BIN="$C/bin/claude-accounts" CC_WAVE_ROUTE_BIN="$C/bin/cc-route" \
         CC_WAVE_IDL="$C/idl.jsonl"
}

# ── (a) selftest contract ─────────────────────────────────────────────────────────────────────────────
@test "selftest passes and runs all 63 checks (a zero-check suite must not 'pass')" {
  # 29 → 63: the S3/S4 verdict + bounded-oracle cases. Bound-dependent checks print `skip` and are
  # counted separately, so a box without timeout(1) reports fewer `ok` lines rather than silently
  # passing a hollow suite — hence >= on a floor that still fails a collapsed run.
  run "$WP" selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -ge 52 ]
  ! printf '%s' "$output" | grep -q '^  FAIL'
}

# ── surface by anchor context — TWICE-INVERTED, and both inversions matter ───────────────────────
# 2026-07-25 (drain incident): a hardcoded --split-right killed EVERY headless spawn, because under
#   launchd $ITERM_SESSION_ID never exists and handoff-fire REFUSED an anchorless split. 0 `fired`
#   IDL records ever, 408 `failed` in one day. The fix: emit --window when headless.
# 2026-07-30 (d6b417e9): that cure opened a brand-new iTerm2 WINDOW per dispatched session — 174 in
#   one day. The anchor is now resolved at the CHOKEPOINT (handoff-fire's resolve_headless_anchor),
#   so cc-wave-plan's surface became UNCONDITIONALLY --split-right and the anchorless refusal that
#   caused the drain no longer fires here (bin/cc-wave-plan:555-568).
#
# This test asserted the 2026-07-25 contract and was left behind by the 2026-07-30 change: the
# binary moved on 07-30, the suite last moved 07-29, and it has been RED on trunk since — while
# cc-wave-plan's OWN selftest (:728-731, 63/63 green) asserted the opposite. Two oracles for one
# behaviour disagreeing is the tell. Updated to the live contract per §4's rule: a test can encode a
# falsified premise, and CHANGING it is legitimate where HIDING it would not be.
@test "headless plan (no ITERM_SESSION_ID) emits --split-right and NEVER --window (d6b417e9)" {
  run bash -c "env -u ITERM_SESSION_ID '$WP' --items '[{\"id\":\"h\",\"slot\":\"lead\"}]' --json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].fire_line | test("--split-right")'
  # the load-bearing half: --window is what minted 174 windows in a day
  echo "$output" | jq -e '.[0].fire_line | test("--window") | not'
}

@test "anchored plan (ITERM_SESSION_ID present) keeps the --split-right ⌘D default" {
  ITERM_SESSION_ID="w0t0p0:TEST" run "$WP" --items '[{"id":"a","slot":"lead"}]' --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].fire_line | test("--split-right")'
}

@test "the surface no longer varies by anchor context — the choice moved to the chokepoint" {
  # The PAIR above now asserts the same surface on both sides, so on its own it can no longer tell
  # "decided correctly, twice" from "the decision was dropped". That is the point post-d6b417e9 —
  # the surface is not cc-wave-plan's call any more — but it must be asserted POSITIVELY rather than
  # left as an accident of two tests happening to agree (memory decision-moved-out-of-the-guarded-unit).
  # scan() with a capture GROUP yields the group, not the match, so the alternation is spelled out
  # without one — otherwise both sides read as arrays and compare equal for the wrong reason.
  surf='.[0].fire_line | [scan("--split-right|--window")] | sort | join(",")'
  headless="$(bash -c "env -u ITERM_SESSION_ID '$WP' --items '[{\"id\":\"h\",\"slot\":\"lead\"}]' --json" | jq -r "$surf")"
  anchored="$(ITERM_SESSION_ID="w0t0p0:TEST" "$WP" --items '[{"id":"h","slot":"lead"}]' --json | jq -r "$surf")"
  [ "$headless" = "$anchored" ]
  [ "$headless" = "--split-right" ]   # and NOT "" — an empty match on both sides would also be equal
}

@test "unknown flag → exit 2 (fail-loud, no silent no-op)" {
  run "$WP" --bogus
  [ "$status" -eq 2 ]
}

# ── (b) real CLI placement through the stubbed quota ──────────────────────────────────────────────────
@test "happy: mixed wave places each item with its slot's model/effort on a ranked account" {
  run "$WP" --items '[{"id":"a","slot":"lead"},{"id":"b","slot":"transcription"}]' --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0]|select(.id=="a" and .model=="claude-opus-4-8" and .effort=="max" and .account=="next")'
  echo "$output" | jq -e '.[1]|select(.id=="b" and .effort=="high")'
  echo "$output" | jq -e '.[0].fire_line|test("handoff-fire.sh") and test("/tmp/fire-a.txt")'
}

@test "spread: 3 items, MAX=2, 2 idle accounts → round-robin A,B,A (per-wave cap retained)" {
  # Greedy best-first would have put items 1+2 on acctA then spilled 3 to acctB (A,A,B); spread-aware
  # placement round-robins (A,B,A) while the ≤MAX_PER_ACCT cap still bounds A at 2.
  export STUB_RANK='acctA acctB' CC_WAVE_MAX_PER_ACCT=2
  run "$WP" --items '[{"id":"1","slot":"lead"},{"id":"2","slot":"lead"},{"id":"3","slot":"lead"}]' --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.[0].account=="acctA") and (.[1].account=="acctB") and (.[2].account=="acctA")'
}

@test "spread: a live-loaded best-ranked account is de-prioritized by the load penalty" {
  # acctA ranks first but already carries 3 live sessions; acctB is idle → the item lands on acctB.
  # This is the cross-wave fix (operator 2026-07-19): greedy best-first piled onto acctA regardless.
  export STUB_RANK='acctA acctB' STUB_ROWS='[{"acct":"acctA","k":3},{"acct":"acctB","k":0}]'
  run "$WP" --items '[{"id":"1","slot":"lead"}]' --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].account=="acctB"'
}

@test "straddle: Fable window within guard → Opus fallback with reason, NO fable id in the plan" {
  export STUB_WIN_MIN=10
  run "$WP" --items '[{"id":"j","slot":"judgment-dense"},{"id":"v","slot":"adversarial"}]' --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0]|select(.slot=="judgment-dense" and .model=="claude-opus-4-8" and .effort=="max")'
  echo "$output" | jq -e '.[1]|select(.slot=="adversarial" and .model=="claude-opus-4-8" and .effort=="xhigh")'
  ! printf '%s' "$output" | grep -q fable || false
  # the invocation is recorded as an abstention (fable-straddle-fallback)
  tail -1 "$CC_WAVE_IDL" | jq -e 'select(.action=="abstained" and .actor=="cc-wave-plan")'
}

@test "open: wide-open Fable window → the frontier slot keeps the fable model @ xhigh (guard not over-firing)" {
  export STUB_WIN_MIN=600
  run "$WP" --items '[{"id":"j","slot":"judgment-dense"}]' --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0]|select(.model=="claude-fable-5" and .effort=="xhigh")'
  tail -1 "$CC_WAVE_IDL" | jq -e 'select(.action=="fired")'
}

@test "cliff: every account capped (rank empty) → exit 4, NO plan on stdout, names /limit-recover" {
  export STUB_RANK=''
  run "$WP" --items '[{"id":"a","slot":"lead"}]'
  [ "$status" -eq 4 ]
  [ -z "$output" ] || ! printf '%s' "$output" | jq -e . >/dev/null 2>&1 || false # no JSON plan emitted
  run bash -c "'$WP' --items '[{\"id\":\"a\",\"slot\":\"lead\"}]' 2>&1 1>/dev/null"
  printf '%s' "$output" | grep -q limit-recover
}

# ── the falsified premise, and the split that replaces it ─────────────────────────────────────────
# THIS TEST USED TO ENCODE A FALSIFIED BELIEF: "wave exceeds total concurrency → exit 4 cliff",
# asserting nothing but the exit code — identical to its cc-route neighbour below, so the two were
# indistinguishable. Verified from disk, not inherited: `bef587ac` (2026-07-18) bounded the wave to
# MAX_SPAWN precisely "so an oversized backlog stops false-cliffing", and cc-dispatch:199 slices the
# wave to MAX_SPAWN before it ever calls this tool — yet the live IDL still records 12 cc-dispatch
# quota-cliffs on 2026-07-26, eight days later. So the surviving cliffs were never wave sizing, and
# an oversized wave is not evidence of a quota wall at all: the accounts have headroom by
# construction (ranked_n > 0 below is that fact, asserted).
#
# The replacement is a VERDICT split, not a relaxed assertion. Wave oversize verdicts `capacity`;
# a cc-route-propagated cliff verdicts `capped` with evidence. The exit code stays 4 for BOTH
# because that is cc-dispatch's pinned contract (cc-dispatch:204 treats 4 as abstain+page and any
# other non-zero as a loud refuse) — telling them apart is the journal's job, which is exactly what
# made the false cliffs unmeasurable before (§5 F6). Whether wave oversize should leave exit 4
# entirely is a cc-dispatch-contract question, open with the lead; it is a one-line change here.

@test "capacity: an oversized wave verdicts 'capacity' — NOT a quota cliff (premise falsified)" {
  export STUB_RANK='acctA acctB' CC_WAVE_MAX_PER_ACCT=2
  run "$WP" --items '[{"id":"1","slot":"lead"},{"id":"2","slot":"lead"},{"id":"3","slot":"lead"},{"id":"4","slot":"lead"},{"id":"5","slot":"lead"}]'
  [ "$status" -eq 4 ]                                   # cc-dispatch contract, pinned deliberately
  tail -1 "$CC_WAVE_IDL" | jq -e 'select(.verdict=="capacity")'
  # the accounts HAVE headroom — the whole reason this is not a cliff
  tail -1 "$CC_WAVE_IDL" | jq -e '.evidence.ranked_n == 2'
  tail -1 "$CC_WAVE_IDL" | jq -e '.evidence.action != "/limit-recover"'
  run bash -c "STUB_RANK='acctA acctB' CC_WAVE_MAX_PER_ACCT=2 '$WP' --items '[{\"id\":\"1\",\"slot\":\"lead\"},{\"id\":\"2\",\"slot\":\"lead\"},{\"id\":\"3\",\"slot\":\"lead\"},{\"id\":\"4\",\"slot\":\"lead\"},{\"id\":\"5\",\"slot\":\"lead\"}]' 2>&1 1>/dev/null"
  ! printf '%s' "$output" | grep -q limit-recover || false
}

@test "cliff: a cc-route-propagated quota cliff is GENUINE — verdict 'capped', /limit-recover" {
  # The neighbour the ruling requires to stay distinguishable. cc-route's exit 4 means "general
  # route none, every account capped" (bin/cc-route:29,264) — a real capped-account stop, so it
  # keeps the cliff verdict AND the operator action the oversize case must never carry.
  export STUB_ROUTE_CLIFF=1
  run "$WP" --items '[{"id":"a","slot":"lead"}]'
  [ "$status" -eq 4 ]
  tail -1 "$CC_WAVE_IDL" | jq -e 'select(.verdict=="capped" and .evidence.action=="/limit-recover")'
  run bash -c "STUB_ROUTE_CLIFF=1 '$WP' --items '[{\"id\":\"a\",\"slot\":\"lead\"}]' 2>&1 1>/dev/null"
  printf '%s' "$output" | grep -q limit-recover
}

@test "the pair cannot collapse: wave-sizing and a real capped stop verdict DIFFERENTLY" {
  # The guard the ruling actually asks for. Both cases exit 4, so an exit-code-only assertion (what
  # both tests used to be) passes against a tool that cannot tell them apart. This one fails.
  export STUB_RANK='acctA acctB' CC_WAVE_MAX_PER_ACCT=2
  run "$WP" --items '[{"id":"1","slot":"lead"},{"id":"2","slot":"lead"},{"id":"3","slot":"lead"},{"id":"4","slot":"lead"},{"id":"5","slot":"lead"}]'
  v_sizing="$(tail -1 "$CC_WAVE_IDL" | jq -r '.verdict')"
  unset CC_WAVE_MAX_PER_ACCT
  export STUB_RANK='' STUB_ROUTE_CLIFF=1
  run "$WP" --items '[{"id":"a","slot":"lead"}]'
  v_capped="$(tail -1 "$CC_WAVE_IDL" | jq -r '.verdict')"
  [ "$v_sizing" = "capacity" ]
  [ "$v_capped" = "capped" ]
  [ "$v_sizing" != "$v_capped" ]
}

@test "usage: empty items array → exit 2" {
  run "$WP" --items '[]'
  [ "$status" -eq 2 ]
}

@test "config: malformed JSON items → exit 3 (LOUD, never a silent default)" {
  run "$WP" --items 'not-json'
  [ "$status" -eq 3 ]
}

@test "config: an invalid slot in an item → exit 3 (never a silent default)" {
  run "$WP" --items '[{"id":"a","slot":"chief-vibes-officer"}]'
  [ "$status" -eq 3 ]
}
