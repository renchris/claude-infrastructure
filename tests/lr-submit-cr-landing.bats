#!/usr/bin/env bats
# 2026-09-22 — THE CR MUST LAND AS A SUBMIT, AND A SCREEN IT COULD NOT READ MUST NOT SPEND THE RETRY.
#
# THE INCIDENT. Sessions b6125384 and 2825e1e5 were transplanted correctly onto next2 and then sat
# TASK-LESS with their ingest prompt in the composer. Two independent defects, both here:
#
#   (1) THE CR LANDED AS TEXT. ba5e3c1e1 cut the inject settle gaps from 2/1/1 to 0.3/0.2/0.2, and
#       its own comment names what they are for — keeping the text and the CR from coalescing into
#       one paste the TUI reads as a single keystroke. A trailing CR inside a paste is a literal
#       NEWLINE. The signature is countable on the pane: an empty Claude Code composer renders
#       exactly ONE body row, and both stranded panes rendered the wrapped prompt PLUS a trailing
#       blank row.
#   (2) THE ONE RE-CR WAS SPENT ON A SCREEN NOBODY READ. The retry latch was set BEFORE the branch,
#       so the NOT-MEASURED arm (EMPTY/UNKNOWN — a TUI still painting) consumed the whole budget
#       without sending anything, and the loop never looked at the composer again. 4 of 4 runs that
#       reached this stage ended FAILED:submit; the two that recovered did so because a human
#       pressed Enter.
#
# THE TESTS ARE BEHAVIOURAL, not source greps: the two blocks are lifted out of the expect program
# by brace balance and EXECUTED under tclsh against stubs, so a refactor that preserves the
# behaviour keeps them green and one that loses it goes red.

setup() {
  # Hermeticity pins (test-hermeticity ratchet). Nothing here reads the operator's box on purpose —
  # the subject blocks are lifted out and run under tclsh against stubs — but the ratchet is a
  # SHAPE check, and a suite that has no reason to touch live state is exactly the one that must
  # say so. $HOME is fixtured so no future case can grow a dependency on the real one, and
  # capacity-admit is closed because its gate refuses on ambient load, memory and session census,
  # which would make this suite red-by-desk rather than by its subject.
  export CC_ADMIT_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  FIRE="$REPO/scripts/limit-recover/lr-fire-resume.sh"
  command -v tclsh >/dev/null || skip "tclsh not installed"
  EXP="$BATS_TEST_TMPDIR/exp.tcl"
  sed -n "/^expect -c '\$/,/^' ||/p" "$FIRE" | sed '1d;$d' > "$EXP"
  [ -s "$EXP" ] || { echo "extraction of the expect body from $FIRE failed" >&2; return 1; }
  LIFT="$BATS_TEST_TMPDIR/lift.py"
  cat > "$LIFT" <<'PY'
import sys
# Lift a brace-balanced block starting at the first LINE containing <anchor>. Counting is per LINE,
# not per character: `proc x {} {` dips back to depth 0 at its empty argument list mid-line, so a
# character-wise scan stops at the signature and lifts a body-less proc.
lines = open(sys.argv[1]).read().splitlines(True)
anchor = sys.argv[2]
start = next(i for i, l in enumerate(lines) if anchor in l)
out, depth, opened = [], 0, False
for l in lines[start:]:
    out.append(l)
    depth += l.count('{') - l.count('}')
    if depth > 0: opened = True
    if opened and depth == 0: break
sys.stdout.write(''.join(out))
PY
}

# Stubs shared by both cases: a scripted screen, a recording send, and inert notes.
stubs() {
  cat <<'TCL'
set SENT {}
set LOOKS 0
proc send {args} { global SENT; lappend SENT [lindex $args end] }
proc send_user {args} {}
proc lr_note {a b c} {}
proc sleep {n} {}
proc lr_screen {} { global SCREENS LOOKS; set v [lindex $SCREENS $LOOKS]; incr LOOKS
                    if {$v eq ""} { set v [lindex $SCREENS end] }; return $v }
array set env {}
TCL
}

@test "the CR is withheld until the composer has painted our draft" {
  python3 "$LIFT" "$EXP" "proc lr_submit_cr" > "$BATS_TEST_TMPDIR/proc.tcl"
  { stubs
    cat "$BATS_TEST_TMPDIR/proc.tcl"
    # composer is blank for three reads (a TUI still loading), then paints our draft
    echo 'set SCREENS {EMPTY EMPTY EMPTY DRAFT-MINE}'
    echo 'lr_submit_cr'
    echo 'puts "sent=[llength $SENT] looks=$LOOKS"'
  } > "$BATS_TEST_TMPDIR/t.tcl"
  run tclsh "$BATS_TEST_TMPDIR/t.tcl"
  [ "$status" -eq 0 ]
  # exactly one CR, and only after the draft was seen — a blind 0.2s sleep would have read 1 look.
  [ "$output" = "sent=1 looks=4" ]
}

@test "a parked menu forbids the CR outright" {
  python3 "$LIFT" "$EXP" "proc lr_submit_cr" > "$BATS_TEST_TMPDIR/proc.tcl"
  { stubs
    cat "$BATS_TEST_TMPDIR/proc.tcl"
    echo 'set SCREENS {MENU}'
    echo 'lr_submit_cr'
    echo 'puts "sent=[llength $SENT]"'
  } > "$BATS_TEST_TMPDIR/t.tcl"
  run tclsh "$BATS_TEST_TMPDIR/t.tcl"
  [ "$status" -eq 0 ]
  [ "$output" = "sent=0" ]
}

@test "an unreadable pane still gets its CR — the bound falls through, it does not withhold" {
  python3 "$LIFT" "$EXP" "proc lr_submit_cr" > "$BATS_TEST_TMPDIR/proc.tcl"
  { stubs
    cat "$BATS_TEST_TMPDIR/proc.tcl"
    echo 'set SCREENS {UNKNOWN}'
    echo 'lr_submit_cr'
    echo 'puts "sent=[llength $SENT]"'
  } > "$BATS_TEST_TMPDIR/t.tcl"
  run tclsh "$BATS_TEST_TMPDIR/t.tcl"
  [ "$status" -eq 0 ]
  [ "$output" = "sent=1" ]
}

@test "a NOT-MEASURED screen reschedules the look instead of spending the re-CR" {
  # The incident, replayed: nothing ever reaches the transcript, the composer reads EMPTY at the
  # first look (TUI still painting) and DRAFT-MINE at every look after it. The fixed loop must come
  # back and send the Enter; the old latched loop sends nothing for the whole 180s.
  python3 "$LIFT" "$EXP" 'for {set t 0} {$t < $deadline}' > "$BATS_TEST_TMPDIR/loop.tcl"
  { stubs
    echo 'proc lr_probe {t0} { return {none {}} }'
    echo 'set poll 30; set qmax 180; set deadline $poll; set verb skip; set ts ""'
    echo 'set recr 0; set recrmax 2; set nextlook [expr {$poll - 1}]; set unmeasured 0'
    echo 'set t0 0'
    echo 'set SCREENS {EMPTY DRAFT-MINE}'
    cat "$BATS_TEST_TMPDIR/loop.tcl"
    echo 'puts "sent=[llength $SENT]"'
  } > "$BATS_TEST_TMPDIR/t.tcl"
  run tclsh "$BATS_TEST_TMPDIR/t.tcl"
  [ "$status" -eq 0 ]
  # >=1 Enter re-sent. On trunk this is 0: the latch closed on the EMPTY read at t=29.
  [ "$output" != "sent=0" ]
}
