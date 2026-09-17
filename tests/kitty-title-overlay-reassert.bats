#!/usr/bin/env bats
# The overlay's HOLD path must not churn kitty's image store.
#
# WHY THIS SUITE EXISTS. Holding the titles up means re-asserting them on a timer, because
# kitty frees a placement whenever its anchoring cells are cleared or scrolled away and
# never says so. The original hold path re-asserted with the FULL `place()` payload --
# `a=d` (delete the image, data included) then `a=T` (retransmit from file) -- once per
# pane per 0.35s tick. MEASURED 2026-09-16 on the operator's live kitty, 6 panes:
#
#     titles ON   kitty RSS +0.93 MB/s, CPU +6.8pp; after `off`, 21.8 MB never returned
#                 (190.9 MB baseline -> 212.7 MB settled after ONE 17-second hold)
#
# and in an isolated sandbox kitty, 40 cycles/arm at 0.35s, two bracketing idle controls
# both flat at +0K, reproduced twice:
#
#     control  +0K              0.0% of a core
#     place()  +1008K/+1344K    1.0%          <- delete+retransmit
#     a=p      -16K             0.1%          <- re-assert only
#
# After the fix, same live kitty, 30s arms back to back with the strips genuinely
# painting: ON cost +0.53pp of CPU and RSS was FLAT (-16K).
#
# So the invariant is: an UNCHANGED strip on the hold path costs one `a=p` and nothing
# else. These cases pin that, and each one is paired with a mutant below, because a suite
# that only asserts the happy path credits no site.

setup() {
    REPO="${BATS_TEST_DIRNAME}/.."
    SUBJECT="${REPO}/scripts/kitty-pane-title-overlay.py"
    PY="$(command -v python3)"
    [ -n "$PY" ] || skip "no python3"
    [ -r "$SUBJECT" ] || skip "subject not readable: $SUBJECT"
    # FIXTURE $HOME. The subject computes AUTONOMY/LOG/STATE/SOCK from os.path.expanduser
    # at import, so an unfixtured run resolves them into the operator's live
    # ~/.claude/autonomy -- where a daemon is using those very paths. Pointing HOME at the
    # per-test tmpdir makes every one of those resolve inside it instead.
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME/.claude/autonomy"
    # Per-test strip dir for the same reason, and because a fixed /tmp string is a
    # collision between two concurrent runs rather than a fixture.
    export OV_STRIPDIR="$BATS_TEST_TMPDIR/strips"
}

# Drive paint_frames() against a fake tty-writer so we can read the exact bytes it would
# have written. The module is loaded by PATH rather than imported, because it is a script
# and not a package.
_harness() {
    local mode="$1"          # first|repeat|changed|after_clear
    "$PY" - "$SUBJECT" "$mode" <<'PY'
import importlib.util, os, sys

path, mode = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("ov", path)
ov = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ov)

WRITES = []
ov._tty_write = lambda tty, payload, budget=0.0: (WRITES.append(payload), True)[1]
# Keep the strip off disk: place() writes a PNG file, and a test must not depend on a
# writable STRIPDIR in whatever environment the gate runs in.
ov.STRIPDIR = os.environ["OV_STRIPDIR"]

PNG_A = b"\x89PNG\r\n\x1a\n" + b"A" * 64
PNG_B = b"\x89PNG\r\n\x1a\n" + b"B" * 64
IID = 7101
TTY = "/dev/null"

ov._HOLD_TICK = 1          # not a multiple of FULL_EVERY -> no self-heal this tick
ov.paint_frames([(TTY, PNG_A, IID)], budget=5.0, force=True)   # the press: full transmit
first = b"".join(WRITES); WRITES.clear()

if mode == "first":
    out = first
else:
    if mode == "after_clear":
        ov.clear(TTY, IID, budget=5.0)
        WRITES.clear()
    png = PNG_B if mode == "changed" else PNG_A
    ov._HOLD_TICK = 1
    ov.paint_frames([(TTY, png, IID)], budget=5.0)             # the hold tick
    out = b"".join(WRITES)

print("TRANSMIT" if b"a=T" in out else "-", "DELETE" if b"a=d" in out else "-",
      "PLACE" if b"a=p" in out else "-")
PY
}

@test "a press transmits in full (delete + retransmit), so it survives a freed image" {
    run _harness first
    [ "$status" -eq 0 ]
    [[ "$output" == "TRANSMIT DELETE -" ]]
}

@test "the hold path re-asserts an UNCHANGED strip with a=p and never retransmits" {
    # THE LOAD-BEARING CASE. If this regresses, kitty grows ~0.93 MB/s while titles are up.
    run _harness repeat
    [ "$status" -eq 0 ]
    [[ "$output" == "- - PLACE" ]]
}

@test "a CHANGED strip still forces a full transmit" {
    # kitty keys image DATA by id and ignores new bytes under an id it already holds, so a
    # restyle that took the cheap path would be silently invisible -- the exact defect the
    # subject's own DELETE FIRST note records.
    run _harness changed
    [ "$status" -eq 0 ]
    [[ "$output" == "TRANSMIT DELETE -" ]]
}

@test "after clear() the next paint transmits, because d=I freed the data" {
    # clear() sends d=I, which frees the image itself and not merely the placement. If
    # _SENT still remembered it, the next paint would re-assert against nothing and the
    # strip would be silently blank.
    run _harness after_clear
    [ "$status" -eq 0 ]
    [[ "$output" == "TRANSMIT DELETE -" ]]
}

# ── mutants: each removes ONE cure and must redden a DIFFERENT case ────────────────────
# A green suite credits no site, so every cure above is shown to be load-bearing by
# deleting it and watching the specific case that guards it go red.

_mutate() {
    local sed_expr="$1" mode="$2"
    local mdir; mdir="$(mktemp -d)"
    cp "$SUBJECT" "$mdir/mutant.py"
    /usr/bin/sed -i '' "$sed_expr" "$mdir/mutant.py"
    # Prove the mutation actually applied; a sed that matched nothing would leave the
    # subject intact and the mutant would "survive" for no reason at all.
    if cmp -s "$SUBJECT" "$mdir/mutant.py"; then
        echo "MUTATION-DID-NOT-APPLY"; rm -rf "$mdir"; return 0
    fi
    local saved="$SUBJECT"
    SUBJECT="$mdir/mutant.py" _harness "$mode"
    SUBJECT="$saved"
    rm -rf "$mdir"
}

@test "MUTANT: hold path always full-transmits -> the re-assert case goes red" {
    # This is the pre-fix implementation, restored exactly: no cheap branch at all.
    run _mutate 's/^        if heal or changed:$/        if True:/' repeat
    [ "$status" -eq 0 ]
    [[ "$output" != "MUTATION-DID-NOT-APPLY" ]] || false
    [[ "$output" != "- - PLACE" ]] || false # the guarded case no longer holds
    [[ "$output" == "TRANSMIT DELETE -" ]]
}

@test "MUTANT: clear() keeps its _SENT entry -> the after-clear case goes red" {
    run _mutate 's/^    _SENT.pop(img_id, None)$/    pass/' after_clear
    [ "$status" -eq 0 ]
    [[ "$output" != "MUTATION-DID-NOT-APPLY" ]] || false
    [[ "$output" == "- - PLACE" ]]      # re-asserts against an image kitty already freed
}
