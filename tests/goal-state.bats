#!/usr/bin/env bats
# goal-state — the ONE shared predicate "does this session have a LIVE /goal?".
#
# Subject: hooks/lib/goal-state.sh :: goal_live_condition. Consumers: mailbox-drain.sh (wake-path
# nag), session-continue.sh (WAKE FLOOR abstain), validate-bash.sh (parked-watcher deny),
# handoff-fire.sh (--recycle goal inheritance). Mechanism the consumers exist to protect:
# docs/research/goal-in-handoff-2026-08-08.md — CC deletes the /goal Stop hook at any Stop where a
# non-terminal local_bash task exists, so an instructed `cc-await-ping` background arm makes an
# armed goal silently inert.
#
# The load-bearing negatives: the PROSE decoy (a bare grep of `goal_status` matches the assistant
# talking about goals — measured 6 hits where the truth was 1) and LAST-record-wins ordering (a
# cleared goal must not read as live because an older arm marker exists).

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/hooks/lib/goal-state.sh"
  D="$BATS_TEST_TMPDIR"
  if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
}

probe() { # <transcript-path> → runs the predicate in a clean bash
  run bash -c ". '$LIB'; goal_live_condition '$1'"
}

arm_rec()   { printf '{"type":"attachment","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"%s"}}\n' "$1"; }
unmet_rec() { printf '{"type":"attachment","attachment":{"type":"goal_status","met":false,"condition":"%s","reason":"still open"}}\n' "$1"; }
met_rec()   { printf '{"type":"attachment","attachment":{"type":"goal_status","met":true,"condition":"%s","iterations":2}}\n' "$1"; }
clear_rec() { printf '{"type":"attachment","attachment":{"type":"goal_status","met":true,"sentinel":true,"condition":"%s"}}\n' "$1"; }
fail_rec()  { printf '{"type":"attachment","attachment":{"type":"goal_status","met":false,"failed":true,"condition":"%s"}}\n' "$1"; }
prose()     { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"a goal_status with met false sentinel true is the arm marker"}]}}\n'; }

@test "LIVE: arm marker (sentinel, met:false) → rc 0 + prints the condition" {
  { prose; arm_rec "finish the migration"; } > "$D/t.jsonl"
  probe "$D/t.jsonl"
  [ "$status" -eq 0 ]
  [ "$output" = "finish the migration" ]
}

@test "LIVE: evaluated-unmet (non-sentinel met:false) → rc 0" {
  { arm_rec "finish"; unmet_rec "finish"; } > "$D/t.jsonl"
  probe "$D/t.jsonl"
  [ "$status" -eq 0 ]
  [ "$output" = "finish" ]
}

@test "NOT live: achieved (met:true) is terminal even after an arm" {
  { arm_rec "finish"; unmet_rec "finish"; met_rec "finish"; } > "$D/t.jsonl"
  probe "$D/t.jsonl"
  [ "$status" -eq 1 ]
}

@test "NOT live: /goal clear marker (sentinel met:true)" {
  { arm_rec "finish"; clear_rec "finish"; } > "$D/t.jsonl"
  probe "$D/t.jsonl"
  [ "$status" -eq 1 ]
}

@test "NOT live: evaluator judged IMPOSSIBLE (failed:true) — CC cleared the goal" {
  { arm_rec "finish"; fail_rec "finish"; } > "$D/t.jsonl"
  probe "$D/t.jsonl"
  [ "$status" -eq 1 ]
}

@test "RE-ARM after clear reads live again (last record wins in both directions)" {
  { arm_rec "one"; clear_rec "one"; arm_rec "two"; } > "$D/t.jsonl"
  probe "$D/t.jsonl"
  [ "$status" -eq 0 ]
  [ "$output" = "two" ]
}

@test "NOT live: prose-only decoy — the token with no attachment must not read as a goal" {
  { prose; prose; } > "$D/t.jsonl"
  probe "$D/t.jsonl"
  [ "$status" -eq 1 ]
}

@test "NOT live: absent file, empty arg" {
  probe "$D/absent.jsonl"; [ "$status" -eq 1 ]
  run bash -c ". '$LIB'; goal_live_condition ''"; [ "$status" -eq 1 ]
}

@test "tilde-headed transcript path resolves under \$HOME" {
  mkdir -p "$HOME/tr"
  arm_rec "via tilde" > "$HOME/tr/t.jsonl"
  # shellcheck disable=SC2088  # the LITERAL tilde is the subject: hook payloads carry
  # tilde-headed transcript_path values and the lib must expand them itself
  probe "~/tr/t.jsonl"
  [ "$status" -eq 0 ]
  [ "$output" = "via tilde" ]
}

@test "a corrupt line among the grep hits fails toward NO goal, never toward live" {
  { arm_rec "finish"; printf '{"type":"attachment","attachment":{"type":"goal_status"\n'; } > "$D/t.jsonl"
  probe "$D/t.jsonl"
  [ "$status" -eq 1 ]
}
