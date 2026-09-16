#!/usr/bin/env bats
# ============================================================================
#  tests/kitty-pane-graph.bats — THE DIFFER'S CONTROL SUITE (plan § W4)
#
#  🚨 WHY THIS SUITE EXISTS, AND WHY BRANCH (b) IS THE WHOLE POINT.
#  Last session the pane-graph READER was already controlled against a
#  known-good reorder and that control PASSED — because the bug was entirely
#  downstream of it, in the DIFFER.  So this suite controls the DIFFER, not
#  the reader (memory: `witness-must-test-the-set-before-the-order`).
#
#  CLOSING A PANE MAKES ITS TWO NEIGHBOURS ADJACENT.  A differ that tests
#  "did a surviving member's adjacency change?" BEFORE "is the member set the
#  same?" therefore calls an ordinary pane close a REORDER.  W4's whole job is
#  to witness a HUMAN ACTION — the one proof a session may not manufacture —
#  so that false positive fabricates exactly the evidence nobody else can check.
#
#  FIVE BRANCHES, fed as JSON fixtures so NO kitty is needed to run them:
#    (a) true reorder            -> REORDERED
#    (b) member closed           -> SET-CHANGED   <- THE ONLY ONE THAT FAILS PRE-FIX
#    (c) member opened           -> SET-CHANGED
#    (d) identical               -> NO-CHANGE
#    (e) a multi-id `neighbors` value that must parse correctly
#
#  PROOF THAT THE SUITE IS NOT DECORATIVE.  Move the order test above the set
#  test in diff_graphs() — the mutant — and branch (b) goes RED while (a),
#  (c), (d) and (e) stay green.  That asymmetry is the evidence; a suite in
#  which the mutant changes nothing credits no site at all (memory:
#  `per-site-mutation-attributes-coverage`).
#
#  WHY (c) SURVIVES THE MUTANT, STATED SO IT IS NOT MISTAKEN FOR A WEAKNESS.
#  Branch (c) opens the new pane in a DIFFERENT OS WINDOW, so no existing
#  member's adjacency is perturbed; the mutant's order test finds nothing moved
#  and falls through to the set test, reaching the right answer for the wrong
#  reason.  That is deliberate: it makes (b) the single discriminating branch,
#  so a green (b) is unambiguous about which test ran first.  A same-tab open
#  perturbs its neighbours and would redden under the mutant too — covered
#  incidentally by the real-data case in the header of scripts/kitty-pane-graph.py.
#
#  The `neighbors` shapes below are the MEASURED ones, not invented: read off a
#  sandbox kitty (own KITTY_CONFIG_DIRECTORY, socket outside /tmp/kitty-*, all
#  three KITTY_ vars dropped) on 2026-09-16 —
#      id 1 neighbors = {'bottom': [2, 3]}
#      id 2 neighbors = {'right': [3], 'top': [1]}
#      id 3 neighbors = {'left': [2], 'top': [1]}
#  Absent direction keys mean "no neighbour"; values are LISTS and may hold
#  more than one id.  That is branch (e).
#
#  KITTY_PANE_GRAPH_BIN overrides the subject under test.  It exists ONLY so a
#  mutant can be run from a scratch copy without touching the tracked file; it
#  defaults to the real script and production never sets it.
# ============================================================================

