#!/usr/bin/env bats
# validate-bash goal guard — the CHOKEPOINT that stops a session disabling its own /goal.
#
# Subject: hooks/validate-bash.sh, LIVE-/goal guard. Mechanism: CC deletes the /goal Stop hook at
# any Stop where the task registry holds a non-terminal local_bash task
# (docs/research/goal-in-handoff-2026-08-08.md § RESOLVED) — and CLAUDE.md § Agent Teams instructs
# every wave lead to arm exactly such a task (`cc-await-ping`, Bash run_in_background). The guard
# denies that one arm, only under a live goal (MEMORY.md enforcement-must-live-at-the-chokepoint:
# gate the act's own tool call, and let the gate teach the alternative).
#
# The discriminators are the suite: foreground cc-await-ping (cc-wait's use) passes, a goal-less
# session passes, a met goal passes, an unreadable transcript passes (fail-open). Only the exact
# self-sabotage shape is refused.
#
# ── WIDENED 2026-08-11 (backlog 0e021a9d68e3) ────────────────────────────────────────────────────
# The guard used to sit on ONE door. The measured incident (lead pane 248, same day) went through
# the other: a hand-rolled `until … ; do sleep 10; done` monitor, backgrounded, held the registry
# non-terminal for ~2 h and 8 peer pings sat undelivered. Cases 8+ cover the CLASS the guard now
# keys on — park-by-construction — and every DENY below is PAIRED with the control that differs by
# exactly one lever, because a guard that always fires discriminates nothing
# (MEMORY.md alarm-polarity-and-attention-budget, positive-control-the-denominator):
#   deny poll-loop            ↔ (9) the same loop with NO goal · (10) the same loop in FOREGROUND
#   deny sleep 300            ↔ (13) sleep 5 — the threshold, not the verb
#   deny tail -f              ↔ (15) tail -n 100 — the follow flag, not the tool
#   deny cd && cc-await-ping  ↔ (6) a bg SEARCH for the same literal
# and (11)/(12) are the "do not be too wide" controls the brief names outright: an ordinary short
# background build, and a bounded `for` loop, both under a LIVE goal, both silent.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/validate-bash.sh"
  D="$BATS_TEST_TMPDIR"
  # Ambient seams pinned (this repo's recurring latent-unhermetic class): the hook itself is
  # terminal-blind, but it sources hooks/lib/*.sh by a $HOME fallback chain and logs under $HOME,
  # so a stray terminal id or an operator threshold must never decide a verdict here.
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  unset CC_GOAL_BG_SLEEP_SECS
  if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
}

live_goal_tx() {
  printf '{"type":"attachment","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"resolve the goal-inertness conflict"}}\n' > "$D/t.jsonl"
  printf '%s' "$D/t.jsonl"
}
no_goal_tx() {
  printf '{"type":"user","message":{"content":"hello"}}\n' > "$D/t.jsonl"
  printf '%s' "$D/t.jsonl"
}
met_goal_tx() {
  { printf '{"type":"attachment","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"x"}}\n'
    printf '{"type":"attachment","attachment":{"type":"goal_status","met":true,"condition":"x","iterations":1}}\n'
  } > "$D/t.jsonl"
  printf '%s' "$D/t.jsonl"
}

probe() { # <command> <run_in_background:true|false> <transcript>
  run bash -c 'jq -nc --arg c "$1" --argjson b "$2" --arg t "$3" \
    "{tool_input:{command:\$c, run_in_background:\$b}, transcript_path:\$t}" | "$0"' \
    "$HOOK" "$1" "$2" "$3"
}
denied() { printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; }

@test "DENIES: background cc-await-ping under a LIVE goal — and the reason teaches the mechanism" {
  probe "$HOME/.claude/bin/cc-await-ping --timeout 14400 --interval 15" true "$(live_goal_tx)"
  [ "$status" -eq 0 ]
  denied "$output"
  printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -q 'skips /goal evaluation' || false
  printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -q 'session-continue.sh set' || false
}

@test "PASSES: the same arm with NO goal in the transcript (the ordinary wave-lead case)" {
  printf '{"type":"user","message":{"content":"hello"}}\n' > "$D/t.jsonl"
  probe "cc-await-ping --timeout 14400" true "$D/t.jsonl"
  [ "$status" -eq 0 ]
  ! denied "$output" || false
}

