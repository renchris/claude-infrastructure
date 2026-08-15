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

# ══ THE LIVENESS ORACLE (E5, §9 B5) — goal_liveness ═══════════════════════════════════════════════
#
# Subject: hooks/lib/goal-state.sh :: goal_liveness. Consumer: scripts/wrap-ledger.sh (GOAL_* +
# the ◎ line in --full/--goal). The question it answers is the one goal_live_condition CANNOT:
# an armed goal that is never EVALUATED (the starvation pole, 47/84 sessions in §2) is
# indistinguishable from a healthily-deferred one to a predicate that only asks "is it armed?".
#
# The load-bearing cases: 0 evals on a LIVE goal (the pole itself) · evaluations counted SINCE THE
# LAST ARM, never over the file (a re-armed goal must not inherit the previous goal's count) ·
# an unreadable transcript reads as a FAILURE (rc 1), never as `absent`, which is the positive
# finding "this session never armed one".

live_probe() { # <transcript-path> → runs the oracle in a clean bash
  run bash -c ". '$LIB'; goal_liveness '$1'"
}
tsv_field() { printf '%s' "$1" | cut -f"$2"; }

# timestamped variants — the oracle reads the ENVELOPE's .timestamp (that is where CC writes it)
t_arm_rec()   { printf '{"type":"attachment","timestamp":"%s","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"%s"}}\n' "$2" "$1"; }
t_unmet_rec() { printf '{"type":"attachment","timestamp":"%s","attachment":{"type":"goal_status","met":false,"condition":"%s"}}\n' "$2" "$1"; }
t_met_rec()   { printf '{"type":"attachment","timestamp":"%s","attachment":{"type":"goal_status","met":true,"condition":"%s"}}\n' "$2" "$1"; }

@test "ORACLE: armed and never evaluated ⇒ live · 0 evals · last=arm (THE STARVATION POLE)" {
  { prose; t_arm_rec "land it" "2026-08-15T12:31:04.123Z"; } > "$D/t.jsonl"
  live_probe "$D/t.jsonl"
  [ "$status" -eq 0 ]
  [ "$(tsv_field "$output" 1)" = "live" ]
  [ "$(tsv_field "$output" 2)" = "0" ]
  [ "$(tsv_field "$output" 3)" = "arm" ]
  [ "$(tsv_field "$output" 5)" = "land it" ]
}

@test "ORACLE: evaluations are counted, and the last verdict is reported" {
  { t_arm_rec "land it" "2026-08-15T12:31:04.123Z"
    t_unmet_rec "land it" "2026-08-15T13:00:00.000Z"
    t_unmet_rec "land it" "2026-08-15T13:05:00.000Z"; } > "$D/t.jsonl"
  live_probe "$D/t.jsonl"
  [ "$status" -eq 0 ]
  [ "$(tsv_field "$output" 1)" = "live" ]
  [ "$(tsv_field "$output" 2)" = "2" ]
  [ "$(tsv_field "$output" 3)" = "unmet" ]
}

@test "ORACLE: a RE-ARMED goal starts at 0 — the previous goal's evals are never inherited" {
  { t_arm_rec "one" "2026-08-15T10:00:00.000Z"
    t_unmet_rec "one" "2026-08-15T10:05:00.000Z"
    t_met_rec "one" "2026-08-15T10:09:00.000Z"
    t_arm_rec "two" "2026-08-15T11:00:00.000Z"; } > "$D/t.jsonl"
  live_probe "$D/t.jsonl"
  [ "$(tsv_field "$output" 1)" = "live" ]
  [ "$(tsv_field "$output" 2)" = "0" ]      # NOT 2 — the count is since the LAST arm
  [ "$(tsv_field "$output" 5)" = "two" ]
}

@test "ORACLE: met ⇒ cleared · failed ⇒ failed · /goal clear ⇒ cleared+clear" {
  { arm_rec "x"; unmet_rec "x"; met_rec "x"; } > "$D/m.jsonl"
  live_probe "$D/m.jsonl"
  [ "$(tsv_field "$output" 1)" = "cleared" ]
  [ "$(tsv_field "$output" 3)" = "met" ]
  [ "$(tsv_field "$output" 2)" = "2" ]      # the met verdict IS an evaluation

  { arm_rec "x"; fail_rec "x"; } > "$D/f.jsonl"
  live_probe "$D/f.jsonl"
  [ "$(tsv_field "$output" 1)" = "failed" ]
  [ "$(tsv_field "$output" 3)" = "failed" ]

  { arm_rec "x"; clear_rec "x"; } > "$D/c.jsonl"
  live_probe "$D/c.jsonl"
  [ "$(tsv_field "$output" 1)" = "cleared" ]
  [ "$(tsv_field "$output" 3)" = "clear" ]
}

@test "ORACLE: the PROSE decoy is not a goal record — a goal-less transcript reads absent" {
  { prose; prose; } > "$D/t.jsonl"
  live_probe "$D/t.jsonl"
  [ "$status" -eq 0 ]
  [ "$(tsv_field "$output" 1)" = "absent" ]
  [ "$(tsv_field "$output" 2)" = "0" ]
}

@test "ORACLE: unreadable ⇒ rc 1 (a FAILURE), never the positive finding 'absent'" {
  live_probe "$D/nope.jsonl"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  run bash -c ". '$LIB'; goal_liveness ''"
  [ "$status" -eq 1 ]
}

@test "ORACLE: fractional-second ISO stamps parse — the epoch is not silently 0" {
  t_arm_rec "x" "2026-08-15T12:31:04.123Z" > "$D/t.jsonl"
  live_probe "$D/t.jsonl"
  [ "$(tsv_field "$output" 4)" -gt 1000000000 ]
  # …and an unparseable stamp degrades to 0 (the consumer says "time unknown"), never to a wrong clock
  printf '{"type":"attachment","timestamp":"not-a-date","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"x"}}\n' > "$D/u.jsonl"
  live_probe "$D/u.jsonl"
  [ "$status" -eq 0 ]
  [ "$(tsv_field "$output" 4)" = "0" ]
}

@test "ORACLE: a TAB/newline in the condition cannot break the TSV contract" {
  printf '{"type":"attachment","timestamp":"2026-08-15T12:31:04Z","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"a\\tb\\nc"}}\n' > "$D/t.jsonl"
  live_probe "$D/t.jsonl"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c .)" -eq 1 ]     # one line
  [ "$(tsv_field "$output" 1)" = "live" ]
  [ "$(tsv_field "$output" 5)" = "a b c" ]             # field 5 stays field 5
}
