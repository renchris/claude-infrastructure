#!/usr/bin/env bats
#
# curl-gate must be in scope inside reso's LINKED WORKTREES, not only its primary
# checkout. Measured 2026-08-10: reso had 64 live worktrees under
# ~/Development/.worktrees/, none of which share a prefix with PROJECT_ROOT, so
# `cwd.startswith(PROJECT_ROOT)` exited 0 with no decision in every one of them —
# every curl rule (pipe-to-shell, IMDS/private hosts, unsafe TLS, file://,
# sensitive uploads) was inert exactly where the work happens.
#
# Hermetic: builds its own fake primary checkout + linked worktree under BATS_TMPDIR
# and points the hook's PROJECT_ROOT at it, so nothing here depends on the operator's
# real repos, on how many worktrees exist, or on which terminal is running.

setup() {
    unset KITTY_WINDOW_ID ITERM_SESSION_ID
    export IT2_WRAPPER_NO_KITTY=1
    REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

    FAKE_ROOT="${BATS_TEST_TMPDIR}/reso-primary"
    FAKE_WT="${BATS_TEST_TMPDIR}/.worktrees/bs-thing"
    mkdir -p "$FAKE_ROOT/.git" "$FAKE_WT"
    # A linked worktree's .git is a FILE pointing at the owner's gitdir.
    printf 'gitdir: %s/.git/worktrees/bs-thing\n' "$FAKE_ROOT" > "$FAKE_WT/.git"

    # An unrelated project's worktree — must stay OUT of scope.
    OTHER_ROOT="${BATS_TEST_TMPDIR}/other-primary"
    OTHER_WT="${BATS_TEST_TMPDIR}/.worktrees/wt-other"
    mkdir -p "$OTHER_ROOT/.git" "$OTHER_WT"
    printf 'gitdir: %s/.git/worktrees/wt-other\n' "$OTHER_ROOT" > "$OTHER_WT/.git"

    GATE="${BATS_TEST_TMPDIR}/curl-gate.py"
    sed "s|^PROJECT_ROOT = .*|PROJECT_ROOT = \"${FAKE_ROOT}\"|" \
        "$REPO/hooks/curl-gate.py" > "$GATE"
}

probe() { # $1=cwd  $2=command
    # NOT PATH=/usr/bin:/bin. curl-gate.py uses PEP-604 (`int | None`) and so REQUIRES
    # python3.10+; macOS system python3 is 3.9 and cannot even parse it (TypeError at
    # import). Pinning /usr/bin here would test an interpreter production never uses and
    # report every case as "no decision" — i.e. it would look exactly like the fail-open
    # bug this suite exists to catch. Use the same python3 the hook chain resolves.
    printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"},"session_id":"t","tool_use_id":"t"}' \
        "$1" "$2" | python3 "$GATE" 2>&1
}

@test "PROJECT_ROOT substitution actually took (guards a vacuous suite)" {
    run grep -c "PROJECT_ROOT = \"${FAKE_ROOT}\"" "$GATE"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "the interpreter under test can actually run the gate (guards a false fail-open)" {
    run python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)'
    [ "$status" -eq 0 ]
}

@test "unsafe curl in a LINKED worktree is denied (the regression this pins)" {
    run probe "$FAKE_WT" "curl --insecure https://example.com"
    [[ "$output" == *'"permissionDecision": "deny"'* ]]
}

@test "unsafe curl in a SUBDIR of a linked worktree is denied" {
    mkdir -p "$FAKE_WT/src/deep"
    run probe "$FAKE_WT/src/deep" "curl --insecure https://example.com"
    [[ "$output" == *'"permissionDecision": "deny"'* ]]
}

@test "unsafe curl in the PRIMARY checkout is still denied (no regression)" {
    run probe "$FAKE_ROOT" "curl --insecure https://example.com"
    [[ "$output" == *'"permissionDecision": "deny"'* ]]
}

@test "an unrelated project's worktree stays OUT of scope (no over-reach)" {
    run probe "$OTHER_WT" "curl --insecure https://example.com"
    [ "$output" = "" ]
}

@test "a non-curl command in a linked worktree emits nothing" {
    run probe "$FAKE_WT" "echo hello"
    [ "$output" = "" ]
}