@test "PASSES: a MET goal is no goal (last record wins)" {
  probe "cc-await-ping --timeout 14400" true "$(met_goal_tx)"
  ! denied "$output" || false
}

@test "PASSES: FOREGROUND cc-await-ping under a live goal (cc-wait's use — terminal by Stop time)" {
  probe "cc-await-ping --timeout 60" false "$(live_goal_tx)"
  ! denied "$output" || false
}

@test "PASSES: an unreadable transcript fails OPEN (never strand a wake path on a read failure)" {
  probe "cc-await-ping --timeout 14400" true "$D/absent.jsonl"
  ! denied "$output" || false
}

@test "DISCRIMINATOR: a background SEARCH that merely mentions cc-await-ping is NOT denied" {
  probe "rg -n 'cc-await-ping' docs/" true "$(live_goal_tx)"
  [ "$status" -eq 0 ]
  ! denied "$output" || false
}

@test "DENIES the path spelling too (\$HOME/.claude/bin/cc-await-ping — the nags' exact string)" {
  probe "/some/home/.claude/bin/cc-await-ping --timeout 14400 --interval 15" true "$(live_goal_tx)"
  denied "$output"
}

# ── the CLASS: park-by-construction, each deny paired with its control ───────────────────────────

@test "(8) DENIES the MEASURED incident verbatim: a bg until/sleep poller under a LIVE goal" {
  probe "until /usr/bin/grep -qE '^→ fired:|ABORT|refus' /tmp/fire-w3.log; do sleep 10; done" \
        true "$(live_goal_tx)"
  [ "$status" -eq 0 ]
  denied "$output"
  r="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')"
  printf '%s' "$r" | grep -q 'event-polling loop' || false
  printf '%s' "$r" | grep -q 'skips /goal evaluation' || false
  printf '%s' "$r" | grep -q 'session-continue.sh set' || false
}

@test "(9) CONTROL: the same poller with NO goal passes SILENTLY (the guard discriminates)" {
  probe "until /usr/bin/grep -qE '^→ fired:' /tmp/fire-w3.log; do sleep 10; done" \
        true "$(no_goal_tx)"
  [ "$status" -eq 0 ]
  ! denied "$output" || false
  # SILENTLY: not merely "not denied" — the hook emits NOTHING. A guard that answered every
  # backgrounded command with advice would still pass a `! denied` assertion.
  [ -z "$output" ] || false
}

@test "(10) CONTROL: the same poller in the FOREGROUND under a live goal passes (keys on bg)" {
  probe "until /usr/bin/grep -qE '^→ fired:' /tmp/fire-w3.log; do sleep 10; done" \
        false "$(live_goal_tx)"
  [ "$status" -eq 0 ]
  ! denied "$output" || false
}

@test "(11) CONTROL: an ordinary short background BUILD under a live goal is untouched" {
  probe "pnpm build" true "$(live_goal_tx)"
  [ "$status" -eq 0 ]
  ! denied "$output" || false
}

@test "(12) CONTROL: a BOUNDED for-loop with a sleep is a different shape — not denied" {
  probe "for i in 1 2 3; do sleep 1; echo \$i; done" true "$(live_goal_tx)"
  [ "$status" -eq 0 ]
  ! denied "$output" || false
}

@test "(13) DENIES an explicit park (sleep 300) — and sleep 5 is NOT the hazard" {
  probe "sleep 300; echo woke" true "$(live_goal_tx)"
  denied "$output"
  printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -q '300s park' || false
  probe "sleep 5; echo woke" true "$(live_goal_tx)"
  ! denied "$output" || false
}

@test "(14) the park threshold is a KNOB, and the same command flips with it" {
  # export/unset explicitly rather than `VAR=v probe …`: a var-prefixed FUNCTION call persists
  # after the call in bash, which would silently make the second half of this test run under the
  # first half's threshold and assert nothing.
  export CC_GOAL_BG_SLEEP_SECS=3
  probe "sleep 5" true "$(live_goal_tx)"
  denied "$output"
  unset CC_GOAL_BG_SLEEP_SECS
  probe "sleep 5" true "$(live_goal_tx)"
  ! denied "$output" || false
}

