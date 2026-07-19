#!/usr/bin/env bats
# cc-audit — machine-GATE half of the auditability floor (axis k, P7/D9).
#   abstain [--json] [-n N]   D9 distribution monitor; exit 6 when a hook abstained==100% over >=N
#   wave [--since ISO]        the four zeros (unplanned·signal-divergence·orphaned-intent·missed-fire)
#                             with basis+verdict; exit 0 PASS · 1 FAIL · 4 INCOMPLETE(UNPROVEN)
#
# Harness laws (§3.10): L1 fixtures are REAL IDL JSONL the tool parses (no reconstructed report); L2
# asserts on failure-distinct strings + exact exit codes (6/1/4/0, ALARM/FAIL/UNPROVEN/PASS); L3
# every assertion is `[ ]`/`grep -q` (trap under errexit); L4 EACH behaviour carries its negative
# twin — the forced-alarm test (exit 6) is paired with a mixed/low-N no-alarm test (exit 0), and the
# UNPROVEN test proves a basis==0 zero is NOT laundered into a green PASS (the inert-detector trap).
# CC_NOW pins the window so every fixture timestamp is deterministic.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  AUDIT_BIN="$REPO/bin/cc-audit"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_NOW="2026-07-19T08:30:00Z"     # window anchor: abstain=7d back, wave=24h back
  : > "$CC_IDL"
}

hook_rec() { printf '{"ts":"%s","hook":"%s","sid":"%s","disposition":"%s","reason":"x"}\n' "$1" "$2" "$3" "$4" >> "$CC_IDL"; }
kind_rec() { printf '%s\n' "$1" >> "$CC_IDL"; }

# ════════════════════════════ abstain (the D9 monitor) ══════════════════════════════════════
@test "DoD: a FORCED 100%-abstain over N>=10 fires the alarm (exit 6)" {
  local i; for i in $(seq 1 12); do hook_rec "2026-07-19T08:0${i}:00Z" "deadhook" "s$i" "abstained"; done
  run bash "$AUDIT_BIN" abstain
  [ "$status" -eq 6 ]
  echo "$output" | grep -q "ALARM"
  echo "$output" | grep -q "deadhook"
}

@test "a single fire among the abstains EXONERATES the hook (no alarm, exit 0)" {
  local i; for i in $(seq 1 12); do hook_rec "2026-07-19T08:0${i}:00Z" "deadhook" "s$i" "abstained"; done
  hook_rec "2026-07-19T08:20:00Z" "deadhook" "sf" "fired"
  run bash "$AUDIT_BIN" abstain
  [ "$status" -eq 0 ]
}

@test "below N recent evals cannot alarm — low-sample protection (exit 0)" {
  local i; for i in $(seq 1 5); do hook_rec "2026-07-19T08:0${i}:00Z" "lowhook" "s$i" "abstained"; done
  run bash "$AUDIT_BIN" abstain
  [ "$status" -eq 0 ]
}

@test "records older than the horizon do not count toward the alarm" {
  local i; for i in $(seq 1 12); do hook_rec "2026-06-01T08:0${i}:00Z" "oldhook" "s$i" "abstained"; done
  run bash "$AUDIT_BIN" abstain            # all 12 are >7d before CC_NOW
  [ "$status" -eq 0 ]
}

@test "one inert + one healthy hook: only the inert one alarms (exit 6)" {
  local i
  for i in $(seq 1 12); do hook_rec "2026-07-19T08:0${i}:00Z" "inert" "a$i" "abstained"; done
  for i in $(seq 1 12); do hook_rec "2026-07-19T08:0${i}:00Z" "healthy" "b$i" "fired"; done
  run bash "$AUDIT_BIN" abstain
  [ "$status" -eq 6 ]
  echo "$output" | grep -q "ALARM: hook inert"
  run bash -c "bash '$AUDIT_BIN' abstain 2>&1 | grep 'ALARM' | grep -c healthy"
  [ "$output" = "0" ]
}

