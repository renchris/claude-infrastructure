#!/usr/bin/env bats
# kitty-pane-menu-direction — the move-menu's "where is that window" clause, and specifically its
# behaviour when kitty windows are spread over MORE THAN ONE DISPLAY.
#
# WHAT BROKE, AND WHY IT LOOKED LIKE A REMOVED FEATURE RATHER THAN A BUG (2026-09-15). Space
# ordinals are per-display and are genuinely not comparable across monitors, so vector() answered a
# cross-display target with "" — the same value it uses for "this window is on no Space at all".
# other_targets() reads that "" as unplaceable and, correctly, strips the direction clause off
# EVERY row: a menu where some rows carry a swipe and some do not reads as "the unmarked ones are
# here", which is a wrong swipe. So ONE window on a second display silenced the clause on ALL of
# them. Attaching an external display above the built-in therefore deleted the feature outright,
# with no error, no empty string in the wrong place, and nothing to grep — the menu simply went
# back to `<name> — N panes`, which is exactly what a not-yet-built feature looks like.
#
# THE FIX IS A UNIT CHANGE, NOT A LOOSENING. The ordinals are still not comparable; what the probe
# now supplies is the DISPLAYS' own frames, so a cross-display row switches to naming the monitor
# ("on the display above") instead of going silent, and the all-or-nothing strip is left intact for
# rows that are genuinely unplaced. Case 9 pins that the strip still fires.
#
# NOTHING HERE TOUCHES THE OPERATOR'S REAL KITTY, A WINDOWSERVER, OR A SECOND MONITOR. Every case
# drives the two pure functions — parse_probe() and vector() — over synthetic probe text, which is
# the whole reason the parse was split out of reap_probe(): a two-display layout is not a fixture
# any CI box can be asked to have.
#
# Every assertion is `[ ]`, `run`+status, or `… || false`. `[[ ]]` and `(( ))` are errexit-EXEMPT in
# bats and are silently DEAD anywhere but a body's last line — that has burned this repo twice.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MENU="$REPO/bin/kitty-pane-menu"
  [ -f "$MENU" ]
  # EXPORTED, not merely set: every case reads it from a python SUBPROCESS, and an unexported
  # PROBE reaches that subprocess as a KeyError — which arrives as a non-zero status and reads
  # exactly like the assertion failing. Fixture plumbing that fails in the shape of the finding is
  # its own defect; this one cost a full run.
  export PROBE

  # THE SUBJECT READS $HOME, and not obviously: other_targets() → describe_os_window() →
  # _dir_set() → _true_cwd(), which opens ~/.claude/cc-registry/<window id>.json to get the CLAUDE
  # process's cwd rather than the shell's. Cases 8 and 9 build panes with ids 20/30/40, so on the
  # operator's live ~/ a registry file for any of those would silently change the label those
  # cases assert. Seeded empty, which is the state the fixture means: no registry, fall back to
  # the pane's own cwd.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/cc-registry"
}

