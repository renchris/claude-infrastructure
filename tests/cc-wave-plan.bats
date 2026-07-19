#!/usr/bin/env bats
# T-P7-6 cc-wave-plan — quota-aware wave placement. The tool's `selftest` RED-proves every edge against
# stubbed accounts + cc-route; these bats add (a) the selftest exit-code + check-count contract and
# (b) independent real-CLI `--items … --json` runs through the override surface — proving placement,
# the Fable-window straddle guard, the ≤N/account cap, and the quota-cliff STOP outside the selftest.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WP="$REPO/bin/cc-wave-plan"
  C="$BATS_TEST_TMPDIR/case"
  mkdir -p "$C/bin"

  # accounts stub — --rank general (STUB_RANK space-list; set-but-empty = cliff) · --json (window
  # deadline = now + STUB_WIN_MIN minutes, default 600 = wide open; rows = STUB_ROWS JSON array,
  # default [] = every account idle → live-load seed 0 → pure round-robin).
  cat > "$C/bin/claude-accounts" <<'STUB'
#!/bin/bash
case "${1:-}" in
  --rank) i=0; for n in ${STUB_RANK-next next4 next3 next2}; do printf '%s 0.%03d\n' "$n" $((900-i)); i=$((i+1)); done ;;
  --json) m="${STUB_WIN_MIN:-600}"
    dl="$(date -u -v+"${m}"M +%Y-%m-%dT%H:%M:%S+00:00 2>/dev/null || date -u -d "+${m} minutes" +%Y-%m-%dT%H:%M:%S+00:00)"
    printf '{"window":{"active":true,"deadline":"%s"},"rows":%s}\n' "$dl" "${STUB_ROWS:-[]}" ;;
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
@test "selftest passes and runs all 23 checks (a zero-check suite must not 'pass')" {
  run "$WP" selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 23 ]
  ! printf '%s' "$output" | grep -q '^  FAIL'
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
  ! printf '%s' "$output" | grep -q fable
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
  [ -z "$output" ] || ! printf '%s' "$output" | jq -e . >/dev/null 2>&1   # no JSON plan emitted
  run bash -c "'$WP' --items '[{\"id\":\"a\",\"slot\":\"lead\"}]' 2>&1 1>/dev/null"
  printf '%s' "$output" | grep -q limit-recover
}

@test "cliff: wave exceeds total concurrency (5 items, MAX=2, 2 accounts) → exit 4" {
  export STUB_RANK='acctA acctB' CC_WAVE_MAX_PER_ACCT=2
  run "$WP" --items '[{"id":"1","slot":"lead"},{"id":"2","slot":"lead"},{"id":"3","slot":"lead"},{"id":"4","slot":"lead"},{"id":"5","slot":"lead"}]'
  [ "$status" -eq 4 ]
}

@test "cliff: a cc-route quota cliff propagates → exit 4" {
  export STUB_ROUTE_CLIFF=1
  run "$WP" --items '[{"id":"a","slot":"lead"}]'
  [ "$status" -eq 4 ]
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