@test "actor/kind flood records (no disposition) never fabricate a hook" {
  local i; for i in $(seq 1 200); do kind_rec "{\"ts\":\"2026-07-19T08:0$((i%9)):00Z\",\"actor\":\"lead-supervisor\",\"kind\":\"page\",\"sid\":\"d$i\"}"; done
  run bash "$AUDIT_BIN" abstain
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "no inert hooks"
}

@test "abstain --json emits a structured row with the alarm boolean" {
  local i; for i in $(seq 1 11); do hook_rec "2026-07-19T08:0${i}:00Z" "deadhook" "s$i" "abstained"; done
  run bash "$AUDIT_BIN" abstain --json
  [ "$status" -eq 6 ]
  echo "$output" | jq -e '.[] | select(.hook=="deadhook") | .alarm == true and .abstained == 11' >/dev/null
}

# ── arg-parse robustness (regressions for the reviewer's BUG A/B/C) ──────────────────────────
@test "abstain -n with NO value fails fast (exit 2), never hangs" {
  run timeout 5 bash "$AUDIT_BIN" abstain -n
  [ "$status" -eq 2 ]                       # 124 (timeout) would mean the shift-2 hang regressed
}

@test "abstain -n with a NON-NUMERIC value fails loud, never SILENTLY suppresses the alarm" {
  local i; for i in $(seq 1 12); do hook_rec "2026-07-19T08:0${i}:00Z" "deadhook" "s$i" "abstained"; done
  run bash "$AUDIT_BIN" abstain -n abc      # would-be jq --argjson crash → empty rows → missed alarm
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "positive integer"
}

@test "abstain -n 0 is rejected (a threshold must be a positive integer)" {
  run bash "$AUDIT_BIN" abstain -n 0
  [ "$status" -eq 2 ]
}

@test "abstain -n with a valid value still works (proves the guard didn't break the flag)" {
  local i; for i in $(seq 1 3); do hook_rec "2026-07-19T08:0${i}:00Z" "deadhook" "s$i" "abstained"; done
  run bash "$AUDIT_BIN" abstain -n 3        # 3 abstained, threshold 3 → alarm
  [ "$status" -eq 6 ]
}

@test "wave --since with NO value fails fast (exit 2), never hangs" {
  run timeout 5 bash "$AUDIT_BIN" wave --since
  [ "$status" -eq 2 ]
}

# ── malformed-input robustness (regression for backlog 666c6a64c45e / the silent-green defect) ─
# A single unparseable line (unescaped quote in a value) used to abort the `jq -s` slurp → empty
# rows → the alarm/FAIL SILENTLY went green: the inert-verifier trap turned on the auditor's own
# input (§1 inv2, the Blind-Check Law). RED-proven: revert the 4 jq sites to `jq -rs` and these
# fail (abstain exits 0 not 6; wave stops FAILing). The poison bytes ARE the completion-assert bug.
poison_disp() { printf '%s\n' '{"ts":"2026-07-19T08:15:00Z","hook":"badhook","sid":"sx","disposition":"blocked because "quoted" reason"}' >> "$CC_IDL"; }

@test "abstain: a poison IDL line does NOT silently suppress the alarm (still exit 6)" {
  local i; for i in $(seq 1 12); do hook_rec "2026-07-19T08:0${i}:00Z" "deadhook" "s$i" "abstained"; done
  poison_disp                                # unparseable — old `jq -rs` aborted → exit 0 (silent-green)
  run bash "$AUDIT_BIN" abstain
  [ "$status" -eq 6 ]
  echo "$output" | grep -q "ALARM: hook deadhook"
}

@test "abstain: an unparseable line is reported LOUDLY, never hidden" {
  local i; for i in $(seq 1 12); do hook_rec "2026-07-19T08:0${i}:00Z" "deadhook" "s$i" "abstained"; done
  poison_disp
  run bash "$AUDIT_BIN" abstain
  echo "$output" | grep -q "unparseable IDL line"
}

