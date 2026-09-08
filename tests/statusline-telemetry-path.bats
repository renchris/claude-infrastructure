#!/usr/bin/env bats
# statusline-telemetry-path — the telemetry export must survive a session that did not inherit
# the launching shell's PATH (backlog 5c646048e05e).
#
# THE DEFECT. Every jq-using block in statusline.sh is gated on `command -v jq`. A `--resume`d
# session does not inherit the launching shell's PATH, so on this box those panes run with
# PATH=/usr/bin:/bin:/usr/sbin:/sbin (plus a kitty or aftman prefix) while jq lives in
# /opt/homebrew/bin. The gate then fails, the telemetry export is skipped, and no
# /tmp/cc-telemetry/<sid>.json is ever written — so lead-supervisor's DEAD / STALL? /
# PAST-THRESHOLD pages and the permission beacon, which all iterate that directory, are blind to
# the pane. Measured 2026-09-08 with a clean control: 5 of 5 live `--resume` panes whose PATH
# lacked /opt/homebrew/bin had no row; every pane whose PATH carried it had one.
#
# WHY IT WAS INVISIBLE. The gate is a `command -v`, not an error path. A pane with no jq renders a
# completely normal statusline and simply publishes nothing, which on screen is indistinguishable
# from a healthy pane. The only observable is an ABSENCE in a directory nobody looks at directly.
#
# HARNESS LAWS. L1 — the subject runs with a PATH that genuinely lacks jq, built by REMOVING the
# real jq directory rather than by asserting a literal, so it cannot go stale against a moved
# toolchain. L2 — test 2 is the CONTROL and it is the whole point: it replays the PRE-FIX script
# from origin/main under byte-identical conditions and requires it to write NOTHING. Without it a
# green test 1 could mean "the fix works" or "the fixture never removed jq in the first place", and
# those are the two states this suite exists to separate. L3 — test 3 pins the coverage claim: the
# fallback list must contain the directory jq ACTUALLY occupies on this box, so a toolchain that
# moves fails loudly here instead of silently re-opening the hole in production.

setup() {
    REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    SUBJ="$REPO/statusline.sh"
    # Hermetic $HOME. The subject reads $HOME for its own fallback list and for session state, and
    # an unfixtured run would consult the operator's live ~/. Nothing this suite asserts lives under
    # HOME — the telemetry directory is pinned by CC_TELEMETRY_DIR and jq is found by PATH — so an
    # empty fixture home is the honest environment, not a stub of one.
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    TD="$BATS_TEST_TMPDIR/telem"
    mkdir -p "$TD"
    JQ_REAL="$(command -v jq || true)"
    JQ_DIR="${JQ_REAL%/*}"
    # A PATH with every jq-bearing directory removed — derived, never a literal (L1).
    STRIPPED=""
    local IFS=:
    for d in $PATH; do
        [ -n "$d" ] || continue
        [ -x "$d/jq" ] && continue
        STRIPPED="${STRIPPED:+$STRIPPED:}$d"
    done
    PAYLOAD='{"session_id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      "transcript_path":"/Users/x/.claude/projects/p/t.jsonl","cwd":"/tmp",
      "model":{"id":"claude-opus-5"},"effort":{"level":"high"},
      "context_window":{"context_window_size":1000000,"used_percentage":18,
      "remaining_percentage":82,"total_input_tokens":177023},"exceeds_200k_tokens":false}'
    ROW="$TD/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.json"
}

# The fixture must actually reach the regime under test: a PATH that still finds jq would make
# every case below pass for the wrong reason.
@test "fixture: the stripped PATH genuinely cannot find jq" {
    [ -n "$JQ_REAL" ]
    run env -i HOME="$HOME" PATH="$STRIPPED" sh -c 'command -v jq'
    [ "$status" -ne 0 ]
}

@test "a session with no jq on PATH still publishes its telemetry row" {
    printf '%s' "$PAYLOAD" | env HOME="$HOME" PATH="$STRIPPED" CC_TELEMETRY_DIR="$TD" \
        bash "$SUBJ" >/dev/null 2>&1 || true
    [ -f "$ROW" ]
    run env PATH="$JQ_DIR:$PATH" jq -r '.session_id' "$ROW"
    [ "$status" -eq 0 ]
    [ "$output" = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" ]
}

# THE CONTROL (L2). Replays the pre-fix script from git — never a hand-copy — and requires it to
# write nothing under byte-identical conditions. This is what proves the case above is not vacuous.
@test "CONTROL: the pre-fix script writes NO row under the same stripped PATH" {
    local base="$BATS_TEST_TMPDIR/pre-fix-statusline.sh"
    # A LITERAL sha, never `origin/main`. A moving ref advances past this fix the moment it lands,
    # and the control then compares the fix to itself — passing vacuously for a reason that has
    # nothing to do with what it asserts. PRE_FIX is the trunk tip immediately before the fix
    # landed; it is an ancestor of trunk forever, so the replay is reproducible on any checkout.
    local PRE_FIX=a432e823bb19e01aa2dfc5595703d4514480f058
    git -C "$REPO" show "$PRE_FIX:statusline.sh" > "$base" || fail "pre-fix blob $PRE_FIX unreadable"
    # MARKER, derived from the two artifacts' MEASURED diff (0 occurrences pre, 3 post) and not
    # from either file's prose: `_jqd` is the loop variable the fix introduces. Its ABSENCE is what
    # proves this replay is really the pre-fix artifact and not a re-pointed sha carrying the cure.
    run grep -c '_jqd' "$base"
    [ "$output" = "0" ]
    local td2="$BATS_TEST_TMPDIR/telem2"; mkdir -p "$td2"
    printf '%s' "$PAYLOAD" | env HOME="$HOME" PATH="$STRIPPED" CC_TELEMETRY_DIR="$td2" \
        bash "$base" >/dev/null 2>&1 || true
    [ ! -f "$td2/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.json" ]
}

@test "the declared fallback list covers where jq actually lives on this box" {
    [ -n "$JQ_DIR" ]
    run grep -c -- "$JQ_DIR/jq\|for _jqd in .*$JQ_DIR" "$SUBJ"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