# Run a python snippet with bin/kitty-pane-menu imported as module `m`. Imported by loader rather
# than by path-append because the file has no .py extension — the same reason a plain `import`
# cannot reach it and the reason these functions had never had a test before.
kpm() {
  MENU="$MENU" python3 - "$@" <<'PY'
import importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("kpm", os.environ["MENU"])
spec = importlib.util.spec_from_loader("kpm", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
exec(sys.argv[1])
PY
}

# The live shape, as measured 2026-09-15: built-in at the origin, the SOTSU ELITE16 arranged ABOVE
# it — which in CGDisplayBounds' top-left origin means the external's y is NEGATIVE. Display 1 is
# showing its desktop 2, display 2 its desktop 2.
PROBE='D	1	UUID-BUILTIN	0	0	1728	1117	2
D	2	UUID-EXTERNAL	-63	-1050	1680	1050	2
75301	1	1	0	pipeline productivity
79048	2	2	1	pane-title operator
110426	2	4	0	mac-bootstrap wave 3
116852	1	2	1	thinkpad comparison
119473	2	3	0	aria wireless'

@test "1 parse_probe reads the display table: frame and the desktop each display is showing" {
  run kpm 'p,n,d = m.parse_probe(os.environ["PROBE"]); print(len(d), d[1]["rect"], d[1]["cur"], d[2]["rect"], d[2]["cur"], d[2]["uuid"])'
  [ "$status" -eq 0 ]
  [ "$output" = "2 (0.0, 0.0, 1728.0, 1117.0) 2 (-63.0, -1050.0, 1680.0, 1050.0) 2 UUID-EXTERNAL" ]
}

@test "2 the display rows do not disturb the window rows beside them" {
  run kpm 'p,n,d = m.parse_probe(os.environ["PROBE"]); print(len(p), p[119473], n[119473], p[75301])'
  [ "$status" -eq 0 ]
  [ "$output" = "5 (2, 3) aria wireless (1, 1)" ]
}

@test "3 output from a helper that predates the display table still parses (places kept, displays empty)" {
  # The compiled helper is a build artifact that only moves on kitty-setup.sh --apply, while this
  # file is a symlink that goes live on a land. A new caller against an old binary is a REAL state,
  # not a hypothetical, and it must degrade to the old menu rather than to no menu.
  local old; old="$(printf '%s\n' "$PROBE" | grep -v '^D	')"
  OLD="$old" run kpm 'p,n,d = m.parse_probe(os.environ["OLD"]); print(len(p), len(n), len(d))'
  [ "$status" -eq 0 ]
  [ "$output" = "5 5 0" ]
}

@test "4 THE REGRESSION: a cross-display target gets a clause instead of the empty string" {
  # This is the assertion that was false. "" here is what the caller reads as unplaceable, and one
  # unplaceable row strips the clause from every row in the menu (case 9).
  run kpm 'p,n,d = m.parse_probe(os.environ["PROBE"]); v = m.vector(p[75301], p[119473], True, d); print(repr(v)); assert v != "", "cross-display target rendered no clause"'
  [ "$status" -eq 0 ]
  [ "$output" = "'on the display below, 1 desktop left'" ]
}

@test "5 the direction word follows the frames, in all four arrangements" {
  run kpm '
own = {"rect": (0.0, 0.0, 1728.0, 1117.0), "cur": 1}
for name, rect in (("above", (0.0, -1050.0, 1680.0, 1050.0)),
                   ("below", (0.0, 1117.0, 1680.0, 1050.0)),
                   ("left",  (-1680.0, 0.0, 1680.0, 1050.0)),
                   ("right", (1728.0, 0.0, 1680.0, 1050.0))):
    d = {1: own, 2: {"rect": rect, "cur": 1}}
    print(name, "->", m.vector((2, 1), (1, 1), True, d))
'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "above -> on the display above" ]
  [ "${lines[1]}" = "below -> on the display below" ]
  [ "${lines[2]}" = "left -> on the display to the left" ]
  [ "${lines[3]}" = "right -> on the display to the right" ]
}

@test "5b a taller display beside a shorter one is left/right, not above/below" {
  # Origins alone would call this vertical: a 1050-tall display sharing a top edge with a 1117-tall
  # one has the same y-origin, but centre it and the dominant axis is unambiguously horizontal.
  # The failure mode is a menu telling the operator to look up at a monitor beside them.
  run kpm '
d = {1: {"rect": (0.0, 0.0, 1728.0, 1117.0), "cur": 1},
     2: {"rect": (1728.0, 0.0, 1680.0, 1050.0), "cur": 1}}
print(m.vector((2, 1), (1, 1), True, d))'
  [ "$status" -eq 0 ]
  [ "$output" = "on the display to the right" ]
}

@test "5c a wide display directly above a narrow one is ABOVE, not sideways" {
  # THE CASE THAT KILLED THE FIRST IMPLEMENTATION. Deciding on frame CENTRES reads this as "to the
  # right", because a 4000-wide display overhead has its centre a full half-width away from a
  # 800-wide one — and the operator is sent looking sideways at a monitor that is over their head.
  # 5b cannot see this: two displays of similar width agree under centres, origins and gaps alike,
  # so it is decorative on the axis the metric is actually chosen for.
  run kpm '
d = {1: {"rect": (0.0, 0.0, 800.0, 600.0), "cur": 1},
     2: {"rect": (0.0, -600.0, 4000.0, 600.0), "cur": 1}}
print(m.vector((2, 1), (1, 1), True, d))
print(m.vector((1, 1), (2, 1), True, d))'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "on the display above" ]
  [ "${lines[1]}" = "on the display below" ]
}

@test "5d a diagonal arrangement takes the axis that separates them further" {
  # macOS permits a display placed up-and-to-the-side, where both axes separate and no single word
  # is uniquely true. The larger gap is the one the eye travels, and the rule has to be stated
  # rather than left to whichever comparison happened to be written first.
  run kpm '
d = {1: {"rect": (0.0, 0.0, 1728.0, 1117.0), "cur": 1},
     2: {"rect": (2000.0, -3000.0, 1000.0, 1000.0), "cur": 1}}
print(m.vector((2, 1), (1, 1), True, d))'
  [ "$status" -eq 0 ]
  [ "$output" = "on the display above" ]
}

@test "6 the cross-display swipe counts from THAT display's current desktop, not from our own" {
  # Our own ordinal has stopped being the origin the moment the eye is on another monitor. Our
  # window sits at desktop 3; the target at desktop 4 of a display showing desktop 2, so the swipe
  # is 2 right — NOT the 1 right that our own ordinal would have produced.
  run kpm '
d = {1: {"rect": (0.0, 0.0, 1728.0, 1117.0), "cur": 2},
     2: {"rect": (0.0, -1050.0, 1680.0, 1050.0), "cur": 3}}
print(m.vector((1, 4), (2, 3), True, d))'
  [ "$status" -eq 0 ]
  [ "$output" = "on the display below, 2 desktops right" ]
}

@test "6b a target already on the other display's current desktop asks for no swipe" {
  run kpm '
d = {1: {"rect": (0.0, 0.0, 1728.0, 1117.0), "cur": 2},
     2: {"rect": (0.0, -1050.0, 1680.0, 1050.0), "cur": 1}}
print(m.vector((1, 2), (2, 1), True, d))'
  [ "$status" -eq 0 ]
  [ "$output" = "on the display below" ]
}

@test "7 same-display wording is untouched by the change" {
  run kpm '
p, n, d = m.parse_probe(os.environ["PROBE"])
own = p[119473]
print(m.vector(p[79048], own, True, d))
print(m.vector(p[110426], own, True, d))
print(m.vector(own, own, True, d))
print(m.vector(p[79048], own, False, d))
print(m.vector(None, own, True, d))'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "1 desktop left" ]
  [ "${lines[1]}" = "1 desktop right" ]
  [ "${lines[2]}" = "here" ]
  [ "${lines[3]}" = "to the left" ]
  [ "${lines[4]}" = "" ]
}

@test "8 END TO END: a second display no longer strips the clause off the same-display rows" {
  # The defect was never confined to the cross-display row — one of those voided the whole menu.
  # Driving other_targets() is what pins that, because the strip lives there and not in vector().
  run kpm '
p, n, d = m.parse_probe(os.environ["PROBE"])
def osw(i, pwid, title):
    return {"id": i, "platform_window_id": pwid,
            "tabs": [{"is_active": True, "windows": [
                {"id": i * 10, "is_focused": True, "title": title, "cwd": "/tmp/x"}]}]}
tree = [osw(1, 119473, "aria wireless"), osw(2, 79048, "pane-title operator"),
        osw(3, 110426, "mac-bootstrap wave 3"), osw(4, 75301, "pipeline productivity")]
rows = m.other_targets(tree, 1, p, n, True, d)
for _wid, label, _src in rows:
    print(label)
assert all("," in lbl for _w, lbl, _s in rows), "a row lost its clause"'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "pane-title operator — 1 pane, 1 desktop left" ]
  [ "${lines[1]}" = "mac-bootstrap wave 3 — 1 pane, 1 desktop right" ]
  [ "${lines[2]}" = "pipeline productivity — 1 pane, on the display below, 1 desktop left" ]
}

@test "9 the all-or-nothing strip still fires for a genuinely unplaced window" {
  # The rule this fix must not loosen. A window on NO Space is unplaceable in a way no display
  # frame can rescue, and a half-marked menu is the wrong-swipe failure the rule exists to prevent.
  local probe; probe="$(printf '%s\n' "$PROBE" | sed 's/^75301\t1\t1\t/75301\t-\t-\t/')"
  P2="$probe" run kpm '
p, n, d = m.parse_probe(os.environ["P2"])
def osw(i, pwid, title):
    return {"id": i, "platform_window_id": pwid,
            "tabs": [{"is_active": True, "windows": [
                {"id": i * 10, "is_focused": True, "title": title, "cwd": "/tmp/x"}]}]}
tree = [osw(1, 119473, "aria wireless"), osw(2, 79048, "pane-title operator"),
        osw(4, 75301, "pipeline productivity")]
rows = m.other_targets(tree, 1, p, n, True, d)
for _wid, label, _src in rows:
    print(label)'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "pane-title operator — 1 pane" ]
  [ "${lines[1]}" = "pipeline productivity — 1 pane" ]
}

@test "10 mirrored displays get no direction word, because none is true" {
  run kpm '
d = {1: {"rect": (0.0, 0.0, 1728.0, 1117.0), "cur": 1},
     2: {"rect": (0.0, 0.0, 1728.0, 1117.0), "cur": 1}}
v = m.vector((2, 1), (1, 1), True, d)
print(v)
assert v != "", "a mirrored display is still a placement"'
  [ "$status" -eq 0 ]
  [ "$output" = "on another display" ]
}

@test "11 an unresolvable frame degrades one clause, not the row" {
  # The Swift side emits "-" per missing field rather than dropping the row, so a display whose
  # frame CGDisplayBounds would not give up still contributes a placement and a swipe.
  local probe; probe="$(printf '%s\n' "$PROBE" | sed 's|^D\t1\tUUID-BUILTIN\t0\t0\t1728\t1117\t2|D\t1\tUUID-BUILTIN\t-\t-\t-\t-\t2|')"
  P3="$probe" run kpm '
p, n, d = m.parse_probe(os.environ["P3"])
print(d[1]["rect"])
print(m.vector(p[75301], p[119473], True, d))'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "None" ]
  [ "${lines[1]}" = "on another display, 1 desktop left" ]
}

@test "12 with no display table at all, a cross-display target is still PLACED" {
  # The old-binary case, which is the one that must not reintroduce the bug: no frames means no
  # direction word, but "on another display" is a placement, so the strip stays off the other rows.
  local old; old="$(printf '%s\n' "$PROBE" | grep -v '^D	')"
  OLD="$old" run kpm '
p, n, d = m.parse_probe(os.environ["OLD"])
print(m.vector(p[75301], p[119473], True, d))'
  [ "$status" -eq 0 ]
  [ "$output" = "on another display" ]
}

@test "13 the plist source names the display but never a count off it" {
  # The plist is a stale cache measured three-of-five ordinals wrong; the sign survives staleness,
  # a remote display's current-Space delta does not, and it carries no frames either.
  run kpm 'print(m.vector((2, 4), (1, 1), False, {}))'
  [ "$status" -eq 0 ]
  [ "$output" = "on another display" ]
}

@test "14 the caller can tell an old helper from a macOS that withheld the frames" {
  # Two indistinguishable outputs, one fixable by --apply and one not. Only the marker separates
  # them, which is why --check reports it.
  run kpm 'print(m._GEOM_MARKER.decode(), m._PROBE_MARKER.decode())'
  [ "$status" -eq 0 ]
  [ "$output" = "KPM-DISPLAY-GEOM-V1 KPM-WINDOWS-MODE-V1" ]
  # >15 UTF-8 bytes or the small-string optimisation keeps it out of the compiled string table and
  # the capability test silently reads every new binary as old — measured, and the reason the first
  # marker was renamed.
  run kpm 'print(len(m._GEOM_MARKER))'
  [ "$output" -gt 15 ]
  grep -q 'KPM-DISPLAY-GEOM-V1' "$REPO/bin/kitty-pane-menu-native.swift" || false
}