@test "clean input emits NO malformed warning (warn_malformed does not false-positive)" {
  local i; for i in $(seq 1 3); do hook_rec "2026-07-19T08:0${i}:00Z" "h" "s$i" "fired"; done
  run bash "$AUDIT_BIN" abstain
  ! echo "$output" | grep -q "unparseable"
}

@test "wave: a poison line does not zero out a real FAIL (page_escalate still FAILs, exit 1)" {
  kind_rec '{"ts":"2026-07-19T08:00:00Z","actor":"lead-supervisor","kind":"heartbeat","swept":9,"findings":0}'
  kind_rec '{"ts":"2026-07-19T08:05:00Z","actor":"lead-supervisor","kind":"page_escalate","sid":"esc1"}'
  printf '%s\n' '{"ts":"2026-07-19T08:06:00Z","actor":"lead-supervisor","kind":"page","state":"escalated to "human" now"}' >> "$CC_IDL"
  run bash "$AUDIT_BIN" wave                 # old slurp aborted the sup metric → unplanned UNPROVEN → exit 4, hiding the escalation
  [ "$status" -eq 1 ]
  echo "$output" | grep -qE 'unplanned +1 .*FAIL'
}

# ════════════════════════════ wave (the four zeros) ══════════════════════════════════════════
@test "wave with an active observer but no defects: unplanned+orphaned PASS, div+mf UNPROVEN → INCOMPLETE (exit 4)" {
  kind_rec '{"ts":"2026-07-19T08:00:00Z","actor":"lead-supervisor","kind":"heartbeat","swept":9,"findings":0}'
  kind_rec '{"ts":"2026-07-19T08:10:00Z","actor":"lead-supervisor","kind":"checkpoint","sid":"s1","cwd":"/x","why":"routine"}'
  run bash "$AUDIT_BIN" wave
  [ "$status" -eq 4 ]
  echo "$output" | grep -qE 'unplanned +0 +basis=[1-9].* PASS'
  echo "$output" | grep -qE 'signal-divergence +0 +basis=0 +UNPROVEN'
  echo "$output" | grep -qE 'orphaned-intent +0 +basis=[1-9].* PASS'
  echo "$output" | grep -q "WAVE: INCOMPLETE"
}

@test "HONESTY: a basis==0 zero is UNPROVEN, never laundered into a green PASS" {
  # The inert-detector trap, applied to the auditor itself: with no snapshot/replay source records,
  # signal-divergence and missed-fire must read UNPROVEN and the wave must NOT be PASS. A tool that
  # printed "0 → PASS" here would be the exact fake-green bug this layer exists to kill.
  kind_rec '{"ts":"2026-07-19T08:00:00Z","actor":"lead-supervisor","kind":"heartbeat","swept":1,"findings":0}'
  run bash "$AUDIT_BIN" wave
  [ "$status" -ne 0 ]
  echo "$output" | grep -qE 'missed-fire +0 +basis=0 +UNPROVEN'
  run bash -c "bash '$AUDIT_BIN' wave | grep -c 'WAVE: PASS'"
  [ "$output" = "0" ]
}

@test "a page_escalate makes unplanned FAIL (exit 1)" {
  kind_rec '{"ts":"2026-07-19T08:00:00Z","actor":"lead-supervisor","kind":"heartbeat","swept":1,"findings":1}'
  kind_rec '{"ts":"2026-07-19T08:15:00Z","actor":"lead-supervisor","kind":"page_escalate","sid":"dead1","detail":"operator action needed"}'
  run bash "$AUDIT_BIN" wave
  [ "$status" -eq 1 ]
  echo "$output" | grep -qE 'unplanned +1 .* FAIL'
  echo "$output" | grep -q "WAVE: FAIL"
}

@test "a dark session (page state STALL?) makes orphaned-intent FAIL (exit 1)" {
  kind_rec '{"ts":"2026-07-19T08:00:00Z","actor":"lead-supervisor","kind":"heartbeat","swept":1,"findings":1}'
  kind_rec '{"ts":"2026-07-19T08:12:00Z","actor":"lead-supervisor","kind":"page","state":"STALL?","sid":"d2","detail":"pid alive but telemetry stale"}'
  run bash "$AUDIT_BIN" wave
  [ "$status" -eq 1 ]
  echo "$output" | grep -qE 'orphaned-intent +1 .* FAIL'
}

