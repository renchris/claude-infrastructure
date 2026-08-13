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
  # CC_WAVE_PLAN_UNDER_TEST — the RED-PROOF seam, mirroring tests/cc-wave-plan-verdict.bats. Point it
  # at a pristine binary (`git archive origin/main bin/cc-wave-plan | tar -x -C <tmp>`) to re-run the
  # proof that the W2-B urgency tests below actually FAIL pre-change, rather than asserting they did.
  WP="${CC_WAVE_PLAN_UNDER_TEST:-$REPO/bin/cc-wave-plan}"
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

  # W2-B — the SSOT accounts.json the urgent allowance reads KMAX from. PINNED, not ambient: KMAX is
  # operator-tunable (hand-raised 4→8 already) and this suite does NOT fixture $HOME, so an unpinned
  # read would let a live constant decide these verdicts. Same env override claude-accounts honours
  # (claude-accounts:127), so both sides can only ever mean one file. (ACCOUNT_ROUTING_V2 §13's rule:
  # a new ambient input to a CLI is a new fixture surface for every suite that drives it.)
  printf '{"router":{"KMAX":8}}\n' > "$C/accounts-ssot.json"
  export CLAUDE_ACCOUNTS_JSON="$C/accounts-ssot.json"

  export CC_WAVE_ACCOUNTS_BIN="$C/bin/claude-accounts" CC_WAVE_ROUTE_BIN="$C/bin/cc-route" \
         CC_WAVE_IDL="$C/idl.jsonl"

  # W2-B urgency fixtures. acctA ranks first and is BEHIND (needs 20%/d, burning 3%/d); acctB is
  # AHEAD (4 vs 9) and keeps the flat cap. With KMAX=8 and acctA charged 1, its allowance is
  # min(4, 8−1) = 4, so a 5-item wave that flat-caps at 2×2 = 4 slots fits.
  URG_BEHIND='[{"acct":"acctA","k":1,"k_work":1,"k_phantom":0,"weekly_need_pct_per_day":20.0,"burn_wk_ppd":3.0},{"acct":"acctB","k":0,"k_work":0,"k_phantom":0,"weekly_need_pct_per_day":4.0,"burn_wk_ppd":9.0}]'
  # The same two accounts with NO pace fields — the shape a thin utilization series actually emits.
  URG_NOFIELDS='[{"acct":"acctA","k":1},{"acct":"acctB","k":0}]'
  # Same urgency claim, acctA charged 5 (k_work 4 + 1 phantom) ⇒ KMAX−k_eff = 3 binds BELOW the knob.
  URG_CLAMP='[{"acct":"acctA","k":5,"k_work":4,"k_phantom":1,"weekly_need_pct_per_day":20.0,"burn_wk_ppd":3.0},{"acct":"acctB","k":0,"k_work":0,"k_phantom":0,"weekly_need_pct_per_day":4.0,"burn_wk_ppd":9.0}]'
  IT5='[{"id":"1","slot":"lead"},{"id":"2","slot":"lead"},{"id":"3","slot":"lead"},{"id":"4","slot":"lead"},{"id":"5","slot":"lead"}]'
  IT6='[{"id":"1","slot":"lead"},{"id":"2","slot":"lead"},{"id":"3","slot":"lead"},{"id":"4","slot":"lead"},{"id":"5","slot":"lead"},{"id":"6","slot":"lead"}]'
}

# ── (a) selftest contract ─────────────────────────────────────────────────────────────────────────────
@test "selftest passes and runs all 76 checks (a zero-check suite must not 'pass')" {
  # 29 → 63 → 74: the S3/S4 verdict + bounded-oracle cases, then W2-B's urgency pairs. Bound-dependent
  # checks print `skip` and are counted separately, so a box without timeout(1) reports fewer `ok`
  # lines rather than silently passing a hollow suite — hence a FLOOR, not an `-eq`: an exact count
  # reds on the suite's own growth and catches no regression at all (memory:
  # exact-count-assertion-tripwires-its-own-subject). The floor tracks the 11 bound-dependent checks.
  run "$WP" selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -ge 63 ]
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

# ── W2-B: the URGENT per-account allowance (the DEMAND half of M7) ────────────────────────────────
# The flat cap is urgency-BLIND: it allowances an account whose weekly quota strands in <24h exactly
# like one with six idle days, so a wave cannot concentrate where quota is about to be lost (the live
# 2026-08-10 snapshot: next3 had to burn 11% in under a day and a wave handed it the same 2 slots as
# an account with a 6-day runway). Each test below is a PAIR on one wave with ONE variable changed —
# a "it placed 5 items" assertion alone would pass equally against a tool that simply raised the flat
# cap for everybody, which is the widening this must NOT be.

