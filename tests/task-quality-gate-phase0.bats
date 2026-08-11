#!/usr/bin/env bats
#
# The Phase 0 arm of task-quality-gate.sh must be able to REJECT.
#
# It could not. `VERIFY_OUTPUT=$(cmd 2>&1 || true); VERIFY_EXIT=$?` makes the ASSIGNMENT
# the thing whose status is read, and `|| true` forces that to 0 — so VERIFY_EXIT was
# unconditionally 0, the `-ne 0` branch was unreachable, and a verify-team.sh that exited
# non-zero over missing worktrees/branches/settings was logged as "verify passed" and the
# Phase 0 task completed anyway. That is the exact incident the arm was written to prevent.
#
# The pre-existing suite (tests/task-quality-gate.bats) never reached this branch: its
# helper hardcodes task_subject:"do work", which does not match *"Phase 0"*.

setup() {
    unset KITTY_WINDOW_ID ITERM_SESSION_ID
    export IT2_WRAPPER_NO_KITTY=1
    # The hook appends to $HOME/.claude/logs/task-quality-gate.log, and the reach-guard
    # test below GREPS that log — unfixtured, it would both pollute the operator's log and
    # be satisfiable by some earlier real run's line rather than by this test's own.
    export HOME="${BATS_TEST_TMPDIR}/home"; mkdir -p "$HOME"
    REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    HOOK="$REPO/hooks/task-quality-gate.sh"

    # A fake project root whose scripts/team/verify-team.sh we control.
    PROJ="${BATS_TEST_TMPDIR}/proj"
    mkdir -p "$PROJ/scripts/team"
    git -C "$PROJ" init -q 2>/dev/null || true
    VERIFY="$PROJ/scripts/team/verify-team.sh"
}

# $1 = exit code the fake verifier should return
make_verifier() {
    cat > "$VERIFY" <<EOF
#!/usr/bin/env bash
echo "worktree missing for member alpha"
exit $1
EOF
    chmod +x "$VERIFY"
}

run_hook() { # stdin payload; runs with cwd = the fake project
    # TOP-LEVEL fields — the hook reads .task_subject/.team_name directly, not tool_input.*.
    # A nested payload exits at the empty-team guard, which looks identical to "allowed".
    printf '{"task_subject":"Phase 0 setup","teammate_name":"alpha","team_name":"team-x"}' \
        | (cd "$PROJ" && bash "$HOOK")
}

@test "the fake verifier is actually reachable (guards a vacuous suite)" {
    make_verifier 7
    run "$VERIFY" team-x
    [ "$status" -eq 7 ]
}

@test "the payload actually REACHES the Phase 0 arm (guards a vacuous pass)" {
    # Without this, a payload the hook drops early makes every allow-case pass for the
    # wrong reason — the hook's log is the only witness that the arm was entered.
    make_verifier 0
    run run_hook
    run grep -q "Phase 0 task detected" "$HOME/.claude/logs/task-quality-gate.log"
    [ "$status" -eq 0 ]
}

@test "a FAILING Phase 0 verify blocks the task (the regression this pins)" {
    make_verifier 7
    run run_hook
    [ "$status" -eq 2 ]
    [[ "$output" == *"QUALITY GATE FAILED"* ]]
}

@test "the blocked message carries the verifier's own output, not just a code" {
    make_verifier 7
    run run_hook
    [[ "$output" == *"worktree missing for member alpha"* ]]
}

@test "a PASSING Phase 0 verify does not block (no over-blocking)" {
    make_verifier 0
    run run_hook
    [ "$status" -ne 2 ]
}
