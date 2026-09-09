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

# ══ THE PIPEFAIL INVERSION (W1a · A04 § 3, exhaustive-drive 2026-09-08) ═══════════════════════════
#
# THE DEFECT. Both readers were `grep … | jq …`, and BOTH consumers run `set -o pipefail`
# (`goal-inert-watch.sh:90`, `wrap-ledger.sh`). grep's NO-MATCH status is 1, so under pipefail the
# pipeline's status was 1 however well jq did, `|| return 1` fired, and a transcript that simply
# never armed a goal — the commonest state on this box — was reported UNREADABLE. Measured on
# 2026-09-08: 375 of 469 goal-inert-watch evaluations logged `goal-unreadable`, and 47 of 48 sampled
# sids had ZERO `goal_status` lines. The oracle's own header calls this out in the other direction
# ("a failure must never wear `absent`"); the inverse is just as wrong, and it is what shipped.
#
# WHY EVERY CASE ABOVE WAS BLIND TO IT, and it is the HARNESS, not the assertions. `live_probe`
# runs `bash -c ". LIB; goal_liveness …"` with NO pipefail, so the pipeline took jq's status and the
# bug could not appear — and the one goal-less fixture in this suite (`prose`) contains the literal
# token `goal_status`, so grep MATCHED and returned 0 even under pipefail. A fixture that is
# goal-less in the way production is goal-less — the token appears NOWHERE — plus the consumer's own
# shell options, is what makes this observable at all.
#
# THE FIX MUST KEEP THREE OUTCOMES, NOT TWO. A bare `|| true` on the pipeline would satisfy the
# ABSENT case and re-create the laundering the header forbids, so the corrupt case below is not a
# nicety: it is the half of the red-proof that pins the distinct "grep succeeded, jq failed" rc.

pf_probe() { # <transcript-path> → runs the oracle under the CONSUMERS' shell options
  run bash -c "set -uo pipefail; . '$LIB'; goal_liveness '$1'"
}

# goal-less the way a real transcript is: the token `goal_status` appears on no line at all.
no_goal_at_all() {
  printf '{"type":"user","message":{"role":"user","content":"land the migration"}}\n'
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}}\n'
}

@test "PIPEFAIL: a transcript with ZERO goal_status lines is ABSENT, never UNREADABLE" {
  no_goal_at_all > "$D/t.jsonl"
  [ "$(grep -c 'goal_status' "$D/t.jsonl" || true)" -eq 0 ]   # fixture integrity: grep finds nothing
  pf_probe "$D/t.jsonl"
  [ "$status" -eq 0 ]                       # ← RED pre-fix: grep's no-match 1 became the pipeline's
  [ "$(tsv_field "$output" 1)" = "absent" ]
  [ "$(tsv_field "$output" 2)" = "0" ]
  [ "$(tsv_field "$output" 3)" = "none" ]
}

@test "PIPEFAIL: a CORRUPT record still returns rc 1 — 'absent' is never worn by a failure" {
  # The other half of the proof. Pre-fix these two fixtures are INDISTINGUISHABLE (both rc 1);
  # post-fix they must separate, and this is the one that must NOT move.
  { arm_rec "finish"; printf '{"type":"attachment","attachment":{"type":"goal_status"\n'; } > "$D/c.jsonl"
  pf_probe "$D/c.jsonl"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "PIPEFAIL: a LIVE goal still reads live — the fix does not disturb the matched path" {
  { prose; t_arm_rec "land it" "2026-08-15T12:31:04.123Z"; } > "$D/t.jsonl"
  pf_probe "$D/t.jsonl"
  [ "$status" -eq 0 ]
  [ "$(tsv_field "$output" 1)" = "live" ]
  [ "$(tsv_field "$output" 5)" = "land it" ]
}

@test "PIPEFAIL: goal_live_condition takes the same leg — goal-less is 'not live', not an error" {
  # The predicate's rc is 1 either way (no goal ⇒ not live), so this case cannot go red on its own.
  # It is here because the two functions share one pipeline shape and must not drift again: a
  # future maintainer fixing only the oracle would leave the predicate inverted with no test
  # anywhere that could tell. The MUTATION below is what actually gives this file teeth.
  no_goal_at_all > "$D/t.jsonl"
  run bash -c "set -uo pipefail; . '$LIB'; goal_live_condition '$D/t.jsonl'"
  [ "$status" -eq 1 ]
  { prose; arm_rec "still live"; } > "$D/l.jsonl"
  run bash -c "set -uo pipefail; . '$LIB'; goal_live_condition '$D/l.jsonl'"
  [ "$status" -eq 0 ]
  [ "$output" = "still live" ]
}

@test "MUTATION: restoring the bare grep leg re-inverts ABSENT into UNREADABLE" {
  # Neuters exactly the fix — `_goal_grep` becomes the bare `grep` it replaced — and asserts the
  # ABSENT case flips back. Without this, the three cases above would pass on any implementation
  # that happens to be correct today, including one that swallows grep's ERROR status too.
  m="$D/mutant.sh"
  sed 's/^  \[ "\$_gg_rc" -le 1 \] && return 0$/  [ "$_gg_rc" -eq 0 ] \&\& return 0/' "$LIB" > "$m"
  # THE `|| false` IS LOAD-BEARING, and so is the fact that it is not `&& false`. A bare
  # `! cmp -s …` on its own line is EXEMPT from errexit under bats and asserts nothing
  # (MEMORY.md negated-assertion-dead-unless-final); `cmp -s … && false` is dead the other way,
  # because errexit does not reach the LHS of an `&&` either — scripts/bats-assert-liveness-lint
  # names that class `and-absorbed` and it caught this very line in the ship gate. Only making
  # `false` the LAST command of an OR-list actually fails the test.
  ! cmp -s "$LIB" "$m" || false              # the mutation really applied
  grep -q '\-eq 0 \] && return 0' "$m"       # …and applied to the LINE the fix added
  no_goal_at_all > "$D/t.jsonl"
  run bash -c "set -uo pipefail; . '$m'; goal_liveness '$D/t.jsonl'"
  [ "$status" -eq 1 ]                        # ← flipped: the pre-fix defect, reproduced on demand
  [ -z "$output" ]
}