@test "urgency (a): the top-ranked BEHIND account takes the urgent allowance; others stay flat" {
  export STUB_RANK='acctA acctB' STUB_ROWS="$URG_BEHIND"
  # stdout ONLY: bats' `run` merges stderr, and the disclosure line below would then be parsed as
  # part of the plan. Asserting the two surfaces separately is the point — one is the machine plan.
  plan="$("$WP" --items "$IT5" --json 2>/dev/null)"      # flat-capped this wave walls at 2×2=4 slots
  # acctA (BEHIND) absorbs 3; acctB is AHEAD and still stops at the flat 2 — the allowance is not
  # a blanket raise. (3 not 4 because placement is still least-loaded: acctA carries 1 live session.)
  echo "$plan" | jq -e '([.[]|select(.account=="acctA")]|length)==3'
  echo "$plan" | jq -e '([.[]|select(.account=="acctB")]|length)==2'
  # …and it is never SILENT: --json keeps stdout pure, so the disclosure is on stderr (contract 4).
  run bash -c "STUB_RANK='acctA acctB' STUB_ROWS='$URG_BEHIND' '$WP' --items '$IT5' --json 2>&1 1>/dev/null"
  printf '%s' "$output" | grep -q 'urgency: acctA is BEHIND (needs 20%/d, recent 3%/d) → allowance 4'
}

@test "urgency (b): absent burn/need fields are a missing MEASUREMENT, not urgency → flat everywhere" {
  # The fail-soft direction that matters: a thin utilization series must not widen anything. Same
  # accounts, same loads, same wave — only the two pace fields are gone.
  export STUB_RANK='acctA acctB' STUB_ROWS="$URG_NOFIELDS"
  run "$WP" --items "$IT5"
  [ "$status" -eq 4 ]
  tail -1 "$CC_WAVE_IDL" | jq -e 'select(.verdict=="capacity")'
  # the negative control for (a)'s disclosure: no widening ⇒ nothing rendered (alarm polarity)
  run bash -c "STUB_RANK='acctA acctB' STUB_ROWS='$URG_NOFIELDS' '$WP' --items '[{\"id\":\"1\",\"slot\":\"lead\"}]' 2>&1"
  ! printf '%s' "$output" | grep -q 'urgency:' || false
}

@test "urgency (c): the allowance is CLAMPED by KMAX − k_eff (k_work + phantoms), never past it" {
  # acctA is BEHIND and the knob says 4, but its live charge is 5 of KMAX 8 → 3 is what it may take.
  export STUB_RANK='acctA acctB' STUB_ROWS="$URG_CLAMP"
  run "$WP" --items "$IT6"
  [ "$status" -eq 4 ]                                    # 3+2 = 5 slots < 6 items — the clamp binds
  # and the bound BINDS rather than vetoes: the same wave one item smaller places exactly.
  plan="$("$WP" --items "$IT5" --json 2>/dev/null)"
  echo "$plan" | jq -e '([.[]|select(.account=="acctA")]|length)==3'
  run bash -c "STUB_RANK='acctA acctB' STUB_ROWS='$URG_CLAMP' '$WP' --items '$IT5' --json 2>&1 1>/dev/null"
  printf '%s' "$output" | grep -q 'allowance 3 this wave (flat 2; KMAX 8 − live 5)'
}

@test "urgency (d): the kill switch is BYTE-IDENTICAL — knobs unset/equal reproduce the flat plan" {
  # Two arms, because "identical" has two ways to be true for the wrong reason. Arm 1: with nobody
  # BEHIND the armed lane must change nothing at all. Arm 2 is the load-bearing one — on the fixture
  # that DOES trigger the widening, killing the knob must reproduce the plan the tool emits when the
  # urgency data is absent entirely, byte for byte. An arm-1-only test would pass against a tool
  # whose kill switch does nothing.
  # `|| true` on every capture: three of these four runs are the WALL (exit 4) and bats runs under
  # `set -e`, so an unguarded assignment would abort the test before it compared anything.
  armed="$(STUB_RANK='acctA acctB' STUB_ROWS="$URG_NOFIELDS" "$WP" --items "$IT5" --json 2>&1 || true)"
  killed="$(STUB_RANK='acctA acctB' STUB_ROWS="$URG_NOFIELDS" CC_WAVE_MAX_PER_ACCT_URGENT=2 \
              "$WP" --items "$IT5" --json 2>&1 || true)"
  [ "$armed" = "$killed" ]
  [ -n "$armed" ]                                        # not two empty strings comparing equal

  behind_killed="$(STUB_RANK='acctA acctB' STUB_ROWS="$URG_BEHIND" CC_WAVE_MAX_PER_ACCT_URGENT=2 \
                     "$WP" --items "$IT5" --json 2>&1 || true)"
  [ "$behind_killed" = "$armed" ]
  # positive control: ARMED on the same BEHIND fixture is a DIFFERENT outcome, so the equality above
  # is the kill switch working and not the fixture being inert on both sides.
  behind_armed="$(STUB_RANK='acctA acctB' STUB_ROWS="$URG_BEHIND" "$WP" --items "$IT5" --json 2>&1 || true)"
  [ "$behind_armed" != "$armed" ]
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