setup() {
    REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    KPG="${KITTY_PANE_GRAPH_BIN:-${REPO}/scripts/kitty-pane-graph.py}"
    FIX="${BATS_TEST_TMPDIR}"

    # ---- (a) TRUE REORDER: two stacked panes trade places. Set = {1,2}. ----
    cat > "${FIX}/a_before.json" <<'JSON'
[{"id": 1, "tabs": [{"id": 1, "layout": "splits", "windows": [
  {"id": 1, "neighbors": {"bottom": [2]}},
  {"id": 2, "neighbors": {"top": [1]}}
]}]}]
JSON
    cat > "${FIX}/a_after.json" <<'JSON'
[{"id": 1, "tabs": [{"id": 1, "layout": "splits", "windows": [
  {"id": 1, "neighbors": {"top": [2]}},
  {"id": 2, "neighbors": {"bottom": [1]}}
]}]}]
JSON

    # ---- (b) MEMBER CLOSED: pane 2 goes away. Its two neighbours, 1 and 3,
    #         become adjacent AS A CONSEQUENCE. A differ that tests order
    #         first reads that consequence as a move. Set = {1,2,3} -> {1,3}.
    cat > "${FIX}/b_before.json" <<'JSON'
[{"id": 1, "tabs": [{"id": 1, "layout": "splits", "windows": [
  {"id": 1, "neighbors": {"bottom": [2, 3]}},
  {"id": 2, "neighbors": {"top": [1], "right": [3]}},
  {"id": 3, "neighbors": {"top": [1], "left": [2]}}
]}]}]
JSON
    cat > "${FIX}/b_after.json" <<'JSON'
[{"id": 1, "tabs": [{"id": 1, "layout": "splits", "windows": [
  {"id": 1, "neighbors": {"bottom": [3]}},
  {"id": 3, "neighbors": {"top": [1]}}
]}]}]
JSON

    # ---- (c) MEMBER OPENED, in a SEPARATE OS WINDOW so no surviving member's
    #         adjacency changes. Set = {1,2} -> {1,2,7}. See the header for
    #         why this one is deliberately non-discriminating.
    cat > "${FIX}/c_before.json" <<'JSON'
[{"id": 1, "tabs": [{"id": 1, "layout": "splits", "windows": [
  {"id": 1, "neighbors": {"bottom": [2]}},
  {"id": 2, "neighbors": {"top": [1]}}
]}]}]
JSON
    cat > "${FIX}/c_after.json" <<'JSON'
[{"id": 1, "tabs": [{"id": 1, "layout": "splits", "windows": [
  {"id": 1, "neighbors": {"bottom": [2]}},
  {"id": 2, "neighbors": {"top": [1]}}
]}]},
 {"id": 2, "tabs": [{"id": 2, "layout": "splits", "windows": [
  {"id": 7, "neighbors": {}}
]}]}]
JSON

    # ---- (e) MULTI-ID neighbors value, the measured real shape. Panes 2 and 3
    #         swap sides under pane 1, whose bottom stays the two-id list.
    cat > "${FIX}/e_before.json" <<'JSON'
[{"id": 1, "tabs": [{"id": 1, "layout": "splits", "windows": [
  {"id": 1, "neighbors": {"bottom": [2, 3]}},
  {"id": 2, "neighbors": {"right": [3], "top": [1]}},
  {"id": 3, "neighbors": {"left": [2], "top": [1]}}
]}]}]
JSON
    cat > "${FIX}/e_after.json" <<'JSON'
[{"id": 1, "tabs": [{"id": 1, "layout": "splits", "windows": [
  {"id": 1, "neighbors": {"bottom": [3, 2]}},
  {"id": 2, "neighbors": {"left": [3], "top": [1]}},
  {"id": 3, "neighbors": {"right": [2], "top": [1]}}
]}]}]
JSON

    # ---- (e2) the SAME three panes, whole-tab move. Set is stable {1,2,3},
    #          so this is a REORDERED, and pane 1's rendered line must still
    #          carry BOTH ids of its multi-id `bottom` list.
    cat > "${FIX}/e_tab.json" <<'JSON'
[{"id": 1, "tabs": [{"id": 2, "layout": "splits", "windows": [
  {"id": 1, "neighbors": {"bottom": [2, 3]}},
  {"id": 2, "neighbors": {"right": [3], "top": [1]}},
  {"id": 3, "neighbors": {"left": [2], "top": [1]}}
]}]}]
JSON
}

# --- assertion helpers. Written so a failure RETURNS non-zero explicitly:
#     a bare `[[ ... ]]` is a dead assertion anywhere but the final line
#     (memory: `negated-assertion-dead-unless-final`).
want() {   # want <needle> -- asserts $output contains it
    case "$output" in
        *"$1"*) return 0 ;;
        *) echo "MISSING from output: $1" >&2; echo "--- output ---" >&2
           echo "$output" >&2; return 1 ;;
    esac
}
dont_want() {
    case "$output" in
        *"$1"*) echo "UNEXPECTED in output: $1" >&2; echo "--- output ---" >&2
                echo "$output" >&2; return 1 ;;
        *) return 0 ;;
    esac
}
rc_is() {
    if [ "$status" -ne "$1" ]; then
        echo "expected rc $1, got $status" >&2; echo "$output" >&2; return 1
    fi
    return 0
}

# =========================== (a) TRUE REORDER ==============================

@test "(a) true reorder: stable pane set with changed adjacency is REORDERED" {
    run python3 "$KPG" diff "${FIX}/a_before.json" "${FIX}/a_after.json"
    rc_is 0 || return 1
    want "verdict=REORDERED" || return 1
    want "moved: window 1" || return 1
    dont_want "verdict=SET-CHANGED" || return 1
}

@test "(a) true reorder satisfies --expect REORDERED" {
    run python3 "$KPG" diff "${FIX}/a_before.json" "${FIX}/a_after.json" --expect REORDERED
    rc_is 0 || return 1
    want "verdict=REORDERED"
}

# ============ (b) MEMBER CLOSED — THE ONLY PRE-FIX FAILURE =================

@test "(b) member closed: a pane close is NOT a reorder, it is SET-CHANGED" {
    # 🚨 THE DISCRIMINATING BRANCH. Pane 2 closes; panes 1 and 3 become
    # adjacent as a direct consequence. A differ that tests order before set
    # reports REORDERED here and fabricates a human action that never happened.
    run python3 "$KPG" diff "${FIX}/b_before.json" "${FIX}/b_after.json"
    rc_is 0 || return 1
    want "verdict=SET-CHANGED" || return 1
    dont_want "verdict=REORDERED" || return 1
}