@test "(15) DENIES a follow-mode tail — and a bounded tail -n is untouched" {
  probe "tail -f /tmp/wave.log" true "$(live_goal_tx)"
  denied "$output"
  printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -q 'follow-mode tail' || false
  probe "tail -n 100 /tmp/wave.log" true "$(live_goal_tx)"
  ! denied "$output" || false
}

@test "(16) COMMAND POSITION: a compound cd && cc-await-ping is caught in its own segment" {
  probe "cd /tmp && cc-await-ping --timeout 14400" true "$(live_goal_tx)"
  denied "$output"
}

# ── C6 CARVE-OUT (2026-08-16): the chokepoint admits its own cure ────────────────────────────────
# docs/research/goal-safe-2way-comms-2026-08-13.md §4, backlog 6290f0ee6b52. Denying the whole class
# left a goal-armed session with NO idle mode: park and starve the goal, or stay bare and spin it
# (90 unmet evaluations in 76 min, measured). `--idle-scoped` is the third mode — it stands itself
# down on any new turn of its own session, so its deferral spans exactly the idle window. The gate
# admits that ONE shape, and the deny text teaches it, because a chokepoint that refuses without
# naming the alternative is what produced the spin pole in the first place.

@test "(17) ADMITS: cc-await-ping --idle-scoped under a LIVE goal (the one sanctioned parked shape)" {
  probe "$HOME/.claude/bin/cc-await-ping --idle-scoped --sid abc-123" true "$(live_goal_tx)"
  [ "$status" -eq 0 ]
  ! denied "$output" || false
}

@test "(18) CONTROL: the SAME command WITHOUT the flag is still denied (the flag is the whole lever)" {
  probe "$HOME/.claude/bin/cc-await-ping --sid abc-123" true "$(live_goal_tx)"
  denied "$output"
}

@test "(19) the deny TEACHES the admitted form, and names THIS session's id" {
  run bash -c 'jq -nc --arg c "$1" --arg t "$2" \
    "{tool_input:{command:\$c, run_in_background:true}, transcript_path:\$t, session_id:\"sid-xyz\"}" | "$0"' \
    "$HOOK" "cc-await-ping --timeout 14400" "$(live_goal_tx)"
  denied "$output"
  r="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')"
  printf '%s' "$r" | grep -q -- '--idle-scoped --sid sid-xyz' || false
  # the pre-existing contract is unbroken: the mechanism and the goal-safe continuation lever stay
  printf '%s' "$r" | grep -q 'skips /goal evaluation' || false
  printf '%s' "$r" | grep -q 'session-continue.sh set' || false
}

@test "(20) with NO session_id the deny still teaches the form, as a placeholder — never a broken command" {
  probe "cc-await-ping --timeout 14400" true "$(live_goal_tx)"
  denied "$output"
  printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason' \
    | grep -q -- "--idle-scoped --sid <this session's id>" || false
}

@test "(21) the carve-out is PER-SEGMENT: an idle-scoped arm elsewhere does not launder a parked one" {
  # the flag belongs to the cc-await-ping it is written on. A compound that arms the safe shape AND
  # parks a 4-hour one still parks a 4-hour one, and the registry cannot tell them apart.
  probe "cc-await-ping --idle-scoped --sid a && cc-await-ping --timeout 14400" true "$(live_goal_tx)"
  denied "$output"
}

@test "(22) the carve-out does NOT reach the loop shape: --idle-scoped inside a poller is still denied" {
  # shape (1) is judged over the intact command and never looks at flags — correctly, because the
  # LOOP is the parker there, and a watcher that self-cancels inside a loop that restarts it is not
  # idle-scoped at all.
  probe "while true; do cc-await-ping --idle-scoped --sid a; sleep 30; done" true "$(live_goal_tx)"
  denied "$output"
  printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -q 'event-polling loop' || false
}

@test "(23) a substring is not the flag: --idle-scopedX does not open the gate" {
  probe "cc-await-ping --idle-scopedX --timeout 14400" true "$(live_goal_tx)"
  denied "$output"
}