@test "unplanned dedups by sid — 3 escalations of one session count as 1" {
  kind_rec '{"ts":"2026-07-19T08:00:00Z","actor":"lead-supervisor","kind":"heartbeat","swept":1,"findings":1}'
  local i; for i in 1 2 3; do kind_rec "{\"ts\":\"2026-07-19T08:1${i}:00Z\",\"actor\":\"lead-supervisor\",\"kind\":\"page_escalate\",\"sid\":\"samedead\",\"detail\":\"x\"}"; done
  run bash "$AUDIT_BIN" wave
  [ "$status" -eq 1 ]
  echo "$output" | grep -qE 'unplanned +1 '
}

@test "records older than the wave horizon are excluded (an old escalation does not FAIL today)" {
  kind_rec '{"ts":"2026-07-19T08:00:00Z","actor":"lead-supervisor","kind":"heartbeat","swept":1,"findings":0}'
  kind_rec '{"ts":"2026-07-17T08:00:00Z","actor":"lead-supervisor","kind":"page_escalate","sid":"olddead","detail":"x"}'
  run bash "$AUDIT_BIN" wave     # escalation is >24h before CC_NOW
  [ "$status" -eq 4 ]
  echo "$output" | grep -qE 'unplanned +0 .* PASS'
}

@test "P2 wiring: a reported-vs-truth snapshot past delta makes signal-divergence FAIL; within delta PASSes" {
  kind_rec '{"ts":"2026-07-19T08:00:00Z","actor":"lead-supervisor","kind":"heartbeat","swept":1,"findings":0}'
  kind_rec '{"ts":"2026-07-19T08:05:00Z","kind":"snapshot","reported_pct":40,"truth_pct":92}'
  run bash "$AUDIT_BIN" wave
  [ "$status" -eq 1 ]
  echo "$output" | grep -qE 'signal-divergence +1 .* FAIL'
  # within-delta twin (proves the threshold, not just "any snapshot fails")
  : > "$CC_IDL"
  kind_rec '{"ts":"2026-07-19T08:00:00Z","actor":"lead-supervisor","kind":"heartbeat","swept":1,"findings":0}'
  kind_rec '{"ts":"2026-07-19T08:05:00Z","kind":"snapshot","reported_pct":47,"truth_pct":48}'
  run bash "$AUDIT_BIN" wave
  echo "$output" | grep -qE 'signal-divergence +0 +basis=1 +PASS'
}

@test "P5 wiring: a should-fire-but-didnt replay makes missed-fire FAIL; a clean replay PASSes" {
  kind_rec '{"ts":"2026-07-19T08:00:00Z","actor":"lead-supervisor","kind":"heartbeat","swept":1,"findings":0}'
  kind_rec '{"ts":"2026-07-19T08:06:00Z","kind":"replay","should_fire":true,"fired":false}'
  run bash "$AUDIT_BIN" wave
  [ "$status" -eq 1 ]
  echo "$output" | grep -qE 'missed-fire +1 .* FAIL'
}

@test "all four sources present and zero → full PASS (exit 0), proving INCOMPLETE is earned not hardcoded" {
  kind_rec '{"ts":"2026-07-19T08:00:00Z","actor":"lead-supervisor","kind":"heartbeat","swept":1,"findings":0}'
  kind_rec '{"ts":"2026-07-19T08:05:00Z","kind":"snapshot","reported_pct":47,"truth_pct":48}'
  kind_rec '{"ts":"2026-07-19T08:06:00Z","kind":"replay","should_fire":false,"fired":false}'
  run bash "$AUDIT_BIN" wave
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "WAVE: PASS"
}

@test "an unknown verb exits 2 with usage" {
  run bash "$AUDIT_BIN" frobnicate
  [ "$status" -eq 2 ]
}