@test "(b) member closed: names the gone pane and reports no moves" {
    run python3 "$KPG" diff "${FIX}/b_before.json" "${FIX}/b_after.json" --json
    rc_is 0 || return 1
    want '"gone"' || return 1
    want '"2"' || return 1
    want '"moved": []' || return 1
    dont_want "REORDERED"
}

@test "(b) member closed: --expect REORDERED must FAIL, rc 1" {
    # The inverse control. If the differ ever called this a reorder, this case
    # would pass rc 0 and the suite would be silently agreeing with the bug.
    run python3 "$KPG" diff "${FIX}/b_before.json" "${FIX}/b_after.json" --expect REORDERED
    rc_is 1 || return 1
    want "verdict=SET-CHANGED"
}

# =========================== (c) MEMBER OPENED =============================

@test "(c) member opened: a new pane is NOT a reorder, it is SET-CHANGED" {
    run python3 "$KPG" diff "${FIX}/c_before.json" "${FIX}/c_after.json"
    rc_is 0 || return 1
    want "verdict=SET-CHANGED" || return 1
    want "new:  7" || return 1
    dont_want "verdict=REORDERED"
}

# ============================= (d) IDENTICAL ===============================

@test "(d) identical documents are NO-CHANGE" {
    run python3 "$KPG" diff "${FIX}/a_before.json" "${FIX}/a_before.json"
    rc_is 0 || return 1
    want "verdict=NO-CHANGE" || return 1
    dont_want "verdict=REORDERED"
}

@test "(d) identical: a snapshot compares equal to the ls dump it came from" {
    python3 "$KPG" snapshot --ls "${FIX}/e_before.json" --out "${FIX}/e_snap.json"
    run python3 "$KPG" diff "${FIX}/e_before.json" "${FIX}/e_snap.json"
    rc_is 0 || return 1
    want "verdict=NO-CHANGE"
}

# ==================== (e) MULTI-ID neighbors VALUE =========================

@test "(e) a multi-id neighbors list parses and survives normalisation" {
    run python3 "$KPG" snapshot --ls "${FIX}/e_before.json"
    rc_is 0 || return 1
    # {"bottom": [2, 3]} -- two ids under one direction, the measured shape.
    want '"bottom"' || return 1
    want "2," || return 1
    want "3" || return 1
    dont_want "INSTRUMENT ERROR"
}

@test "(e) multi-id: id order inside one direction is not itself a move" {
    # before has bottom [2,3]; after spells the SAME pair as [3,2]. Pane 1 has
    # not moved. Panes 2 and 3 HAVE traded sides, so the verdict is REORDERED
    # and pane 1 must NOT appear among the moved members.
    run python3 "$KPG" diff "${FIX}/e_before.json" "${FIX}/e_after.json"
    rc_is 0 || return 1
    want "verdict=REORDERED" || return 1
    want "moved: window 2" || return 1
    want "moved: window 3" || return 1
    dont_want "moved: window 1"
}

@test "(e) multi-id renders both ids in the human line of a real move" {
    # The three panes move to another tab together. Set stable -> REORDERED,
    # and window 1's line must print the WHOLE two-id list, not just the head.
    run python3 "$KPG" diff "${FIX}/e_before.json" "${FIX}/e_tab.json"
    rc_is 0 || return 1
    want "verdict=REORDERED" || return 1
    want "bottom=[2, 3]" || return 1
    want "tab 1" || return 1
    want "tab 2"
}

# ================== INSTRUMENT CONTROLS (non-verdicts) =====================

@test "a parse failure is an INSTRUMENT ERROR at rc 2, never a quiet NO-CHANGE" {
    printf 'not json at all' > "${FIX}/broken.json"
    run python3 "$KPG" diff "${FIX}/broken.json" "${FIX}/a_after.json"
    rc_is 2 || return 1
    want "INSTRUMENT ERROR" || return 1
    dont_want "verdict=NO-CHANGE"
}

@test "an empty document is an error, not an empty layout" {
    : > "${FIX}/empty.json"
    run python3 "$KPG" diff "${FIX}/empty.json" "${FIX}/a_after.json"
    rc_is 2 || return 1
    want "is empty"
}

@test "an unknown neighbors direction is refused rather than silently dropped" {
    cat > "${FIX}/bogus.json" <<'JSON'
[{"id": 1, "tabs": [{"id": 1, "windows": [
  {"id": 1, "neighbors": {"diagonal": [2]}}
]}]}]
JSON
    run python3 "$KPG" diff "${FIX}/bogus.json" "${FIX}/a_after.json"
    rc_is 2 || return 1
    want "unknown neighbors direction"
}
